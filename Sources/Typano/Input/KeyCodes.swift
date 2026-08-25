import Foundation

/// macOS ANSI virtual key codes (Carbon `kVK_*`).
///
/// These identify *physical* key positions, so the instrument mapping is
/// unaffected by whatever software keyboard layout the user has active.
enum KC {
    static let a: UInt16 = 0
    static let s: UInt16 = 1
    static let d: UInt16 = 2
    static let f: UInt16 = 3
    static let h: UInt16 = 4
    static let g: UInt16 = 5
    static let z: UInt16 = 6
    static let x: UInt16 = 7
    static let c: UInt16 = 8
    static let v: UInt16 = 9
    static let b: UInt16 = 11
    static let q: UInt16 = 12
    static let w: UInt16 = 13
    static let e: UInt16 = 14
    static let r: UInt16 = 15
    static let y: UInt16 = 16
    static let t: UInt16 = 17

    static let one: UInt16 = 18
    static let two: UInt16 = 19
    static let three: UInt16 = 20
    static let four: UInt16 = 21
    static let six: UInt16 = 22
    static let five: UInt16 = 23
    static let equal: UInt16 = 24
    static let nine: UInt16 = 25
    static let seven: UInt16 = 26
    static let minus: UInt16 = 27
    static let eight: UInt16 = 28
    static let zero: UInt16 = 29

    static let rightBracket: UInt16 = 30
    static let o: UInt16 = 31
    static let u: UInt16 = 32
    static let leftBracket: UInt16 = 33
    static let i: UInt16 = 34
    static let p: UInt16 = 35
    static let ret: UInt16 = 36
    static let l: UInt16 = 37
    static let j: UInt16 = 38
    static let quote: UInt16 = 39
    static let k: UInt16 = 40
    static let semicolon: UInt16 = 41
    static let backslash: UInt16 = 42
    static let comma: UInt16 = 43
    static let slash: UInt16 = 44
    static let n: UInt16 = 45
    static let m: UInt16 = 46
    static let period: UInt16 = 47
    static let tab: UInt16 = 48
    static let space: UInt16 = 49
    static let grave: UInt16 = 50
    static let delete: UInt16 = 51

    static let command: UInt16 = 55
    static let shift: UInt16 = 56
    static let capsLock: UInt16 = 57
    static let option: UInt16 = 58
    static let control: UInt16 = 59
    static let rightShift: UInt16 = 60
    static let rightOption: UInt16 = 61
    static let rightControl: UInt16 = 62
    static let rightCommand: UInt16 = 54
    static let function: UInt16 = 63

    /// Caps Lock remapped by `Scripts/remap.sh`.
    static let f13: UInt16 = 105
    /// Right ⌘ remapped by `Scripts/remap.sh`, which strips its modifier
    /// meaning at the HID level so even WindowServer shortcuts stop firing.
    static let f16: UInt16 = 106

    static let left: UInt16 = 123
    static let right: UInt16 = 124
    static let down: UInt16 = 125
    static let up: UInt16 = 126

    static let escape: UInt16 = 0x35

    /// Function row. Their codes are famously out of order — F3 sits between
    /// F7 and F8 — so they are written as the SDK spells them rather than
    /// derived from F1.
    static let f1: UInt16 = 0x7A
    static let f2: UInt16 = 0x78
    static let f3: UInt16 = 0x63
    static let f4: UInt16 = 0x76
    static let f5: UInt16 = 0x60
    static let f6: UInt16 = 0x61
    static let f7: UInt16 = 0x62
    static let f8: UInt16 = 0x64
    static let f9: UInt16 = 0x65
    static let f10: UInt16 = 0x6D
    static let f11: UInt16 = 0x67
    static let f12: UInt16 = 0x6F

    /// Numeric keypad. Present on the external boards, absent on the MacBook —
    /// which is the whole reason a layout has to know which keyboard it is for.
    static let keypadDecimal: UInt16 = 0x41
    static let keypadMultiply: UInt16 = 0x43
    static let keypadPlus: UInt16 = 0x45
    /// A PC keyboard's Num Lock arrives as Clear; macOS has no Num Lock state.
    static let keypadClear: UInt16 = 0x47
    static let keypadDivide: UInt16 = 0x4B
    static let keypadEnter: UInt16 = 0x4C
    static let keypadMinus: UInt16 = 0x4E
    /// Apple keypads only — a PC numpad has no `=`.
    static let keypadEquals: UInt16 = 0x51
    static let keypad0: UInt16 = 0x52
    static let keypad1: UInt16 = 0x53
    static let keypad2: UInt16 = 0x54
    static let keypad3: UInt16 = 0x55
    static let keypad4: UInt16 = 0x56
    static let keypad5: UInt16 = 0x57
    static let keypad6: UInt16 = 0x58
    static let keypad7: UInt16 = 0x59
    static let keypad8: UInt16 = 0x5B
    static let keypad9: UInt16 = 0x5C

    /// Editing cluster. A PC keyboard's Insert arrives as Help, and its Delete
    /// is `forwardDelete` — `delete` above is Backspace.
    static let help: UInt16 = 0x72
    static let home: UInt16 = 0x73
    static let pageUp: UInt16 = 0x74
    static let forwardDelete: UInt16 = 0x75
    static let end: UInt16 = 0x77
    static let pageDown: UInt16 = 0x79

    /// Device-dependent modifier bits (IOKit `NX_DEVICE*KEYMASK`), needed
    /// because the cooked flags — `.shift`, `.command`, … — cannot tell left
    /// from right. `fn` has no device bit; it is detected by key code plus
    /// `.function` in the cooked flags.
    enum DeviceFlag {
        static let leftControl: UInt = 0x0001
        static let leftShift: UInt = 0x0002
        static let rightShift: UInt = 0x0004
        static let leftCommand: UInt = 0x0008
        static let rightCommand: UInt = 0x0010
        static let leftOption: UInt = 0x0020
        static let rightOption: UInt = 0x0040
        static let rightControl: UInt = 0x2000

        /// The bit that says "this modifier key is physically down", for each
        /// modifier key code the monitor reports.
        static func mask(for keyCode: UInt16) -> UInt? {
            switch keyCode {
            case KC.control:      return leftControl
            case KC.shift:        return leftShift
            case KC.rightShift:   return rightShift
            case KC.command:      return leftCommand
            case KC.rightCommand: return rightCommand
            case KC.option:       return leftOption
            case KC.rightOption:  return rightOption
            default:              return nil
            }
        }
    }
}
