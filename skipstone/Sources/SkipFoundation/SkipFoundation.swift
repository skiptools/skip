#if !SKIP
@_exported import Foundation
#endif

internal func SkipFoundationInternalModuleName() -> String {
    return "SkipFoundation"
}

public func SkipFoundationPublicModuleName() -> String {
    return "SkipFoundation"
}

#if !SKIP
// The non-Skip version is in FoundationHelpers.kt
func foundationHelperDemo() -> String {
    return "Swift"
}
#endif
