#if !SKIP
@_exported import Foundation
#endif

internal func CrossFoundationInternalModuleName() -> String {
    return "CrossFoundation"
}

public func CrossFoundationPublicModuleName() -> String {
    return "CrossFoundation"
}

#if !SKIP
// The non-Skip version is in FoundationHelpers.kt
func foundationHelperDemo() -> String {
    return "Swift"
}
#endif
