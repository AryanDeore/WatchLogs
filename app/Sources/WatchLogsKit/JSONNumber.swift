import Foundation

enum JSONNumber {
    /// A JSON value that is an exact integer: `1` and `1.0` pass, `1.5` and a
    /// bool do not. Shared by the Flush decoder and the pairing-string decoder.
    static func whole(_ value: Any) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        let intValue = number.intValue
        return Double(intValue) == number.doubleValue ? intValue : nil
    }
}
