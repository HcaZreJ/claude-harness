import AppKit

/// 真窗口的标题：一句话告诉用户这一版要他看什么。
let previewWindowTitle = "设计稿"

/// 设计稿本体。每屏一个条目：标签 + 视图。
///
/// 控件用真实 AppKit 代码写，与将来落地到业务代码的写法逐字一致——这份稿就是实现草案。
/// 悬停、按下、选中这类状态做成可直接赋值的属性（离屏渲染不会触发 tracking area），
/// 同一控件的不同状态各占一屏，并排渲染出来比。
func makeScreens() -> [(String, NSView)] {
    let demo = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 120))
    demo.wantsLayer = true
    demo.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

    let label = NSTextField(labelWithString: "在 Design.swift 里写设计")
    label.translatesAutoresizingMaskIntoConstraints = false
    demo.addSubview(label)
    NSLayoutConstraint.activate([
        label.centerXAnchor.constraint(equalTo: demo.centerXAnchor),
        label.centerYAnchor.constraint(equalTo: demo.centerYAnchor)
    ])

    return [("示例", demo)]
}
