import AppKit
import Carbon.HIToolbox

/// The button on the remote that is held down to show the laser.
/// A keyboard key is caught with a Carbon hotkey (no permissions needed);
/// an extra mouse button (3, 4, 5…) with a global mouse monitor.
enum LaserButton: Equatable {
    case key(code: Int, modifiers: Int, name: String)
    case mouse(button: Int)

    var title: String {
        switch self {
        case .key(_, _, let name): name
        case .mouse(let button): "ปุ่มเมาส์ \(button + 1)"
        }
    }

    var plist: [String: Any] {
        switch self {
        case let .key(code, modifiers, name): ["kind": "key", "code": code, "modifiers": modifiers, "name": name]
        case let .mouse(button): ["kind": "mouse", "button": button]
        }
    }

    init?(plist: [String: Any]) {
        switch plist["kind"] as? String {
        case "key":
            guard let code = plist["code"] as? Int, let mods = plist["modifiers"] as? Int else { return nil }
            self = .key(code: code, modifiers: mods, name: plist["name"] as? String ?? "keyCode \(code)")
        case "mouse":
            guard let button = plist["button"] as? Int else { return nil }
            self = .mouse(button: button)
        default:
            return nil
        }
    }

    /// Builds a binding from the key press captured in the "learn" panel.
    static func from(keyEvent e: NSEvent) -> LaserButton {
        let flags = e.modifierFlags.intersection([.command, .option, .control, .shift])
        var carbon = 0
        var prefix = ""
        if flags.contains(.control) { carbon |= controlKey; prefix += "⌃" }
        if flags.contains(.option) { carbon |= optionKey; prefix += "⌥" }
        if flags.contains(.shift) { carbon |= shiftKey; prefix += "⇧" }
        if flags.contains(.command) { carbon |= cmdKey; prefix += "⌘" }
        return .key(code: Int(e.keyCode), modifiers: carbon, name: prefix + keyName(e))
    }

    private static func keyName(_ e: NSEvent) -> String {
        let named: [Int: String] = [
            kVK_PageUp: "Page Up", kVK_PageDown: "Page Down", kVK_Home: "Home", kVK_End: "End",
            kVK_Escape: "Esc", kVK_Tab: "Tab", kVK_Return: "Return", kVK_Space: "Space",
            kVK_Delete: "Delete", kVK_ForwardDelete: "Forward Delete",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
            kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
        ]
        if let n = named[Int(e.keyCode)] { return n }
        if let c = e.charactersIgnoringModifiers, !c.isEmpty,
           c.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
            return c.uppercased()
        }
        return "keyCode \(e.keyCode)"
    }
}

/// Small window that waits for the next key or extra mouse button and hands it back.
@MainActor
final class ButtonCapture: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var monitor: Any?
    private var completion: ((LaserButton?) -> Void)?

    func begin(completion: @escaping (LaserButton?) -> Void) {
        finish(nil)
        self.completion = completion

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 167),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        panel.title = "ตั้งปุ่มเลเซอร์"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = makeContent()
        panel.center()
        self.panel = panel

        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .otherMouseDown]) { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .keyDown:
                self.finish(LaserButton.from(keyEvent: event))
            case .otherMouseDown:
                self.finish(.mouse(button: event.buttonNumber))
            default:
                return event
            }
            return nil
        }
    }

    /// The panel's content; also used by `--snapshot-capture` to check the layout.
    func makeContent() -> NSView {
        let title = NSTextField(wrappingLabelWithString: "กดปุ่มบนรีโมตที่อยากใช้ \"กดค้างเพื่อแสดงเลเซอร์\"")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        let body = NSTextField(wrappingLabelWithString:
            "ปุ่มที่เลือกจะถูกแอปนี้ใช้แทน แอปอื่นจะไม่ได้รับปุ่มนี้แล้ว ไม่ควรเลือกปุ่มเลื่อนสไลด์ (Page Up / Page Down / ลูกศร)")
        body.textColor = .secondaryLabelColor
        let hint = NSTextField(wrappingLabelWithString:
            "ถ้ากดแล้วไม่มีอะไรเกิดขึ้น แปลว่าปุ่มนั้นไม่ได้ส่งคีย์มาที่เครื่อง ให้ลองปุ่มอื่น หรือใช้โหมด \"แสดงเมื่อขยับเมาส์\" แทน")
        hint.textColor = .secondaryLabelColor
        let cancel = NSButton(title: "ยกเลิก", target: self, action: #selector(cancelPressed))
        cancel.keyEquivalent = ""

        let stack = NSStackView(views: [title, body, hint, cancel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: 400),
        ])
        return content
    }

    @objc private func cancelPressed() { finish(nil) }

    func windowWillClose(_ notification: Notification) {
        if completion != nil { finish(nil, closing: true) }
    }

    private func finish(_ result: LaserButton?, closing: Bool = false) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        let done = completion
        completion = nil
        if !closing { panel?.close() }
        panel = nil
        done?(result)
    }
}
