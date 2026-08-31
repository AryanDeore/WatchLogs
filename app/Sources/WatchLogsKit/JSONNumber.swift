import Foundation

enum JSONNumber {
    /// A JSON value that is an exact integer: `1` and `1.0` pass, `1.5` and a
    /// bool do not. Shared by the Flush decoder and the pairing-string decoder.
    static func whole(_ value: Any) -> Int? {
        guard let number = numeric(value) else { return nil }
        let intValue = number.intValue
        return Double(intValue) == number.doubleValue ? intValue : nil
    }

    /// A JSON number as a `Double` — media positions and playback rates are
    /// float seconds. A bool is not a number.
    static func real(_ value: Any) -> Double? {
        numeric(value)?.doubleValue
    }

    /// A JSON `true` / `false`. `1` is not a bool.
    static func flag(_ value: Any) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
            return nil
        }
        return number.boolValue
    }

    private static func numeric(_ value: Any) -> NSNumber? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        return number
    }
}
