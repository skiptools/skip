/// Determines what API is bridged.
public enum BridgeAPI {
    /// Bridging is disabled.
    case none
    /// Bridge only API with bridge attribute.
    case explicit
    /// Bridge all public API that isn't explicitly excluded.
    case `public`
}
