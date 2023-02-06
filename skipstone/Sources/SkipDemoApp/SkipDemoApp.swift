#if !SKIP
import SkipUI
import SkipFoundation

@main
struct MyApp {}

extension MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
#endif

internal func SkipDemoAppInternalModuleName() -> String {
    return "SkipDemoApp"
}

public func SkipDemoAppPublicModuleName() -> String {
    return "SkipDemoApp"
}
