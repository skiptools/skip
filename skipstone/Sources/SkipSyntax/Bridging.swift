/// Determines what API is bridged without being explicitly annotated.
public enum AutoBridge {
    /// Bridge only API with bridge attribute.
    case none
    /// Bridge all public API that isn't explicitly excluded.
    case `public`
}

/// Whether a declaration is briging.
func isBridging(attributes: Attributes, isPublic: Bool, autoBridge: AutoBridge) -> Bool {
    guard !attributes.isBridge else {
        return true
    }
    guard autoBridge == .public else {
        return false
    }
    guard !attributes.isNoBridge else {
        return false
    }
    return isPublic
}
