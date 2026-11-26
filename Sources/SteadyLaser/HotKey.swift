import Carbon.HIToolbox

/// Global hotkeys through Carbon's RegisterEventHotKey, with both press and
/// release callbacks (so a key can be "held" to show the laser).
/// Needs no Accessibility or Input Monitoring permission. A registered key is
/// consumed: other apps no longer receive it.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private struct Entry {
        var ref: EventHotKeyRef
        var onPress: () -> Void
        var onRelease: (() -> Void)?
        var isDown = false
    }

    private var entries: [UInt32: Entry] = [:]
    private var nextID: UInt32 = 1
    private var installed = false

    private func installHandler() {
        guard !installed else { return }
        installed = true
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard status == noErr else { return status }
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            // Carbon delivers hotkey events on the main thread.
            MainActor.assumeIsolated { HotKeyCenter.shared.dispatch(id: hotKeyID.id, pressed: pressed) }
            return noErr
        }, specs.count, &specs, nil, nil)
    }

    /// Returns an id for `unregister`, or nil if the combination is taken
    /// (for example by another app).
    @discardableResult
    func register(keyCode: Int, modifiers: Int, onPress: @escaping () -> Void, onRelease: (() -> Void)? = nil) -> UInt32? {
        installHandler()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers),
            EventHotKeyID(signature: OSType(0x534C_5352), id: id), // 'SLSR'
            GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else { return nil }
        entries[id] = Entry(ref: ref, onPress: onPress, onRelease: onRelease)
        return id
    }

    func unregister(_ id: UInt32) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(entry.ref)
        if entry.isDown { entry.onRelease?() }
    }

    private func dispatch(id: UInt32, pressed: Bool) {
        guard var entry = entries[id] else { return }
        // Ignore key auto-repeat: only the first press and the release count.
        guard pressed != entry.isDown else { return }
        entry.isDown = pressed
        entries[id] = entry
        if pressed { entry.onPress() } else { entry.onRelease?() }
    }
}
