import XCTest

final class SwiftUITests: XCTestCase {
    let baseSupportingSwift = """
    import SwiftUI
    
    protocol View {}

    extension View {
        func mod() -> some View {
        }
    }

    struct VStack: View {
        init(@ViewBuilder content: () -> any View) {
        }
    }
    """

//    func testBody() async throws {
//        try await check(supportingSwift: baseSupportingSwift, swift: """
//        import SwiftUI
//        struct V: View {
//            var body: some View {
//            }
//        }
//        """, kotlin: """
//        import androidx.compose.runtime.*
//
//        import skip.ui.*
//        internal class V: View {
//            @Composable
//            internal fun body(): View {
//            }
//        }
//        """)
//
//        try await check(supportingSwift: baseSupportingSwift + """
//        protocol MyView: View {
//        }
//        """, swift: """
//        import SwiftUI
//        struct V: MyView {
//            var body: some View {
//            }
//        }
//        """, kotlin: """
//        import androidx.compose.runtime.*
//
//        import skip.ui.*
//        internal class V: MyView {
//            @Composable
//            internal fun body(): View {
//            }
//        }
//        """)
//    }
//
//    func testViewBuilderComposable() async throws {
//        try await check(supportingSwift: baseSupportingSwift, swift: """
//        protocol P {
//            @ViewBuilder var v: any View { get }
//            @ViewBuilder func f() -> any View
//        }
//        class C: P {
//            @ViewBuilder var v: some View {
//                VStack {}
//            }
//            var v2: some View {
//                VStack {}
//            }
//            @ViewBuilder func f() -> some View {
//                VStack {}
//            }
//            func f2() -> some View {
//                VStack {}
//            }
//        }
//        """, kotlin: """
//        internal interface P {
//            @Composable
//            fun v(): View
//            @Composable
//            fun f(): View
//        }
//        internal open class C: P {
//            @Composable
//            override fun v(): View {
//                return VStack {  }
//            }
//            internal open val v2: View
//                get() {
//                    return VStack {  }
//                }
//            @Composable
//            override fun f(): View {
//                return VStack {  }
//            }
//            internal open fun f2(): View {
//                return VStack {  }
//            }
//        }
//        """)
//    }
//
//    func testTailCall() async throws {
//        let supportingSwift = baseSupportingSwift + """
//        struct V: View {
//            var body: some View {
//                V()
//            }
//        }
//        """
//
//        try await check(supportingSwift: supportingSwift, swift: """
//        import SwiftUI
//        func f() {
//            VStack {
//                V()
//            }
//        }
//        """, kotlin: """
//        import androidx.compose.runtime.*
//
//        import skip.ui.*
//        internal fun f() {
//            VStack { V().eval() }
//        }
//        """)
//
//        try await check(supportingSwift: supportingSwift, swift: """
//        import SwiftUI
//        struct MyV: View {
//            var body: some View {
//                VStack {
//                    V().mod()
//                }.mod()
//            }
//        }
//        """, kotlin: """
//        import androidx.compose.runtime.*
//
//        import skip.ui.*
//        internal class MyV: View {
//            @Composable
//            internal fun body(): View {
//                return VStack { V().mod().eval() }.mod().eval()
//            }
//        }
//        """)
//
//        try await check(supportingSwift: supportingSwift, swift: """
//        import SwiftUI
//        struct MyV: View {
//            var body: some View {
//                VStack {
//                    let v = V().mod()
//                    v
//                    v
//                }
//            }
//        }
//        """, kotlin: """
//        import androidx.compose.runtime.*
//
//        import skip.ui.*
//        internal class MyV: View {
//            @Composable
//            internal fun body(): View {
//                return VStack {
//                    val v = V().mod()
//                    v.eval()
//                    v.eval()
//                }.eval()
//            }
//        }
//        """)
//    }
//
//    func testComplexTailCall() async throws {
//        let supportingSwift = baseSupportingSwift + """
//        struct V: View {
//            var body: some View {
//                V()
//            }
//        }
//        """
//
//        try await check(supportingSwift: supportingSwift, swift: """
//        import SwiftUI
//        struct MyV: View {
//            var body: some View {
//                if b(v: V()) {
//                    return VStack {
//                        V().mod()
//                    }
//                } else {
//                    let test = b(v: V())
//                    return v(b: test) {
//                        VStack {
//                            V().mod()
//                        }
//                    }
//                }
//            }
//            func b(v: any View) -> Bool {
//                return true
//            }
//            func v(b: Bool, @ViewBuilder c: () -> some View) -> some View {
//                return V()
//            }
//        }
//        """, kotlin: """
//        import androidx.compose.runtime.*
//
//        import skip.ui.*
//        internal class MyV: View {
//            @Composable
//            internal fun body(): View {
//                if (b(v = V())) {
//                    return VStack { V().mod().eval() }.eval()
//                } else {
//                    val test = b(v = V())
//                    return v(b = test) {
//                        VStack { V().mod().eval() }.eval()
//                    }.eval()
//                }
//            }
//            internal fun b(v: View): Boolean = true
//            internal fun v(b: Boolean, c: @Composable () -> View): View = V()
//        }
//        """)
//    }
}
