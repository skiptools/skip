/// Determines what API is bridged without being explicitly annotated.
public enum AutoBridge: Int {
    /// Bridge only API with bridge attribute.
    case none
    /// Bridge all internal or public API that isn't explicitly excluded.
    case `internal`
    /// Bridge all public API that isn't explicitly excluded.
    case `public`
}

/// Whether a declaration is briging.
func isBridging(attributes: Attributes, visibility: Modifiers.Visibility, autoBridge: AutoBridge) -> Bool {
    guard !attributes.isBridge else {
        return true
    }
    guard autoBridge != .none else {
        return false
    }
    guard !attributes.isNoBridge && !attributes.contains(.unavailable) else {
        return false
    }
    return visibility >= .public || (autoBridge == .internal && visibility > .fileprivate)
}
