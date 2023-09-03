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

        func navigationDestination(for: Any, @ViewBuilder destination: (Any) -> any View) -> some View {
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

    struct TextField: View {
        init(_ text: Binding<String>) {
        }
    }

    struct Button: View {
        init(_ text: String, action: () -> Void) {
        }
    }

    struct NavigationStack: View {
        init(@ViewBuilder content: () -> any View) {
        }
    }

    class EnvironmentValues {
    }

    extension EnvironmentValues {
        var envvalue: Int {
            return 0
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
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        internal class V: View {
            override fun body(): View {
                return ComposeView { composectx: ComposeContext ->  }
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
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        internal class V: MyView {
            override fun body(): View {
                return ComposeView { composectx: ComposeContext ->  }
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
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        internal interface P {
            fun v(): View
            fun f(): View
        }
        internal open class C: P {
            override fun v(): View {
                return ComposeView { composectx: ComposeContext ->
                    VStack {
                        ComposeView { composectx: ComposeContext ->  }
                    }.Compose(composectx)
                }
            }
            internal open val v2: View
                get() {
                    return VStack {
                        ComposeView { composectx: ComposeContext ->  }
                    }
                }
            override fun f(): View {
                return ComposeView { composectx: ComposeContext ->
                    VStack {
                        ComposeView { composectx: ComposeContext ->  }
                    }.Compose(composectx)
                }
            }
            internal open fun f2(): View {
                return VStack {
                    ComposeView { composectx: ComposeContext ->  }
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
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        internal fun f() {
            VStack {
                ComposeView { composectx: ComposeContext -> V().Compose(composectx) }
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
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        internal class MyV: View {
            override fun body(): View {
                return ComposeView { composectx: ComposeContext ->
                    VStack {
                        ComposeView { composectx: ComposeContext -> V().mod().Compose(composectx) }
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
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        internal class MyV: View {
            override fun body(): View {
                return ComposeView { composectx: ComposeContext ->
                    VStack {
                        ComposeView { composectx: ComposeContext ->
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
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        internal class MyV: View {
            override fun body(): View {
                return ComposeView l@{ composectx: ComposeContext ->
                    if (b(v = V())) {
                        return@l VStack {
                            ComposeView { composectx: ComposeContext -> V().mod().Compose(composectx) }
                        }.Compose(composectx)
                    } else {
                        val test = b(v = V())
                        return@l v(b = test) {
                            ComposeView { composectx: ComposeContext ->
                                VStack {
                                    ComposeView { composectx: ComposeContext -> V().mod().Compose(composectx) }
                                }.Compose(composectx)
                            }
                        }.Compose(composectx)
                    }
                }
            }
            internal fun b(v: View): Boolean = true
            internal fun v(b: Boolean, c: () -> View): View = V()
        }
        """)
    }

    func testConditionalExpressionTailCall() async throws {
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
                let v = if true { V() } else { V() }
                v
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        internal fun f() {
            VStack {
                ComposeView { composectx: ComposeContext ->
                    val v = if (true) {
                        V()
                    } else {
                        V()
                    }
                    v.Compose(composectx)
                }
            }
        }
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        import SwiftUI
        func f() {
            VStack {
                let i = 1
                let v = switch i {
                    case 0: V()
                    default: V()
                }
                v
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        internal fun f() {
            VStack {
                ComposeView { composectx: ComposeContext ->
                    val i = 1
                    val v = when (i) {
                        0 -> V()
                        else -> V()
                    }
                    v.Compose(composectx)
                }
            }
        }
        """)
    }

    func testTypeInferenceMessage() async throws {
        try await checkProducesMessage(swift: """
        import SwiftUI
        @ViewBuilder func f() -> some View {
            X()
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
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.Stable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        internal open class O: Observable {
        }
        internal class V: View {
            internal var s: Int
                get() = _s.wrappedValue
                set(newValue) {
                    _s.wrappedValue = newValue
                }
            internal var _s: skip.ui.State<Int>
            internal var o: O
                get() = _o.wrappedValue
                set(newValue) {
                    _o.wrappedValue = newValue
                    if (!suppresssideeffects) {
                        print("set o")
                    }
                }
            internal var _o: skip.ui.State<O>
            override fun body(): View {
                return ComposeView { composectx: ComposeContext ->
                    VStack {
                        ComposeView { composectx: ComposeContext ->
                            Text("O: ${o}").Compose(composectx)
                            Button("Tap") { s += 1 }.Compose(composectx)
                        }
                    }.Compose(composectx)
                }
            }

            @Composable
            @Suppress(\"UNCHECKED_CAST\")
            override fun ComposeContent(composectx: ComposeContext) {
                val initials = _s.wrappedValue
                var composes by rememberSaveable(stateSaver = composectx.stateSaver as Saver<Int, Any>) { mutableStateOf(initials) }
                _s.sync(composes, { composes = it })

                val initialo = _o.wrappedValue
                var composeo by rememberSaveable(stateSaver = composectx.stateSaver as Saver<O, Any>) { mutableStateOf(initialo) }
                _o.sync(composeo, { composeo = it })

                body().Compose(composectx)
            }

            constructor(s: Int = 0, o: O = O()) {
                suppresssideeffects = true
                try {
                    this._s = skip.ui.State(s)
                    this._o = skip.ui.State(o)
                } finally {
                    suppresssideeffects = false
                }
            }

            private var suppresssideeffects = false
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
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        internal class S: MutableStruct {
            internal var x: Int
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
            internal var s: S
                get() = _s.wrappedValue.sref({ this.s = it })
                set(newValue) {
                    _s.wrappedValue = newValue.sref()
                }
            internal var _s: skip.ui.State<S>
            override fun body(): View {
                return ComposeView { composectx: ComposeContext ->
                    VStack {
                        ComposeView { composectx: ComposeContext ->
                            Button("Tap") { s = S(x = 100) }.Compose(composectx)
                        }
                    }.Compose(composectx)
                }
            }

            @Composable
            @Suppress(\"UNCHECKED_CAST\")
            override fun ComposeContent(composectx: ComposeContext) {
                val initials = _s.wrappedValue
                var composes by rememberSaveable(stateSaver = composectx.stateSaver as Saver<S, Any>) { mutableStateOf(initials) }
                _s.sync(composes, { composes = it })

                body().Compose(composectx)
            }

            constructor(s: S = S()) {
                this._s = skip.ui.State(s.sref())
            }
        }
        """)
    }

    func testKeyedEnvironmentVariable() async throws {
        try await check(supportingSwift: baseSupportingSwift, swift: """
        import SwiftUI
        struct V: View {
            @Environment(\\.envvalue) var envvalue
            var body: some View {
                Text("Value: \\(envvalue)")
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        internal class V: View {
            internal var envvalue: Int = Int(0)
            override fun body(): View {
                return ComposeView { composectx: ComposeContext -> Text("Value: ${envvalue}").Compose(composectx) }
            }
        
            @Composable
            override fun ComposeContent(composectx: ComposeContext) {
                envvalue = EnvironmentValues.shared.envvalue

                body().Compose(composectx)
            }
        }
        """)
    }

    func testTypeEnvironmentVariable() async throws {
        let supportingSwift = baseSupportingSwift + """
        class EnvValue {
        }
        """

        try await check(supportingSwift: supportingSwift, swift: """
        import SwiftUI
        struct V: View {
            @Environment(EnvValue.self) var envvalue
            var body: some View {
                Text("Value: \\(envvalue.x)")
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        internal class V: View {
            internal lateinit var envvalue: EnvValue
            override fun body(): View {
                return ComposeView { composectx: ComposeContext -> Text("Value: ${envvalue.x}").Compose(composectx) }
            }

            @Composable
            override fun ComposeContent(composectx: ComposeContext) {
                envvalue = EnvironmentValues.shared.environmentObject(type = EnvValue::class)!!

                body().Compose(composectx)
            }
        }
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        import SwiftUI
        struct V: View {
            @EnvironmentObject var envvalue: EnvValue
            var body: some View {
                Text("Value: \\(envvalue.x)")
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        internal class V: View {
            internal lateinit var envvalue: EnvValue
            override fun body(): View {
                return ComposeView { composectx: ComposeContext -> Text("Value: ${envvalue.x}").Compose(composectx) }
            }

            @Composable
            override fun ComposeContent(composectx: ComposeContext) {
                envvalue = EnvironmentValues.shared.environmentObject(type = EnvValue::class)!!

                body().Compose(composectx)
            }
        }
        """)
    }

    func testNestedTypeEnvironmentVariable() async throws {
        try await check(supportingSwift: baseSupportingSwift, swift: """
        import SwiftUI
        struct V: View {
            @Environment(EnvValue.self) var envvalue
            var body: some View {
                Text("Value: \\(envvalue.x)")
            }
            class EnvValue {
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        internal class V: View {
            internal lateinit var envvalue: V.EnvValue
            override fun body(): View {
                return ComposeView { composectx: ComposeContext -> Text("Value: ${envvalue.x}").Compose(composectx) }
            }

            @Composable
            override fun ComposeContent(composectx: ComposeContext) {
                envvalue = EnvironmentValues.shared.environmentObject(type = V.EnvValue::class)!!

                body().Compose(composectx)
            }
            internal open class EnvValue {
            }
        }
        """)
    }

    func testOptionalTypeEnvironmentVariable() async throws {
        try await check(supportingSwift: baseSupportingSwift + """
        class EnvValue {
            var x = 0
        }
        """, swift: """
        import SwiftUI
        struct V: View {
            @Environment(EnvValue.self) var envvalue: EnvValue?
            var body: some View {
                Text("Value: \\(envvalue?.x ?? 1)")
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        internal class V: View {
            internal var envvalue: EnvValue? = null
            override fun body(): View {
                return ComposeView { composectx: ComposeContext -> Text("Value: ${envvalue?.x ?: 1}").Compose(composectx) }
            }

            @Composable
            override fun ComposeContent(composectx: ComposeContext) {
                envvalue = EnvironmentValues.shared.environmentObject(type = EnvValue::class)

                body().Compose(composectx)
            }
        }
        """)
    }

    func testBindingVariable() async throws {
        try await check(supportingSwift: baseSupportingSwift, swift: """
        import SwiftUI
        struct V: View {
            @Binding var count: Int
            var body: some View {
                Button("Tap") {
                    count += 1
                }
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        internal class V: View {
            internal var count: Int
                get() = _count.wrappedValue
                set(newValue) {
                    _count.wrappedValue = newValue
                }
            internal var _count: Binding<Int>
            override fun body(): View {
                return ComposeView { composectx: ComposeContext ->
                    Button("Tap") { count += 1 }.Compose(composectx)
                }
            }

            constructor(count: Binding<Int>) {
                this._count = count
            }
        }
        """)
    }

    func testBinding() async throws {
        try await check(supportingSwift: baseSupportingSwift, swift: """
        import SwiftUI
        struct V: View {
            @State var text = ""
            var body: some View {
                TextField($text)
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        internal class V: View {
            internal var text: String
                get() = _text.wrappedValue
                set(newValue) {
                    _text.wrappedValue = newValue
                }
            internal var _text: skip.ui.State<String>
            override fun body(): View {
                return ComposeView { composectx: ComposeContext -> TextField(Binding({ text }, { it -> text = it })).Compose(composectx) }
            }

            @Composable
            @Suppress("UNCHECKED_CAST")
            override fun ComposeContent(composectx: ComposeContext) {
                val initialtext = _text.wrappedValue
                var composetext by rememberSaveable(stateSaver = composectx.stateSaver as Saver<String, Any>) { mutableStateOf(initialtext) }
                _text.sync(composetext, { composetext = it })

                body().Compose(composectx)
            }

            constructor(text: String = "") {
                this._text = skip.ui.State(text)
            }
        }
        """)
    }

    func testSelfBinding() async throws {
        try await check(supportingSwift: baseSupportingSwift, swift: """
        import SwiftUI
        struct V: View {
            @State var text = ""
            var body: some View {
                TextField(self.$text)
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        internal class V: View {
            internal var text: String
                get() = _text.wrappedValue
                set(newValue) {
                    _text.wrappedValue = newValue
                }
            internal var _text: skip.ui.State<String>
            override fun body(): View {
                return ComposeView { composectx: ComposeContext -> TextField(Binding.instance(this, { it.text }, { it, newvalue -> it.text = newvalue })).Compose(composectx) }
            }

            @Composable
            @Suppress(\"UNCHECKED_CAST\")
            override fun ComposeContent(composectx: ComposeContext) {
                val initialtext = _text.wrappedValue
                var composetext by rememberSaveable(stateSaver = composectx.stateSaver as Saver<String, Any>) { mutableStateOf(initialtext) }
                _text.sync(composetext, { composetext = it })

                body().Compose(composectx)
            }

            constructor(text: String = "") {
                this._text = skip.ui.State(text)
            }
        }
        """)
    }

    func testBindable() async throws {
        try await check(supportingSwift: baseSupportingSwift + """
        @Observable class O {
            var string = ""
        }
        """, swift: """
        import SwiftUI
        struct V: View {
            @Bindable var o: O
            var body: some View {
                TextField($o.string)
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        internal class V: View {
            internal var o: O
            override fun body(): View {
                return ComposeView { composectx: ComposeContext -> TextField(Binding.instance(o, { it.string }, { it, newvalue -> it.string = newvalue })).Compose(composectx) }
            }

            constructor(o: O) {
                this.o = o
            }
        }
        """)

        try await check(supportingSwift: baseSupportingSwift + """
        @Observable class O {
            var s = S()
        }
        struct S {
            var string = ""
        }
        """, swift: """
        import SwiftUI
        struct V: View {
            @Bindable var o: O
            var body: some View {
                TextField(self.$o.s.string)
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        internal class V: View {
            internal var o: O
            override fun body(): View {
                return ComposeView { composectx: ComposeContext -> TextField(Binding.instance(this.o, { it.s.string }, { it, newvalue -> it.s.string = newvalue })).Compose(composectx) }
            }

            constructor(o: O) {
                this.o = o
            }
        }
        """)
    }

    func testBindableSubscript() async throws {
        try await check(supportingSwift: baseSupportingSwift + """
        @Observable class O {
            var strings: [String] = []
        }
        """, swift: """
        import SwiftUI
        struct V: View {
            @Bindable var o: O
            var body: some View {
                TextField($o.strings[0])
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        internal class V: View {
            internal var o: O
            override fun body(): View {
                return ComposeView { composectx: ComposeContext -> TextField(Binding.instance(o, { it.strings[0] }, { it, newvalue -> it.strings[0] = newvalue })).Compose(composectx) }
            }

            constructor(o: O) {
                this.o = o
            }
        }
        """)
    }

    func testInlineBindable() async throws {
        try await check(supportingSwift: baseSupportingSwift + """
        @Observable class O {
            var string = ""
        }
        """, swift: """
        import SwiftUI
        struct V: View {
            let os: [O]
            var body: some View {
                for o in os {
                    @Bindable var o = o
                    TextField($o.string)
                }
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue
        import skip.lib.Array

        import skip.ui.*
        internal class V: View {
            internal val os: Array<O>
            override fun body(): View {
                return ComposeView { composectx: ComposeContext ->
                    for (o in os.sref()) {
                        var o = o
                        TextField(Binding.instance(o, { it.string }, { it, newvalue -> it.string = newvalue })).Compose(composectx)
                    }
                }
            }

            constructor(os: Array<O>) {
                this.os = os.sref()
            }
        }
        """)
    }

    func testMutableViewMemberwiseConstructor() async throws {
        try await check(supportingSwift: baseSupportingSwift, swift: """
        import SwiftUI
        struct V: View {
            @Environment(\\.envvalue) var envvalue
            @State var count = 0
            @Binding var text: String
            var i = 0

            var body: some View {
                Text("Hello")
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        internal class V: View, MutableStruct {
            internal var envvalue: Int = Int(0)
            internal var count: Int
                get() = _count.wrappedValue
                set(newValue) {
                    _count.wrappedValue = newValue
                }
            internal var _count: skip.ui.State<Int>
            internal var text: String
                get() = _text.wrappedValue
                set(newValue) {
                    _text.wrappedValue = newValue
                }
            internal var _text: Binding<String>
            internal var i: Int
                set(newValue) {
                    willmutate()
                    field = newValue
                    didmutate()
                }

            override fun body(): View {
                return ComposeView { composectx: ComposeContext -> Text("Hello").Compose(composectx) }
            }

            @Composable
            @Suppress(\"UNCHECKED_CAST\")
            override fun ComposeContent(composectx: ComposeContext) {
                val initialcount = _count.wrappedValue
                var composecount by rememberSaveable(stateSaver = composectx.stateSaver as Saver<Int, Any>) { mutableStateOf(initialcount) }
                _count.sync(composecount, { composecount = it })

                envvalue = EnvironmentValues.shared.envvalue

                body().Compose(composectx)
            }

            constructor(count: Int = 0, text: Binding<String>, i: Int = 0) {
                this._count = skip.ui.State(count)
                this._text = text
                this.i = i
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = V(count, _text, i)
        }
        """)
    }

    func testMutableViewCopyConstructor() async throws {
        try await check(supportingSwift: baseSupportingSwift, swift: """
        import SwiftUI
        struct V: View {
            @Environment(\\.envvalue) var envvalue
            @State var count = 0
            @Binding var text: String
            var i = 0
        
            init(text: Binding<String>) {
                self._text = text
            }
        
            var body: some View {
                Text("Hello")
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        internal class V: View, MutableStruct {
            internal var envvalue: Int = Int(0)
            internal var count: Int
                get() = _count.wrappedValue
                set(newValue) {
                    _count.wrappedValue = newValue
                }
            internal var _count: skip.ui.State<Int> = skip.ui.State(0)
            internal var text: String
                get() = _text.wrappedValue
                set(newValue) {
                    _text.wrappedValue = newValue
                }
            internal var _text: Binding<String>
            internal var i = 0
                set(newValue) {
                    willmutate()
                    field = newValue
                    didmutate()
                }

            internal constructor(text: Binding<String>) {
                this._text = text.sref()
            }

            override fun body(): View {
                return ComposeView { composectx: ComposeContext -> Text("Hello").Compose(composectx) }
            }

            @Composable
            @Suppress(\"UNCHECKED_CAST\")
            override fun ComposeContent(composectx: ComposeContext) {
                val initialcount = _count.wrappedValue
                var composecount by rememberSaveable(stateSaver = composectx.stateSaver as Saver<Int, Any>) { mutableStateOf(initialcount) }
                _count.sync(composecount, { composecount = it })

                envvalue = EnvironmentValues.shared.envvalue

                body().Compose(composectx)
            }

            private constructor(copy: MutableStruct) {
                @Suppress("NAME_SHADOWING") val copy = copy as V
                this._count = skip.ui.State(copy.count)
                this._text = copy._text
                this.i = copy.i
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = V(this as MutableStruct)
        }
        """)
    }

    func testContainerView() async throws {
        try await check(supportingSwift: baseSupportingSwift, swift: """
        import SwiftUI
        struct HStack<Content> : View where Content : View {
            let content: Content

            init(@ViewBuilder content: () -> Content) {
                self.content = content()
            }

            var body: some View {
                content
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        internal class HStack<Content>: View where Content: View {
            internal val content: Content

            internal constructor(content: () -> Content) {
                this.content = content()
            }

            override fun body(): View {
                return ComposeView { composectx: ComposeContext -> content.Compose(composectx) }
            }
        }
        """)
    }

    func testOmitPreviews() async throws {
        try await check(supportingSwift: baseSupportingSwift, swift: """
        import SwiftUI
        struct MyV: View {
            var body: some View {
                return Text("Hello")
            }
        }
        struct MyV_Previews: PreviewProvider {
            static var previews: some View {
                MyV()
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        internal class MyV: View {
            override fun body(): View {
                return ComposeView { composectx: ComposeContext -> Text("Hello").Compose(composectx) }
            }
        }
        """)
    }

    func testEmbedCompose() async throws {
        try await check(supportingSwift: baseSupportingSwift + """
        #if SKIP
        struct ComposeView: View {
            let content: @Composable (ComposeContext) -> Void
            init(content: @Composable (ComposeContext) -> Void) {
                self.content = content
            }
            @Composable public override func ComposeContentcontext: ComposeContext) {
                content(context)
            }
        }
        #endif
        """, swift: """
        import SwiftUI
        struct MyV: View {
            var body: some View {
                Text("x")
                ComposeView {
                    androidx.compose.Column(modifier: $0.modifier) {
                        androidx.compose.Text("y")
                    }
                }
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        internal class MyV: View {
            override fun body(): View {
                return ComposeView { composectx: ComposeContext ->
                    Text("x").Compose(composectx)
                    ComposeView { it ->
                        androidx.compose.Column(modifier = it.modifier) { androidx.compose.Text("y") }
                    }.Compose(composectx)
                }
            }
        }
        """)
    }

    func testViewTypeInference() async throws {
        try await check(supportingSwift: baseSupportingSwift + """
        struct Color: View {
            init(value: Int) {
            }

            var body: some View {
                VStack {}
            }
        }
        extension Color {
            static let red = Color(value: 1)
        }
        """, swift: """
        import SwiftUI
        struct MyV: View {
            var body: some View {
                Color.red
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        internal class MyV: View {
            override fun body(): View {
                return ComposeView { composectx: ComposeContext -> Color.red.Compose(composectx) }
            }
        }
        """)
    }

    func testCustomEnvironmentValue() async throws {
        try await check(supportingSwift: """
        struct S {
            var x = 0
        }
        """, swift: """
        import SwiftUI
        struct EnvironmentValues {
        }
        struct MyKey {
        }
        extension EnvironmentValues {
            var intValue: Int {
                get { return self[MyKey.self] }
                set { self[MyKey.self] = newValue }
            }
            var mutableStructValue: S {
                get { return self[MyKey.self] }
                set { self[MyKey.self] = newValue }
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        internal class EnvironmentValues {

            internal val intValue: Int
                @Composable
                get() = this[MyKey::class]
            internal fun setintValue(newValue: Int) {
                this[MyKey::class] = newValue
            }
            internal val mutableStructValue: S
                @Composable
                get() = this[MyKey::class].sref()
            internal fun setmutableStructValue(newValue: S) {
                this[MyKey::class] = newValue.sref()
            }
        }
        internal class MyKey {
        }
        """)
    }

    func testCustomEnvironmentKey() async throws {
        try await check(supportingSwift: baseSupportingSwift, swift: """
        import SwiftUI
        struct MyKey {
        }
        extension MyKey: EnvironmentKey {
            static var defaultValue = ""
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        class MyKey: EnvironmentKey<String> {

            companion object: EnvironmentKeyCompanion<String> {

                override var defaultValue = ""
            }
        }
        """)
    }

    func testEnvironmentModifier() async throws {
        try await check(supportingSwift: baseSupportingSwift + """
        struct Font {
            static let body = Font()
        }
        struct EnvironmentValues {
            var font: Font
        }
        extension View {
            func environment<V>(_ setValue: (V) -> Void, _ value: V) -> some View {
            }
        }
        """, swift: """
        import SwiftUI
        struct MyV: View {
            var body: some View {
                VStack().environment(\\.font, .body)
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        internal class MyV: View {
            override fun body(): View {
                return ComposeView { composectx: ComposeContext ->
                    VStack().environment({ EnvironmentValues.shared.setfont(it) }, Font.body).Compose(composectx)
                }
            }
        }
        """)
    }
}
