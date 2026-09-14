import AppKit

/// 把一棵 AppKit 视图树离屏渲染成 PNG。
enum Snapshot {
    /// view 必须已有非零 frame。
    static func write(_ view: NSView, appearance: NSAppearance, to path: String) {
        view.appearance = appearance
        // 先布局：跳过这步时子视图 frame 全是 0，图上只剩背景。
        view.layoutSubtreeIfNeeded()

        let rect = view.bounds
        guard rect.width > 0, rect.height > 0 else {
            FileHandle.standardError.write(Data("zero-size view: \(path)\n".utf8))
            return
        }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: rect) else { return }

        // labelColor 这类语义色按「当前绘制外观」解析；套上这一层，浅色深色才会渲染成两张图。
        appearance.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: rect, to: rep)
        }

        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }

    /// 把几屏横排进一张图，每屏上方压一行标签。
    static func sideBySide(_ screens: [(String, NSView)]) -> NSView {
        let labelHeight: CGFloat = 22
        let gap: CGFloat = 16
        for (_, screen) in screens { screen.layoutSubtreeIfNeeded() }

        let tallest = screens.map(\.1.bounds.height).max() ?? 0
        let width = screens.reduce(0) { $0 + $1.1.bounds.width } + gap * CGFloat(screens.count + 1)

        let canvas = NSView(frame: NSRect(x: 0, y: 0, width: width, height: tallest + labelHeight + gap * 2))
        canvas.wantsLayer = true
        canvas.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        var x = gap
        for (title, screen) in screens {
            screen.setFrameOrigin(NSPoint(x: x, y: gap))
            canvas.addSubview(screen)

            let label = NSTextField(labelWithString: title)
            label.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.sizeToFit()
            label.setFrameOrigin(NSPoint(x: x, y: gap + screen.bounds.height + 6))
            canvas.addSubview(label)

            x += screen.bounds.width + gap
        }
        return canvas
    }
}
