import AppKit
import ServiceManagement

MainActor.assumeIsolated {
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
        DevTools.snapshot(to: args[i + 1])
        exit(0)
    }
    if let i = args.firstIndex(of: "--snapshot-spotlight"), i + 1 < args.count {
        DevTools.snapshotSpotlight(to: args[i + 1])
        exit(0)
    }
    if let i = args.firstIndex(of: "--render-icon"), i + 1 < args.count {
        DevTools.renderIcon(to: args[i + 1])
        exit(0)
    }
    if let i = args.firstIndex(of: "--snapshot-capture"), i + 1 < args.count {
        DevTools.snapshotCapturePanel(to: args[i + 1])
        exit(0)
    }
    if args.contains("--selftest") {
        DevTools.selfTest()
        exit(0)
    }
    // Used by build.sh --install: register / unregister this app bundle as a login item.
    if let i = args.firstIndex(of: "--login-item"), i + 1 < args.count {
        do {
            if args[i + 1] == "on" { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            print("login item status: \(SMAppService.mainApp.status.rawValue) (1 = enabled, 2 = needs approval)")
        } catch {
            print("login item error: \(error.localizedDescription)")
            exit(1)
        }
        exit(0)
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
    app.run()
}
