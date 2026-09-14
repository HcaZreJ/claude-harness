import AppKit

@main
enum Entry {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count {
            render(into: args[index + 1])
            return
        }

        let delegate = LiveDelegate()
        app.delegate = delegate
        app.run()
    }

    static func render(into directory: String) {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        for (mode, appearance) in [("light", NSAppearance(named: .aqua)!), ("dark", NSAppearance(named: .darkAqua)!)] {
            // 视图的构造也要包在目标外观里：`NSColor.windowBackgroundColor.cgColor` 这类写法
            // 在赋值那一刻就把语义色按「当时的外观」解析成了固定值，之后再设 view.appearance
            // 也改不动它。构造挪进来，两套外观才各自解析出自己的那个值。
            appearance.performAsCurrentDrawingAppearance {
                for (title, screen) in makeScreens() {
                    Snapshot.write(screen, appearance: appearance, to: "\(directory)/\(slug(title))-\(mode).png")
                }
                Snapshot.write(
                    Snapshot.sideBySide(makeScreens()),
                    appearance: appearance,
                    to: "\(directory)/all-\(mode).png"
                )
            }
        }
    }

    static func slug(_ title: String) -> String {
        String(title.map { $0.isLetter || $0.isNumber ? $0 : "-" }).lowercased()
    }
}

final class LiveDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let canvas = Snapshot.sideBySide(makeScreens())
        let window = NSWindow(
            contentRect: canvas.bounds,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = previewWindowTitle
        window.contentView = canvas
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
