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

    struct TextField: View {
        init(_ text: Binding<String>) {
        }
    }

    struct Button: View {
        init(_ text: String, action: () -> Void) {
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
        import androidx.compose.runtime.*

        import skip.ui.*
        internal fun f() {
            VStack {
                ComposingView { composectx: ComposeContext ->
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
        import androidx.compose.runtime.*

        import skip.ui.*
        internal fun f() {
            VStack {
                ComposingView { composectx: ComposeContext ->
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
            internal var s: Int
                get() = _s.wrappedValue
                set(newValue) {
                    _s.wrappedValue = newValue
                }
            internal var _s: State<Int>
            internal var o: O
                get() = _o.wrappedValue
                set(newValue) {
                    _o.wrappedValue = newValue
                    if (!suppresssideeffects) {
                        print("set o")
                    }
                }
            internal var _o: State<O>
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
                val initials = _s.wrappedValue
                var composes by remember { mutableStateOf(initials) }
                _s.sync(composes, { composes = it })

                val initialo = _o.wrappedValue
                var composeo by remember { mutableStateOf(initialo) }
                _o.sync(composeo, { composeo = it })

                body().Compose(composectx)
            }

            constructor(s: Int = 0, o: O = O()) {
                suppresssideeffects = true
                try {
                    this._s = State(s)
                    this._o = State(o)
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
        import androidx.compose.runtime.*

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
            internal var _s: State<S>
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
                val initials = _s.wrappedValue
                var composes by remember { mutableStateOf(initials) }
                _s.sync(composes, { composes = it })

                body().Compose(composectx)
            }

            constructor(s: S = S()) {
                this._s = State(s.sref())
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
        import androidx.compose.runtime.*
        
        import skip.ui.*
        internal class V: View {
            internal var envvalue: Int = Int(0)
            @Composable
            override fun body(): View {
                return ComposingView { composectx: ComposeContext -> Text("Value: ${envvalue}").Compose(composectx) }
            }
        
            @Composable
            override fun Compose(composectx: ComposeContext) {
                envvalue = composectx.environment[EnvironmentValues::envvalue]
        
                body().Compose(composectx)
            }
        }
        """)
    }

    func testTypeEnvironmentVariable() async throws {
        try await check(supportingSwift: baseSupportingSwift, swift: """
        import SwiftUI
        struct V: View {
            @Environment(EnvValue.self) var envvalue
            var body: some View {
                Text("Value: \\(envvalue.x)")
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.*

        import skip.ui.*
        internal class V: View {
            internal var envvalue: EnvValue
                get() = envvaluestorage.sref({ this.envvalue = it })
                set(newValue) {
                    envvaluestorage = newValue.sref()
                }
            private lateinit var envvaluestorage: EnvValue
            @Composable
            override fun body(): View {
                return ComposingView { composectx: ComposeContext -> Text("Value: ${envvalue.x}").Compose(composectx) }
            }

            @Composable
            override fun Compose(composectx: ComposeContext) {
                envvalue = composectx.environment[EnvValue::class]

                body().Compose(composectx)
            }
        }
        """)

        try await check(supportingSwift: baseSupportingSwift, swift: """
        import SwiftUI
        struct V: View {
            @EnvironmentObject(EnvValue.self) var envvalue
            var body: some View {
                Text("Value: \\(envvalue.x)")
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.*

        import skip.ui.*
        internal class V: View {
            internal var envvalue: EnvValue
                get() = envvaluestorage.sref({ this.envvalue = it })
                set(newValue) {
                    envvaluestorage = newValue.sref()
                }
            private lateinit var envvaluestorage: EnvValue
            @Composable
            override fun body(): View {
                return ComposingView { composectx: ComposeContext -> Text("Value: ${envvalue.x}").Compose(composectx) }
            }

            @Composable
            override fun Compose(composectx: ComposeContext) {
                envvalue = composectx.environment[EnvValue::class]

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
        import androidx.compose.runtime.*

        import skip.ui.*
        internal class V: View {
            internal var count: Int
                get() = _count.get()
                set(newValue) {
                    _count.set(newValue)
                }
            internal var _count: Binding<Int>
            @Composable
            override fun body(): View {
                return ComposingView { composectx: ComposeContext ->
                    Button("Tap") { count += 1 }.Compose(composectx)
                }
            }

            constructor(count: Binding<Int>) {
                this._count = count
            }
        }
        """)
    }

    func testPassBinding() async throws {
        try await check(supportingSwift: baseSupportingSwift, swift: """
        import SwiftUI
        struct V: View {
            @State var text = ""
            var body: some View {
                TextField($text)
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.*

        import skip.ui.*
        internal class V: View {
            internal var text: String
                get() = _text.wrappedValue
                set(newValue) {
                    _text.wrappedValue = newValue
                }
            internal var _text: State<String>
            @Composable
            override fun body(): View {
                return ComposingView { composectx: ComposeContext -> TextField(Binding({ text }, { text = it })).Compose(composectx) }
            }

            @Composable
            override fun Compose(composectx: ComposeContext) {
                val initialtext = _text.wrappedValue
                var composetext by remember { mutableStateOf(initialtext) }
                _text.sync(composetext, { composetext = it })

                body().Compose(composectx)
            }

            constructor(text: String = "") {
                this._text = State(text)
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
        import androidx.compose.runtime.*

        import skip.ui.*
        internal class V: View {
            internal var text: String
                get() = _text.wrappedValue
                set(newValue) {
                    _text.wrappedValue = newValue
                }
            internal var _text: State<String>
            @Composable
            override fun body(): View {
                return ComposingView { composectx: ComposeContext -> TextField(InstanceBinding(this, { it.text }, { it, newvalue -> it.text = newvalue })).Compose(composectx) }
            }

            @Composable
            override fun Compose(composectx: ComposeContext) {
                val initialtext = _text.wrappedValue
                var composetext by remember { mutableStateOf(initialtext) }
                _text.sync(composetext, { composetext = it })

                body().Compose(composectx)
            }

            constructor(text: String = "") {
                this._text = State(text)
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
        import androidx.compose.runtime.*

        import skip.ui.*
        internal class V: View {
            internal var o: O
            @Composable
            override fun body(): View {
                return ComposingView { composectx: ComposeContext -> TextField(InstanceBinding(o, { it.string }, { it, newvalue -> it.string = newvalue })).Compose(composectx) }
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
        import androidx.compose.runtime.*

        import skip.ui.*
        internal class V: View {
            internal var o: O
            @Composable
            override fun body(): View {
                return ComposingView { composectx: ComposeContext -> TextField(InstanceBinding(this.o, { it.s.string }, { it, newvalue -> it.s.string = newvalue })).Compose(composectx) }
            }

            constructor(o: O) {
                this.o = o
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
        import androidx.compose.runtime.*

        import skip.ui.*
        internal class V: View, MutableStruct {
            internal var envvalue: Int = Int(0)
            internal var count: Int
                get() = _count.wrappedValue
                set(newValue) {
                    _count.wrappedValue = newValue
                }
            internal var _count: State<Int>
            internal var text: String
                get() = _text.get()
                set(newValue) {
                    _text.set(newValue)
                }
            internal var _text: Binding<String>
            internal var i: Int
                set(newValue) {
                    willmutate()
                    field = newValue
                    didmutate()
                }

            @Composable
            override fun body(): View {
                return ComposingView { composectx: ComposeContext -> Text("Hello").Compose(composectx) }
            }

            @Composable
            override fun Compose(composectx: ComposeContext) {
                val initialcount = _count.wrappedValue
                var composecount by remember { mutableStateOf(initialcount) }
                _count.sync(composecount, { composecount = it })

                envvalue = composectx.environment[EnvironmentValues::envvalue]

                body().Compose(composectx)
            }

            constructor(count: Int = 0, text: Binding<String>, i: Int = 0) {
                this._count = State(count)
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
        import androidx.compose.runtime.*

        import skip.ui.*
        internal class V: View, MutableStruct {
            internal var envvalue: Int = Int(0)
            internal var count: Int
                get() = _count.wrappedValue
                set(newValue) {
                    _count.wrappedValue = newValue
                }
            internal var _count: State<Int> = State(0)
            internal var text: String
                get() = _text.get()
                set(newValue) {
                    _text.set(newValue)
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

            @Composable
            override fun body(): View {
                return ComposingView { composectx: ComposeContext -> Text("Hello").Compose(composectx) }
            }

            @Composable
            override fun Compose(composectx: ComposeContext) {
                val initialcount = _count.wrappedValue
                var composecount by remember { mutableStateOf(initialcount) }
                _count.sync(composecount, { composecount = it })

                envvalue = composectx.environment[EnvironmentValues::envvalue]

                body().Compose(composectx)
            }

            private constructor(copy: MutableStruct) {
                @Suppress("NAME_SHADOWING") val copy = copy as V
                this._count = State(copy.count)
                this._text = copy._text
                this.i = copy.i
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = V(this as MutableStruct)
        }
        """)
    }
}
