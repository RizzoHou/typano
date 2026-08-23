import Foundation

/// HID-level key remapping through `hidutil` — the same mechanism
/// `Scripts/remap.sh` uses, moved in-app so the state can be *read* as well as
/// written.
///
/// No privileges are involved: `hidutil` sets a per-user, per-boot property and
/// the app is neither sandboxed nor entitled. The remaps are per-boot and cover
/// only the devices attached when they were applied.
enum KeyRemap {

    /// The remaps Typano cares about. HID usage page 0x07 codes, identical to
    /// the constants in `Scripts/remap.sh` — the two must not drift.
    enum Feature: String, CaseIterable, Identifiable, Sendable {
        /// Caps Lock → F13. Caps Lock is a toggle with no key-up, so it cannot
        /// time a note; as F13 it is an ordinary key (B3).
        case capsLock
        /// Right ⌘ → F16. Strips right ⌘ of its modifier meaning everywhere, so
        /// holding it can no longer fire ⌘-Tab or ⌘-Space — the two the app's
        /// own isolation cannot reach, because WindowServer handles them first.
        case rightCommand

        var id: String { rawValue }

        var source: UInt64 {
            switch self {
            case .capsLock:     return 0x700000039
            case .rightCommand: return 0x7000000E7
            }
        }

        var destination: UInt64 {
            switch self {
            case .capsLock:     return 0x700000068   // F13
            case .rightCommand: return 0x70000006B   // F16
            }
        }

        var title: String {
            switch self {
            case .capsLock:     return "Caps Lock → F13"
            case .rightCommand: return "Right ⌘ → F16"
            }
        }

        var detail: String {
            switch self {
            case .capsLock:
                return "Caps Lock is a toggle with no key-up, so it cannot time a note. Remapped, it plays B3."
            case .rightCommand:
                return "Removes right ⌘'s modifier meaning system-wide, so holding it stops firing ⌘-Tab and ⌘-Space. Left ⌘ keeps every shortcut."
            }
        }
    }

    // MARK: - Session ownership

    /// What one run of the app turned on, so quitting can put the table back
    /// the way it found it.
    ///
    /// The distinction this exists for: `hidutil` state is per-boot and
    /// survives the process, so the remaps have to be taken down deliberately —
    /// but restoring the table *wholesale* would delete a remap the user set
    /// from `Scripts/remap.sh` before launching, which the app never owned.
    struct Session {
        /// Features this run switched on and has not switched off again.
        private(set) var owned: Set<Feature> = []

        /// Folds in one of the app's own writes: what it turned on becomes ours
        /// to take back down, what it turned off stops being ours.
        mutating func record(before: Set<Feature>, after: Set<Feature>) {
            owned.formUnion(after.subtracting(before))
            owned.subtract(before.subtracting(after))
        }

        /// Drops ownership of anything no longer active. The table can change
        /// behind the app's back — a reboot clears it, the script rewrites it —
        /// and claiming something the app did not set would delete it on quit.
        mutating func reconcile(with active: Set<Feature>) {
            owned.formIntersection(active)
        }

        /// The table to leave behind on quit: everything active except what
        /// this run put there.
        func releasing(_ active: Set<Feature>) -> Set<Feature> {
            active.subtracting(owned)
        }
    }

    // MARK: - Reading

    /// What `hidutil` reports right now.
    ///
    /// Authoritative, and it has to be: the mapping table survives app
    /// restarts, is cleared by a reboot, and can be changed by the script or by
    /// any other tool — so it can never be inferred from what the app itself
    /// did last.
    static func active() -> Set<Feature> {
        let sources = Set(currentEntries().compactMap { $0.source })
        return Set(Feature.allCases.filter { sources.contains($0.source) })
    }

    /// One entry of the `UserKeyMapping` table.
    struct Entry {
        let source: UInt64?
        let destination: UInt64?
    }

    /// Entries Typano did not write. `hidutil` replaces the whole table on
    /// every call, so these have to be carried across a write or the app would
    /// silently clobber any other remap the user has set up — which is exactly
    /// what `Scripts/remap.sh off` does today.
    static func foreignEntries() -> [Entry] {
        let ours = Set(Feature.allCases.map(\.source))
        return currentEntries().filter { entry in
            guard let source = entry.source else { return false }
            return !ours.contains(source)
        }
    }

    private static func currentEntries() -> [Entry] {
        guard let output = run(["property", "--get", "UserKeyMapping"]),
              let data = output.data(using: .utf8)
        else { return [] }

        // `hidutil` prints an OpenStep property list. `PropertyListSerialization`
        // reads that format — but OpenStep has no number type, so every value
        // arrives as a String and `as? NSNumber` silently yields nil. Getting
        // this wrong makes the app report "nothing is remapped" while both
        // remaps are active, which is the precise failure this exists to avoid.
        var format = PropertyListSerialization.PropertyListFormat.openStep
        guard let parsed = try? PropertyListSerialization.propertyList(
            from: data, options: [], format: &format) else { return [] }

        // `[Any]` then compactMap, not a direct `[[String: Any]]` cast: an empty
        // table prints `(null)`, whose single non-dictionary member would make
        // the whole cast fail rather than yielding zero entries.
        guard let members = parsed as? [Any] else { return [] }
        return members.compactMap { member in
            guard let entry = member as? [String: Any] else { return nil }
            return Entry(source: usage(entry["HIDKeyboardModifierMappingSrc"]),
                         destination: usage(entry["HIDKeyboardModifierMappingDst"]))
        }
    }

    private static func usage(_ value: Any?) -> UInt64? {
        if let number = value as? NSNumber { return number.uint64Value }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") {
                return UInt64(trimmed.dropFirst(2), radix: 16)
            }
            return UInt64(trimmed)
        }
        return nil
    }

    // MARK: - Writing

    enum Failure: LocalizedError {
        case hidutilFailed(Int32)
        case hidutilUnavailable

        var errorDescription: String? {
            switch self {
            case .hidutilFailed(let status): return "hidutil exited \(status)"
            case .hidutilUnavailable:        return "hidutil could not be run"
            }
        }
    }

    /// Sets the table to exactly `features`, plus whatever entries Typano does
    /// not own. One call, because `hidutil` replaces the whole table — applying
    /// the two remaps from separate calls would silently drop the first.
    static func apply(_ features: Set<Feature>) throws {
        let ours = features.map { ($0.source, $0.destination) }
        let theirs = foreignEntries().compactMap { entry -> (UInt64, UInt64)? in
            guard let source = entry.source, let destination = entry.destination
            else { return nil }
            return (source, destination)
        }

        let entries = (ours + theirs).map {
            "{\"HIDKeyboardModifierMappingSrc\":\($0.0),\"HIDKeyboardModifierMappingDst\":\($0.1)}"
        }
        let payload = "{\"UserKeyMapping\":[\(entries.joined(separator: ","))]}"

        guard run(["property", "--set", payload]) != nil else {
            throw Failure.hidutilUnavailable
        }
    }

    // MARK: - Process

    @discardableResult
    private static func run(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = arguments

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do { try process.run() } catch { return nil }
        // Read before waiting: a pipe that fills while we block on exit
        // deadlocks. The table is small today, but this is the kind of thing
        // that only breaks once someone has forty remaps.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
