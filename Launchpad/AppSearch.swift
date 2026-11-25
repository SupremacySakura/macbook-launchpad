import Foundation

enum AppSearch {
    static func filter(_ apps: [App], query: String) -> [App] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return apps }
        return AppSearchIndex(apps: apps).filter(query: trimmed)
    }
}

struct AppSearchIndex: Sendable {
    private let entries: [Entry]

    init(apps: [App]) {
        self.entries = apps.enumerated().map { index, app in
            Entry(app: app, originalIndex: index)
        }
    }

    func filter(query: String) -> [App] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return entries.map(\.app)
        }

        let foldedQuery = Self.fold(trimmed)
        let tokens = foldedQuery
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        let compactQuery = Self.compact(foldedQuery)

        guard !tokens.isEmpty else {
            return entries.map(\.app)
        }

        var scored: [(app: App, score: Int, originalIndex: Int)] = []
        scored.reserveCapacity(min(entries.count, 32))

        for entry in entries {
            if let score = entry.matchScore(
                fullQuery: foldedQuery,
                compactQuery: compactQuery,
                tokens: tokens
            ) {
                scored.append((entry.app, score, entry.originalIndex))
            }
        }

        scored.sort { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.originalIndex < rhs.originalIndex
        }

        return scored.map(\.app)
    }

    // MARK: - Indexed Entry & Candidates

    private struct Entry: Sendable {
        let app: App
        let originalIndex: Int
        let candidates: [Candidate]

        init(app: App, originalIndex: Int) {
            self.app = app
            self.originalIndex = originalIndex

            var built: [Candidate] = []
            var seenFolded = Set<String>()

            func appendCandidate(_ raw: String, isPrimary: Bool) {
                let candidate = Candidate(text: raw, isPrimary: isPrimary)
                guard !candidate.folded.isEmpty else { return }
                if seenFolded.insert("\(isPrimary ? "P" : "A")|\(candidate.folded)").inserted {
                    built.append(candidate)
                }

                if AppSearchIndex.containsCJK(raw) {
                    let (fullPinyin, initials) = AppSearchIndex.pinyinForms(for: raw)
                    if !fullPinyin.isEmpty {
                        let pinyinCandidate = Candidate(text: fullPinyin, isPrimary: false)
                        if !pinyinCandidate.folded.isEmpty,
                           seenFolded.insert("A|\(pinyinCandidate.folded)").inserted {
                            built.append(pinyinCandidate)
                        }
                    }
                    if initials.count >= 2 {
                        let initialsCandidate = Candidate(text: initials, isPrimary: false)
                        if !initialsCandidate.folded.isEmpty,
                           seenFolded.insert("A|\(initialsCandidate.folded)").inserted {
                            built.append(initialsCandidate)
                        }
                    }
                }
            }

            appendCandidate(app.name, isPrimary: true)
            for alias in app.searchAliases {
                appendCandidate(alias, isPrimary: false)
            }

            self.candidates = built
        }

        func matchScore(fullQuery: String, compactQuery: String, tokens: [String]) -> Int? {
            if tokens.count == 1 {
                let token = tokens[0]
                let tokenChars = Array(token)
                let compactChars = Array(compactQuery)
                var bestScore: Int?

                for candidate in candidates {
                    if let rawScore = candidate.scoreSingleToken(
                        query: token,
                        queryChars: tokenChars,
                        compactQuery: compactQuery,
                        compactQueryChars: compactChars
                    ) {
                        let total = rawScore + (candidate.isPrimary ? 60 : 0)
                        if bestScore == nil || total > bestScore! {
                            bestScore = total
                        }
                    }
                }
                return bestScore
            }

            var bestMultiScore: Int?

            // Option A: Each token matches at least one candidate (same or different)
            var tokenSum = 0
            var allMatched = true
            for token in tokens {
                let tokenChars = Array(token)
                let tokenCompact = AppSearchIndex.compact(token)
                let tokenCompactChars = Array(tokenCompact)
                var tokenBest: Int?

                for candidate in candidates {
                    if let rawScore = candidate.scoreSingleToken(
                        query: token,
                        queryChars: tokenChars,
                        compactQuery: tokenCompact,
                        compactQueryChars: tokenCompactChars
                    ) {
                        let total = rawScore + (candidate.isPrimary ? 40 : 0)
                        if tokenBest == nil || total > tokenBest! {
                            tokenBest = total
                        }
                    }
                }

                if let tokenBest {
                    tokenSum += tokenBest
                } else {
                    allMatched = false
                    break
                }
            }

            if allMatched {
                bestMultiScore = tokenSum / tokens.count
            }

            // Option B: All tokens match the same single candidate (bonus for coherence)
            let tokenInputs = tokens.map { token -> (String, [Character], String, [Character]) in
                let c = AppSearchIndex.compact(token)
                return (token, Array(token), c, Array(c))
            }

            for candidate in candidates {
                var sum = 0
                var matchedAllOnSame = true
                for (t, tChars, tc, tcChars) in tokenInputs {
                    if let s = candidate.scoreSingleToken(
                        query: t,
                        queryChars: tChars,
                        compactQuery: tc,
                        compactQueryChars: tcChars
                    ) {
                        sum += s
                    } else {
                        matchedAllOnSame = false
                        break
                    }
                }
                if matchedAllOnSame {
                    let coherentScore = (sum / tokens.count) + 50 + (candidate.isPrimary ? 50 : 0)
                    if bestMultiScore == nil || coherentScore > bestMultiScore! {
                        bestMultiScore = coherentScore
                    }
                }

                // Option C: Compact query directly matches compact candidate (e.g. "vs code" vs "vscode")
                if !compactQuery.isEmpty {
                    let compactChars = Array(compactQuery)
                    if let s = candidate.scoreSingleToken(
                        query: compactQuery,
                        queryChars: compactChars,
                        compactQuery: compactQuery,
                        compactQueryChars: compactChars
                    ) {
                        let total = s + (candidate.isPrimary ? 60 : 0)
                        if bestMultiScore == nil || total > bestMultiScore! {
                            bestMultiScore = total
                        }
                    }
                }
            }

            return bestMultiScore
        }
    }

    private struct Candidate: Sendable {
        let isPrimary: Bool
        let folded: String
        let chars: [Character]
        let boundaryFlags: [Bool]
        let compact: String
        let compactChars: [Character]
        let compactBoundaryFlags: [Bool]
        let words: [[Character]]

        init(text: String, isPrimary: Bool) {
            self.isPrimary = isPrimary

            var builtChars: [Character] = []
            var builtBoundaries: [Bool] = []
            var compactBuiltChars: [Character] = []
            var compactBuiltBoundaries: [Bool] = []

            var previousWasSeparator = true
            var previousWasLowerOrDigit = false
            var builtFolded = ""
            var builtCompact = ""

            for ch in text {
                let isSeparator = ch.isWhitespace || ch == "-" || ch == "_" || ch == "." || ch == "/"
                let isBoundary = previousWasSeparator || (previousWasLowerOrDigit && ch.isUppercase)

                let foldedSlice = String(ch)
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                    .lowercased()

                for (offset, fch) in foldedSlice.enumerated() {
                    let charBoundary = (offset == 0) && isBoundary && !isSeparator
                    builtChars.append(fch)
                    builtBoundaries.append(charBoundary)
                    builtFolded.append(fch)

                    if !isSeparator {
                        compactBuiltChars.append(fch)
                        compactBuiltBoundaries.append(charBoundary)
                        builtCompact.append(fch)
                    }
                }

                previousWasSeparator = isSeparator
                previousWasLowerOrDigit = ch.isLowercase || ch.isNumber
            }

            self.folded = builtFolded
            self.chars = builtChars
            self.boundaryFlags = builtBoundaries
            self.compact = builtCompact
            self.compactChars = compactBuiltChars
            self.compactBoundaryFlags = compactBuiltBoundaries
            self.words = builtFolded
                .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "_" || $0 == "." || $0 == "/" })
                .map { Array($0) }
        }

        func scoreSingleToken(
            query: String,
            queryChars: [Character],
            compactQuery: String,
            compactQueryChars: [Character]
        ) -> Int? {
            guard !queryChars.isEmpty else { return nil }

            // 1. Exact match
            if folded == query || (!compactQuery.isEmpty && compact == compactQuery) {
                return 1000
            }

            // 2. Prefix match
            if folded.hasPrefix(query) {
                let compactnessBonus = max(0, 40 - max(0, chars.count - queryChars.count))
                return 860 + compactnessBonus
            }
            if !compactQuery.isEmpty && compact.hasPrefix(compactQuery) {
                let compactnessBonus = max(0, 35 - max(0, compactChars.count - compactQueryChars.count))
                return 845 + compactnessBonus
            }

            // 3. Word-boundary contiguous substring match
            if let boundaryIndex = firstBoundarySubstringIndex(of: queryChars, in: chars, boundaries: boundaryFlags) {
                let positionPenalty = min(30, boundaryIndex * 2)
                return 780 - positionPenalty
            }

            // 4. Contiguous substring match
            if let range = folded.range(of: query) {
                let offset = folded.distance(from: folded.startIndex, to: range.lowerBound)
                return 700 - min(40, offset * 2)
            }
            if !compactQuery.isEmpty, let range = compact.range(of: compactQuery) {
                let offset = compact.distance(from: compact.startIndex, to: range.lowerBound)
                return 685 - min(40, offset * 2)
            }

            // Single character queries only match prefix or contiguous substring
            guard queryChars.count >= 2 else { return nil }

            // 5. Ordered subsequence fuzzy match
            if let subScore = scoreSubsequence(
                queryChars: queryChars,
                targetChars: chars,
                boundaries: boundaryFlags
            ) {
                return subScore
            }

            if !compactQueryChars.isEmpty, compactQueryChars.count >= 2,
               let subScore = scoreSubsequence(
                queryChars: compactQueryChars,
                targetChars: compactChars,
                boundaries: compactBoundaryFlags
               ) {
                return subScore - 10
            }

            // 6. Typo-tolerant Damerau-Levenshtein fallback (4+ chars)
            if queryChars.count >= 4 {
                return scoreTypoTolerance(queryChars: queryChars, compactQueryChars: compactQueryChars)
            }

            return nil
        }

        private func firstBoundarySubstringIndex(
            of needle: [Character],
            in haystack: [Character],
            boundaries: [Bool]
        ) -> Int? {
            guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
            let limit = haystack.count - needle.count
            for start in 0...limit {
                guard boundaries[start] else { continue }
                var matched = true
                for offset in 0..<needle.count {
                    if haystack[start + offset] != needle[offset] {
                        matched = false
                        break
                    }
                }
                if matched {
                    return start
                }
            }
            return nil
        }

        private func scoreSubsequence(
            queryChars: [Character],
            targetChars: [Character],
            boundaries: [Bool]
        ) -> Int? {
            let qLen = queryChars.count
            let tLen = targetChars.count
            guard qLen >= 2, tLen >= qLen else { return nil }

            struct Alignment {
                var score: Int
                var firstIdx: Int
                var lastIdx: Int
                var boundaryHits: Int
                var consecutiveHits: Int
            }

            var prevRow = [Alignment?](repeating: nil, count: tLen)
            for ti in 0..<tLen where targetChars[ti] == queryChars[0] {
                let isBoundary = boundaries[ti]
                prevRow[ti] = Alignment(
                    score: (ti == 0 ? 30 : 0) + (isBoundary ? 28 : 0) - ti,
                    firstIdx: ti,
                    lastIdx: ti,
                    boundaryHits: isBoundary ? 1 : 0,
                    consecutiveHits: 0
                )
            }

            for qi in 1..<qLen {
                var currRow = [Alignment?](repeating: nil, count: tLen)
                var bestPrev: Alignment?

                for ti in 0..<tLen {
                    if let candidatePrev = prevRow[ti] {
                        // Track best previous alignment strictly before next ti, updated after checking targetChars[ti]
                        _ = candidatePrev
                    }

                    if ti > 0, let prevAtEarlier = prevRow[ti - 1] {
                        if bestPrev == nil || prevAtEarlier.score > bestPrev!.score {
                            bestPrev = prevAtEarlier
                        }
                    }

                    guard targetChars[ti] == queryChars[qi] else { continue }

                    // Check direct consecutive predecessor first, and overall best predecessor
                    var chosen: Alignment?

                    if ti > 0, let consecPrev = prevRow[ti - 1] {
                        let isBoundary = boundaries[ti]
                        let candidate = Alignment(
                            score: consecPrev.score + 32 + (isBoundary ? 22 : 0),
                            firstIdx: consecPrev.firstIdx,
                            lastIdx: ti,
                            boundaryHits: consecPrev.boundaryHits + (isBoundary ? 1 : 0),
                            consecutiveHits: consecPrev.consecutiveHits + 1
                        )
                        chosen = candidate
                    }

                    if let nonConsecPrev = bestPrev {
                        let gap = ti - nonConsecPrev.lastIdx - 1
                        let isBoundary = boundaries[ti]
                        let isConsec = gap == 0
                        let delta = (isConsec ? 32 : -min(18, gap * 2)) + (isBoundary ? 24 : 0)
                        let candidate = Alignment(
                            score: nonConsecPrev.score + delta,
                            firstIdx: nonConsecPrev.firstIdx,
                            lastIdx: ti,
                            boundaryHits: nonConsecPrev.boundaryHits + (isBoundary ? 1 : 0),
                            consecutiveHits: nonConsecPrev.consecutiveHits + (isConsec ? 1 : 0)
                        )
                        if chosen == nil || candidate.score > chosen!.score {
                            chosen = candidate
                        }
                    }

                    currRow[ti] = chosen
                }

                prevRow = currRow
            }

            // For 2-character queries that are not contiguous, require both hits on word/CamelCase boundaries
            let requiresAllBoundaries = qLen == 2

            var bestFinal: Alignment?
            for alignment in prevRow.compactMap({ $0 }) {
                let isContiguous = (alignment.lastIdx - alignment.firstIdx + 1) == qLen
                if requiresAllBoundaries && !isContiguous && alignment.boundaryHits < 2 {
                    continue
                }
                if bestFinal == nil || alignment.score > bestFinal!.score {
                    bestFinal = alignment
                }
            }

            guard let best = bestFinal else { return nil }

            let span = max(qLen, best.lastIdx - best.firstIdx + 1)
            let densityBonus = (qLen * 80) / span
            let boundaryBonus = best.boundaryHits * 26
            let consecutiveBonus = best.consecutiveHits * 18
            let startPenalty = min(30, best.firstIdx * 2)

            return 420 + densityBonus + boundaryBonus + consecutiveBonus - startPenalty
        }

        private func scoreTypoTolerance(
            queryChars: [Character],
            compactQueryChars: [Character]
        ) -> Int? {
            let maxDistance = queryChars.count >= 7 ? 2 : 1
            var bestDistance: Int?

            func consider(_ target: [Character], query: [Character]) {
                guard !target.isEmpty, abs(target.count - query.count) <= maxDistance else { return }

                // Require matching or transposed leading characters to avoid noisy false positives
                let sharesLead = target[0] == query[0]
                    || (target.count >= 2 && query.count >= 2 && target[0] == query[1] && target[1] == query[0])
                guard sharesLead else { return }

                if let dist = AppSearchIndex.damerauLevenshtein(query, target, maxDistance: maxDistance),
                   dist * 3 <= query.count {
                    if bestDistance == nil || dist < bestDistance! {
                        bestDistance = dist
                    }
                }
            }

            consider(chars, query: queryChars)
            if !compactQueryChars.isEmpty {
                consider(compactChars, query: compactQueryChars)
            }
            for word in words {
                consider(word, query: queryChars)
            }

            guard let dist = bestDistance else { return nil }
            return 300 - dist * 55
        }
    }

    // MARK: - Helpers

    private static func fold(_ string: String) -> String {
        string
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private static func compact(_ string: String) -> String {
        String(string.filter { !$0.isWhitespace && $0 != "-" && $0 != "_" && $0 != "." && $0 != "/" })
    }

    private static func containsCJK(_ string: String) -> Bool {
        string.unicodeScalars.contains { scalar in
            let v = scalar.value
            return (v >= 0x3400 && v <= 0x9FFF)
                || (v >= 0xF900 && v <= 0xFAFF)
                || (v >= 0x20000 && v <= 0x2A6DF)
        }
    }

    private static func pinyinForms(for string: String) -> (full: String, initials: String) {
        guard let latin = string.applyingTransform(.toLatin, reverse: false) else {
            return ("", "")
        }
        let stripped = latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
        let cleaned = fold(stripped)
        let syllables = cleaned
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)

        guard !syllables.isEmpty else { return ("", "") }

        let full = syllables.joined(separator: " ")
        let initials = String(syllables.compactMap(\.first))
        return (full, initials)
    }

    private static func damerauLevenshtein(
        _ lhs: [Character],
        _ rhs: [Character],
        maxDistance: Int
    ) -> Int? {
        let m = lhs.count
        let n = rhs.count
        if abs(m - n) > maxDistance { return nil }
        if m == 0 { return n <= maxDistance ? n : nil }
        if n == 0 { return m <= maxDistance ? m : nil }

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }

        for i in 1...m {
            var rowMin = Int.max
            for j in 1...n {
                let cost = lhs[i - 1] == rhs[j - 1] ? 0 : 1
                var val = min(
                    dp[i - 1][j] + 1,
                    dp[i][j - 1] + 1,
                    dp[i - 1][j - 1] + cost
                )
                if i > 1 && j > 1 && lhs[i - 1] == rhs[j - 2] && lhs[i - 2] == rhs[j - 1] {
                    val = min(val, dp[i - 2][j - 2] + 1)
                }
                dp[i][j] = val
                if val < rowMin {
                    rowMin = val
                }
            }
            if rowMin > maxDistance + 1 {
                return nil
            }
        }

        let distance = dp[m][n]
        return distance <= maxDistance ? distance : nil
    }
}
