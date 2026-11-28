import AppKit
import SwiftUI

/// Everything in the ◉ menu, in a window laid out like System Settings.
/// It opens with the app, from the menu (ตั้งค่า…, ⌘,) and when the app is
/// opened again. While it's open the app is an ordinary one, in the Dock
/// and ⌘Tab, so the window can't get lost behind others; once it's closed
/// the app goes back to living in the menu bar.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        let w = window ?? makeWindow()
        window = w
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.deactivate()   // hand the menu bar back to the app underneath
    }

    /// The window's frame in screen coordinates, while it's on screen.
    var visibleFrame: CGRect? {
        guard let window, window.isVisible, !window.isMiniaturized else { return nil }
        return window.frame
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        hosting.sizingOptions = []
        let w = NSWindow(contentViewController: hosting)
        w.title = "ตั้งค่า Steady Laser"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.setContentSize(NSSize(width: 980, height: 640))
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        w.setFrameAutosaveName("SettingsWindow")   // puts it back where it was last time
        return w
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    private var settings: Settings { model.settings }

    var body: some View {
        // Two columns, so the window is wide rather than tall: on the left
        // how the pointer looks, with the preview right above the settings
        // that change it; on the right how and when it shows.
        HStack(alignment: .top, spacing: 0) {
            Form {
                pointerSection
                switch settings.kind {
                case .laser: laserSection
                case .spotlight: spotlightSection
                }
            }
            .formStyle(.grouped)

            Form {
                behaviorSections
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 860, minHeight: 480)
    }

    private var pointerSection: some View {
        Section("ตัวชี้") {
            VStack(alignment: .leading, spacing: 6) {
                LaserPreview(look: LaserPreview.Look(settings))
                    .aspectRatio(SampleSlide.size.width / SampleSlide.size.height, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator))
                Text("สไลด์ตัวอย่างย่อจากขนาดจอหลัก ตัวชี้จึงเล็กลงในสัดส่วนเดียวกัน เลื่อนเมาส์บนภาพเพื่อลองชี้")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker(selection: bind(\.kind)) {
                ForEach(PointerKind.allCases, id: \.self) { Text($0.shortTitle).tag($0) }
            } label: {
                Text("แสดงเป็น")
                Text("ระหว่างนำเสนอ กดปุ่ม Pointer 2 ครั้ง เว้นราวครึ่งวินาที เพื่อสลับ")
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var behaviorSections: some View {
        Section("การแสดงผล") {
            Picker(selection: bind(\.mode)) {
                ForEach(LaserMode.allCases, id: \.self) { Text($0.title).tag($0) }
            } label: {
                Text("โหมด")
                Text("เปิดหรือปิดได้ทุกเมื่อด้วย ⌃⌥L")
            }
            Picker(selection: bind(\.stability)) {
                ForEach(Stability.allCases, id: \.self) { Text($0.shortTitle).tag($0) }
            } label: {
                Text("ความนิ่ง")
                Text("ยิ่งสูง มือสั่นยิ่งไม่เห็น แต่จุดตามมือช้าลงเล็กน้อย")
            }
            .pickerStyle(.segmented)
        }

        Section("รีโมต") {
            LabeledContent {
                HStack(spacing: 8) {
                    Text(settings.laserButton?.title ?? "Pointer ของรีโมต Norwii")
                    if settings.laserButton != nil {
                        Button("ใช้ Pointer ของ Norwii") { model.clearLaserButton() }
                    }
                    Button("เปลี่ยน…") { model.learnLaserButton() }
                }
            } label: {
                Text("ปุ่มเลเซอร์")
                Text("ปิดแอป Norwii Presenter ก่อนใช้ เพราะแอปนั้นย้ายเคอร์เซอร์เองและจะแย่งกัน")
            }
            if let error = model.laserButtonError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }

        Section("เคอร์เซอร์") {
            Toggle("ซ่อนเคอร์เซอร์ตอนเลเซอร์แสดง", isOn: bind(\.hideCursor))
            Toggle(isOn: bind(\.detachCursor)) {
                Text("ตอนกดปุ่มเลเซอร์ เมาส์ไม่ชี้หรือคลิกอะไร")
                Text("ปุ่ม ลิงก์ และ Dock ข้างใต้จะไม่เห็นเมาส์จนกว่าจะปล่อยปุ่ม")
            }
        }

        Section {
            Toggle("เปิดอัตโนมัติตอนเข้าเครื่อง", isOn: Binding(
                get: { model.launchesAtLogin },
                set: { _ in model.toggleLaunchAtLogin() }
            ))
        }
    }

    private var laserSection: some View {
        Section("เลเซอร์") {
            Picker("รูปแบบ", selection: bind(\.style)) {
                ForEach(LaserStyle.allCases, id: \.self) { Text($0.shortTitle).tag($0) }
            }
            .pickerStyle(.segmented)
            LabeledContent("สี") {
                ColorSwatches(selection: bind(\.color))
            }
            Picker("ขนาด", selection: bind(\.size)) {
                ForEach(LaserSize.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var spotlightSection: some View {
        Section("สปอตไลต์") {
            Slider(value: step(\.spotlightSize), in: 0...Double(SpotlightSize.allCases.count - 1), step: 1) {
                Text("ขนาด")
                Text("\(settings.spotlightSize.title) · รัศมี \(Int(settings.spotlightSize.radius)) pt")
            } minimumValueLabel: {
                Image(systemName: "circle").font(.system(size: 7))
            } maximumValueLabel: {
                Image(systemName: "circle").font(.system(size: 15))
            }
            .accessibilityValue(settings.spotlightSize.title)

            Slider(value: step(\.spotlightShade), in: 0...Double(SpotlightShade.allCases.count - 1), step: 1) {
                Text("ความทึบรอบวงกลม")
                Text(settings.spotlightShade.title)
            } minimumValueLabel: {
                Text("จาง")
            } maximumValueLabel: {
                Text("เข้ม")
            }
            .accessibilityValue(settings.spotlightShade.title)
        }
    }

    /// A binding that writes only real changes, so dragging a slider over
    /// one step doesn't rebuild the menu on every mouse move.
    private func bind<T: Equatable>(_ key: ReferenceWritableKeyPath<Settings, T>) -> Binding<T> {
        Binding(
            get: { settings[keyPath: key] },
            set: { if settings[keyPath: key] != $0 { settings[keyPath: key] = $0 } }
        )
    }

    /// One slider step per case of a setting's choices.
    private func step<T: CaseIterable & Equatable>(_ key: ReferenceWritableKeyPath<Settings, T>) -> Binding<Double>
    where T.AllCases == [T] {
        let all = T.allCases
        let choice = bind(key)
        return Binding(
            get: { Double(all.firstIndex(of: choice.wrappedValue) ?? 0) },
            set: { choice.wrappedValue = all[min(max(Int($0.rounded()), 0), all.count - 1)] }
        )
    }
}

/// The laser colours as dots, picked the way System Settings picks an accent colour.
private struct ColorSwatches: View {
    @Binding var selection: LaserColor

    var body: some View {
        HStack(spacing: 8) {
            ForEach(LaserColor.allCases, id: \.self) { color in
                let selected = color == selection
                Button {
                    selection = color
                } label: {
                    Circle()
                        .fill(Color(nsColor: color.color))
                        .overlay(Circle().strokeBorder(.black.opacity(0.18), lineWidth: 0.5))
                        .overlay {
                            if selected { Circle().fill(.white).frame(width: 6, height: 6) }
                        }
                        .frame(width: 16, height: 16)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(color.title)
                .accessibilityLabel(color.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}
