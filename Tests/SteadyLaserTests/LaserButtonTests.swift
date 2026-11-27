import Carbon.HIToolbox
import XCTest
@testable import SteadyLaser

final class LaserButtonTests: XCTestCase {
    private let dongle = InputDevice(vendorID: 0x3243, productID: 0x382, name: "BLE Presenter Dongle")
    private let bluetooth = InputDevice(vendorID: 0x3243, productID: 0x3a2, name: "Norwii N95s BLE")
    private let macKeyboard = InputDevice(vendorID: 0, productID: 0, name: "Apple Internal Keyboard / Trackpad")

    func testSavedButtonsRoundTrip() {
        let buttons: [LaserButton] = [
            .key(code: kVK_F5, modifiers: controlKey, name: "⌃F5"),
            .modifier(code: kVK_Control, device: dongle),
            .modifier(code: kVK_RightOption, device: nil),
            .mouse(button: 3),
            .norwiiPointer,
        ]
        for button in buttons {
            XCTAssertEqual(LaserButton(plist: button.plist), button, "\(button)")
        }
    }

    func testUnknownSavedButtonIsIgnored() {
        XCTAssertNil(LaserButton(plist: ["kind": "joystick"]))
        XCTAssertNil(LaserButton(plist: ["kind": "modifier", "code": kVK_CapsLock]))   // not a usable modifier
        XCTAssertNil(LaserButton(plist: ["kind": "key"]))                               // missing code
    }

    /// The same remote must match through its USB dongle and over Bluetooth,
    /// and never match the Mac's own keyboard.
    func testRemoteMatchesByMaker() {
        XCTAssertTrue(dongle.isSameMaker(as: bluetooth))
        XCTAssertTrue(bluetooth.isSameMaker(as: LaserButton.norwiiPointerDevice))
        XCTAssertFalse(macKeyboard.isSameMaker(as: dongle))
        XCTAssertFalse(dongle.isSameMaker(as: macKeyboard))
        XCTAssertTrue(macKeyboard.isSameMaker(as: macKeyboard))
    }

    func testTitles() {
        XCTAssertEqual(LaserButton.mouse(button: 3).title, "ปุ่มเมาส์ 4")
        XCTAssertEqual(LaserButton.modifier(code: kVK_Control, device: dongle).title, "Control (⌃) จาก BLE Presenter Dongle")
        XCTAssertEqual(LaserButton.modifier(code: kVK_RightOption, device: nil).title, "Option ขวา (⌥)")
    }
}

private extension LaserButton {
    static var norwiiPointerDevice: InputDevice {
        guard case let .modifier(_, device?) = LaserButton.norwiiPointer else { fatalError("norwiiPointer changed shape") }
        return device
    }
}
