/// The system's switch that opens the app at login. The app passes `SMAppService.mainApp`.
public protocol LoginItem {
    /// Whether the app opens at login now.
    var isEnabled: Bool { get }

    /// Opens the app at login from now on.
    func enable() throws
}

extension AppSettings {
    /// Set once Open at login has been turned on, so it's done only once.
    static let turnedOnOpenAtLoginKey = "turnedOnOpenAtLogin"

    /// Turns Open at login on at the app's first launch. Only once: if the user turns it off
    /// later, it stays off.
    public func turnOnOpenAtLoginOnFirstLaunch(_ loginItem: some LoginItem) throws {
        guard !defaults.bool(forKey: Self.turnedOnOpenAtLoginKey) else { return }
        try loginItem.enable()
        defaults.set(true, forKey: Self.turnedOnOpenAtLoginKey)
    }
}
