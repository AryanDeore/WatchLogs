import Foundation

/// User preferences for the app, persisted to UserDefaults.
@Observable
final class AppSettings {
    /// Callback invoked when icon-related settings change.
    var onIconSettingsChanged: (() -> Void)?
    
    // MARK: - Launch at Login
    
    var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: Keys.launchAtLogin)
        }
    }
    
    // MARK: - Menubar Icon Configuration
    
    var iconDisplay: IconDisplay {
        didSet {
            UserDefaults.standard.set(iconDisplay.rawValue, forKey: Keys.iconDisplay)
            onIconSettingsChanged?()
        }
    }
    
    var timeSeparator: TimeSeparator {
        didSet {
            UserDefaults.standard.set(timeSeparator.rawValue, forKey: Keys.timeSeparator)
            onIconSettingsChanged?()
        }
    }
    
    var blinkIconWhilePlaying: Bool {
        didSet {
            UserDefaults.standard.set(blinkIconWhilePlaying, forKey: Keys.blinkIconWhilePlaying)
            onIconSettingsChanged?()
        }
    }
    
    var blinkSeparator: Bool {
        didSet {
            UserDefaults.standard.set(blinkSeparator, forKey: Keys.blinkSeparator)
            onIconSettingsChanged?()
        }
    }
    
    init() {
        self.launchAtLogin = UserDefaults.standard.bool(forKey: Keys.launchAtLogin)
        
        if let displayRaw = UserDefaults.standard.string(forKey: Keys.iconDisplay),
           let display = IconDisplay(rawValue: displayRaw) {
            self.iconDisplay = display
        } else {
            self.iconDisplay = .iconAndTime  // Default
        }
        
        if let separatorRaw = UserDefaults.standard.string(forKey: Keys.timeSeparator),
           let separator = TimeSeparator(rawValue: separatorRaw) {
            self.timeSeparator = separator
        } else {
            self.timeSeparator = .letter  // Default (1h05)
        }
        
        self.blinkIconWhilePlaying = UserDefaults.standard.bool(forKey: Keys.blinkIconWhilePlaying)
        self.blinkSeparator = UserDefaults.standard.bool(forKey: Keys.blinkSeparator)
    }
    
    // MARK: - Types
    
    enum IconDisplay: String, CaseIterable {
        case iconOnly = "icon_only"
        case iconAndTime = "icon_and_time"
        case timeOnly = "time_only"
        
        var label: String {
            switch self {
            case .iconOnly: return "Icon only"
            case .iconAndTime: return "Icon + watched time"
            case .timeOnly: return "Watched time only"
            }
        }
    }
    
    enum TimeSeparator: String, CaseIterable {
        case letter = "letter"  // 1h05
        case colon = "colon"    // 1:05
        
        var label: String {
            switch self {
            case .letter: return "1h05"
            case .colon: return "1:05"
            }
        }
    }
    
    private enum Keys {
        static let launchAtLogin = "launchAtLogin"
        static let iconDisplay = "iconDisplay"
        static let timeSeparator = "timeSeparator"
        static let blinkIconWhilePlaying = "blinkIconWhilePlaying"
        static let blinkSeparator = "blinkSeparator"
    }
}
