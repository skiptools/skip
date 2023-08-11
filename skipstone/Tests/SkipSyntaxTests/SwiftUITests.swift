import XCTest

final class SwiftUITests: XCTestCase {
    let baseSupportingSwift = """
    import SwiftUI
    
    protocol View {
        @ViewBuilder var body: some View { get }
    }

    extension View {
        func mod() -> some View {
        }
    }

    struct VStack: View {
        init(@ViewBuilder content: () -> any View) {
        }
    }

    struct Text: View {
        init(_ text: String) {
        }
    }

    struct Button: View {
        init(_ text: String, action: () -> Void) {
        }
    }
    """

    func testBody() async throws {
        try await check(supportingSwift: baseSupportingSwift, swift: """
        import SwiftUI
        struct V: View {
            var body: some View {
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.*

        import skip.ui.*
        internal class V: View {
            @Composable
            override fun body(): View {
                return ComposingView { composectx: ComposeContext ->  }
            }
        }
        """)

        try await check(supportingSwift: baseSupportingSwift + """
        protocol MyView: View {
        }
        """, swift: """
        import SwiftUI
        struct V: MyView {
            var body: some View {
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.*

        import skip.ui.*
        internal class V: MyView {
            @Composable
            override fun body(): View {
                return ComposingView { composectx: ComposeContext ->  }
            }
        }
        """)
    }

    func testViewBuilderComposable() async throws {
        try await check(supportingSwift: baseSupportingSwift, swift: """
        import SwiftUI
        protocol P {
            @ViewBuilder var v: any View { get }
            @ViewBuilder func f() -> any View
        }
        class C: P {
            @ViewBuilder var v: some View {
                VStack {}
            }
            var v2: some View {
                VStack {}
            }
            @ViewBuilder func f() -> some View {
                VStack {}
            }
            func f2() -> some View {
                VStack {}
            }
            func f3(b: Bool) -> some View {
                return b ? v : v2
            }
            func f4(b: Bool, c: C) -> some View {
                return b ? c.v : c.v2
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.*

        import skip.ui.*
        internal interface P {
            @Composable
            fun v(): View
            @Composable
            fun f(): View
        }
        internal open class C: P {
            @Composable
            override fun v(): View {
                return ComposingView { composectx: ComposeContext ->
                    VStack {
                        ComposingView { composectx: ComposeContext ->  }
                    }.Compose(composectx)
                }
            }
            internal open val v2: View
                get() {
                    return VStack {
                        ComposingView { composectx: ComposeContext ->  }
                    }
                }
            @Composable
            override fun f(): View {
                return ComposingView { composectx: ComposeContext ->
                    VStack {
                        ComposingView { composectx: ComposeContext ->  }
                    }.Compose(composectx)
                }
            }
            internal open fun f2(): View {
                return VStack {
                    ComposingView { composectx: ComposeContext ->  }
                }
            }
            internal open fun f3(b: Boolean): View = (if (b) v() else v2).sref()
            internal open fun f4(b: Boolean, c: C): View = (if (b) c.v() else c.v2).sref()
        }
        """)
    }

    func testTailCall() async throws {
        let supportingSwift = baseSupportingSwift + """
        struct V: View {
            var body: some View {
                V()
            }
        }
        """

        try await check(supportingSwift: supportingSwift, swift: """
        import SwiftUI
        func f() {
            VStack {
                V()
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.*

        import skip.ui.*
        internal fun f() {
            VStack {
                ComposingView { composectx: ComposeContext -> V().Compose(composectx) }
            }
        }
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        import SwiftUI
        struct MyV: View {
            var body: some View {
                VStack {
                    V().mod()
                }.mod()
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.*

        import skip.ui.*
        internal class MyV: View {
            @Composable
            override fun body(): View {
                return ComposingView { composectx: ComposeContext ->
                    VStack {
                        ComposingView { composectx: ComposeContext -> V().mod().Compose(composectx) }
                    }.mod().Compose(composectx)
                }
            }
        }
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        import SwiftUI
        struct MyV: View {
            var body: some View {
                VStack {
                    let v = V().mod()
                    v
                    v
                }
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.*

        import skip.ui.*
        internal class MyV: View {
            @Composable
            override fun body(): View {
                return ComposingView { composectx: ComposeContext ->
                    VStack {
                        ComposingView { composectx: ComposeContext ->
                            val v = V().mod()
                            v.Compose(composectx)
                            v.Compose(composectx)
                        }
                    }.Compose(composectx)
                }
            }
        }
        """)
    }

    func testComplexTailCall() async throws {
        let supportingSwift = baseSupportingSwift + """
        struct V: View {
            var body: some View {
                V()
            }
        }
        """

        try await check(supportingSwift: supportingSwift, swift: """
        import SwiftUI
        struct MyV: View {
            var body: some View {
                if b(v: V()) {
                    return VStack {
                        V().mod()
                    }
                } else {
                    let test = b(v: V())
                    return v(b: test) {
                        VStack {
                            V().mod()
                        }
                    }
                }
            }
            func b(v: any View) -> Bool {
                return true
            }
            func v(b: Bool, @ViewBuilder c: () -> some View) -> some View {
                return V()
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.*

        import skip.ui.*
        internal class MyV: View {
            @Composable
            override fun body(): View {
                return ComposingView l@{ composectx: ComposeContext ->
                    if (b(v = V())) {
                        return@l VStack {
                            ComposingView { composectx: ComposeContext -> V().mod().Compose(composectx) }
                        }.Compose(composectx)
                    } else {
                        val test = b(v = V())
                        return@l v(b = test) {
                            ComposingView { composectx: ComposeContext ->
                                VStack {
                                    ComposingView { composectx: ComposeContext -> V().mod().Compose(composectx) }
                                }.Compose(composectx)
                            }
                        }.Compose(composectx)
                    }
                }
            }
            internal fun b(v: View): Boolean = true
            internal fun v(b: Boolean, c: @Composable () -> View): View = V()
        }
        """)
    }

    func testStateVariable() async throws {
        try await check(supportingSwift: baseSupportingSwift, swift: """
        import SwiftUI
        @Observable
        class O {
        }
        struct V: View {
            @State var s = 0
            @State var o = O() {
                didSet {
                    print("set o")
                }
            }
            var body: some View {
                VStack {
                    Text("O: \\(o)")
                    Button("Tap") {
                        s += 1
                    }
                }
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.*

        import skip.ui.*
        internal open class O: Observable {
        }
        internal class V: View {
            internal var s = 0
                set(newValue) {
                    field = newValue
                    sdidchange?.invoke()
                }
            private var sdidchange: (() -> Unit)? = null
            internal var o = O()
                set(newValue) {
                    field = newValue
                    odidchange?.invoke()
                    print("set o")
                }
            private var odidchange: (() -> Unit)? = null
            @Composable
            override fun body(): View {
                return ComposingView { composectx: ComposeContext ->
                    VStack {
                        ComposingView { composectx: ComposeContext ->
                            Text("O: ${o}").Compose(composectx)
                            Button("Tap") { s += 1 }.Compose(composectx)
                        }
                    }.Compose(composectx)
                }
            }

            @Composable
            override fun Compose(composectx: ComposeContext) {
                sdidchange = null
                val initials = s
                var composes by remember { mutableStateOf(initials) }
                s = initials
                sdidchange = { composes = s }

                odidchange = null
                val initialo = o
                var composeo by remember { mutableStateOf(initialo) }
                o = initialo
                odidchange = { composeo = o }

                body().Compose(composectx)
            }
        }
        """)
    }

    func testMutableStructStateVariable() async throws {
        try await check(supportingSwift: baseSupportingSwift, swift: """
        import SwiftUI
        struct S {
            var x = 0
        }
        struct V: View {
            @State var s = S()
            var body: some View {
                VStack {
                    Button("Tap") {
                        s = S(x: 100)
                    }
                }
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.*

        import skip.ui.*
        internal class S: MutableStruct {
            internal var x = 0
                set(newValue) {
                    willmutate()
                    field = newValue
                    didmutate()
                }

            constructor(x: Int = 0) {
                this.x = x
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = S(x)
        }
        internal class V: View {
            internal var s = S()
                get() = field.sref({ this.s = it })
                set(newValue) {
                    @Suppress("NAME_SHADOWING") val newValue = newValue.sref()
                    field = newValue
                    sdidchange?.invoke()
                }
            private var sdidchange: (() -> Unit)? = null
            @Composable
            override fun body(): View {
                return ComposingView { composectx: ComposeContext ->
                    VStack {
                        ComposingView { composectx: ComposeContext ->
                            Button("Tap") { s = S(x = 100) }.Compose(composectx)
                        }
                    }.Compose(composectx)
                }
            }

            @Composable
            override fun Compose(composectx: ComposeContext) {
                sdidchange = null
                val initials = s
                var composes by remember { mutableStateOf(initials) }
                s = initials
                sdidchange = { composes = s }

                body().Compose(composectx)
            }
        }
        """)
    }
}
