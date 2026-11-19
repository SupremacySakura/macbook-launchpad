import AppKit

struct App: Identifiable, Hashable {
    let id: URL
    let name: String
    let url: URL
    let icon: NSImage

    init(name: String, url: URL, icon: NSImage) {
        self.id = url
        self.name = name
        self.url = url
        self.icon = icon
    }

    static func == (lhs: App, rhs: App) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
