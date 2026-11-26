import AppKit

enum LaserMode: String, CaseIterable {
    case off, moving, hold, always

    var title: String {
        switch self {
        case .off: "ปิด"
        case .moving: "แสดงเมื่อขยับเมาส์"
        case .hold: "แสดงเมื่อกดปุ่มเลเซอร์ (กดอีกครั้งเพื่อซ่อน)"
        case .always: "เปิดตลอด"
        }
    }
}

enum LaserStyle: String, CaseIterable {
    case dot, glow, comet

    var title: String {
        switch self {
        case .dot: "จุด (Dot)"
        case .glow: "เรืองแสง (Glow)"
        case .comet: "ดาวหาง มีหาง (Comet)"
        }
    }
}

enum LaserSize: String, CaseIterable {
    case small, medium, large

    var title: String {
        switch self {
        case .small: "เล็ก"
        case .medium: "กลาง"
        case .large: "ใหญ่"
        }
    }

    /// Radius of the solid core, in points.
    var radius: CGFloat {
        switch self {
        case .small: 6
        case .medium: 9
        case .large: 13
        }
    }
}

enum LaserColor: String, CaseIterable {
    case red, green, blue, magenta, orange

    var title: String {
        switch self {
        case .red: "แดง"
        case .green: "เขียว"
        case .blue: "น้ำเงิน"
        case .magenta: "ชมพู"
        case .orange: "ส้ม"
        }
    }

    var color: NSColor {
        switch self {
        case .red: NSColor(srgbRed: 1.00, green: 0.10, blue: 0.08, alpha: 1)
        case .green: NSColor(srgbRed: 0.20, green: 1.00, blue: 0.30, alpha: 1)
        case .blue: NSColor(srgbRed: 0.20, green: 0.55, blue: 1.00, alpha: 1)
        case .magenta: NSColor(srgbRed: 1.00, green: 0.20, blue: 0.85, alpha: 1)
        case .orange: NSColor(srgbRed: 1.00, green: 0.55, blue: 0.08, alpha: 1)
        }
    }
}

/// How hard the One Euro filter smooths hand tremor.
/// minCutoff: cutoff (Hz) when the hand is still — lower = steadier.
/// beta: how fast the cutoff opens up with speed — higher = less lag on fast moves.
enum Stability: String, CaseIterable {
    case low, medium, high

    var title: String {
        switch self {
        case .low: "ต่ำ (ตอบสนองไว)"
        case .medium: "กลาง"
        case .high: "สูง (นิ่งที่สุด)"
        }
    }

    var minCutoff: Double {
        switch self {
        case .low: 4.0
        case .medium: 1.8
        case .high: 0.8
        }
    }

    var beta: Double {
        switch self {
        case .low: 0.010
        case .medium: 0.006
        case .high: 0.004
        }
    }
}

@MainActor
final class Settings {
    static let shared = Settings()

    /// Called after any setting changes.
    var onChange: (() -> Void)?

    private let defaults = UserDefaults.standard

    private func value<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
        guard let raw = defaults.string(forKey: key), let v = T(rawValue: raw) else { return fallback }
        return v
    }

    private func store<T: RawRepresentable>(_ v: T, _ key: String) where T.RawValue == String {
        defaults.set(v.rawValue, forKey: key)
        onChange?()
    }

    var mode: LaserMode {
        get { value("laserMode", .moving) }
        set {
            if newValue != .off { defaults.set(newValue.rawValue, forKey: "lastActiveMode") }
            store(newValue, "laserMode")
        }
    }

    /// The mode the hotkey returns to when turning the laser back on.
    var lastActiveMode: LaserMode {
        let m: LaserMode = value("lastActiveMode", .moving)
        return m == .off ? .moving : m
    }

    var style: LaserStyle {
        get { value("laserStyle", .comet) }
        set { store(newValue, "laserStyle") }
    }

    var size: LaserSize {
        get { value("laserSize", .medium) }
        set { store(newValue, "laserSize") }
    }

    var color: LaserColor {
        get { value("laserColor", .red) }
        set { store(newValue, "laserColor") }
    }

    var stability: Stability {
        get { value("stability", .medium) }
        set { store(newValue, "stability") }
    }

    /// Button on the remote held down to show the laser (nil = none set).
    var laserButton: LaserButton? {
        get { (defaults.dictionary(forKey: "laserButton")).flatMap(LaserButton.init(plist:)) }
        set {
            if let newValue { defaults.set(newValue.plist, forKey: "laserButton") } else { defaults.removeObject(forKey: "laserButton") }
            onChange?()
        }
    }

    var hideCursor: Bool {
        get { defaults.object(forKey: "hideCursor") as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: "hideCursor")
            onChange?()
        }
    }

    /// Seconds without movement before the laser fades in "moving" mode.
    let idleDelay: CFTimeInterval = 1.5
    /// How long the comet tail lasts, in seconds.
    let trailDuration: CFTimeInterval = 0.12
}
