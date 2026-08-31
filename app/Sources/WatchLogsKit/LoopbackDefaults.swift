import Foundation

/// Fixed defaults for the loopback transport. The App binds `defaultPort` first
/// and rolls forward to the next free port on collision (issue #26).
public enum LoopbackDefaults {
    /// The fixed default port the App tries first.
    public static let port = 48920

    /// How many sequential ports to try before giving up.
    public static let portRollAttempts = 20

    /// Wire contract identifier, surfaced by `GET /v1/ping`.
    public static let contract = "v1"

    /// Human-facing app name, surfaced by `GET /v1/ping`.
    public static let appName = "WatchLogs"

    /// Request body cap. A larger body is rejected `413` without being read.
    public static let maxBodyBytes = 1 << 20 // 1 MiB

    /// Cap on the request head (request line + headers). A larger head is `431`.
    public static let headerSectionCap = 64 * 1024

    /// The loopback host. Nothing off-machine can reach the server.
    public static let host = "127.0.0.1"
}
