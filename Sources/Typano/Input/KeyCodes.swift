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
    static let rightCommand: UInt16 = 54
    static let function: UInt16 = 63

    /// Caps Lock remapped by `Scripts/capslock-remap.sh`.
    static let f13: UInt16 = 105

    static let left: UInt16 = 123
    static let right: UInt16 = 124
    static let down: UInt16 = 125
    static let up: UInt16 = 126

    /// Device-dependent modifier bits, needed because `.shift` alone cannot
    /// tell left from right.
    enum DeviceFlag {
        static let leftShift: UInt = 0x0002
        static let rightShift: UInt = 0x0004
    }
}
