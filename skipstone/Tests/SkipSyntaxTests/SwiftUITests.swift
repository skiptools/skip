import XCTest

final class SwiftUITests: XCTestCase {
    let baseSupportingSwift = """
    import SwiftUI
    
    protocol View {
        @ViewBuilder @MainActor var body: some View { get }
    }

    extension View {
        func mod() -> some View {
        }
    }

    protocol ViewModifier {
        typealias Content = View
        func body(content: View) -> View
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
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class V: View {
            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext -> ComposeResult.ok }
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
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class V: MyView {
            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext -> ComposeResult.ok }
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
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal interface P {
            fun v(): View
            fun f(): View
        }
        internal open class C: P {
            override fun v(): View {
                return ComposeBuilder { composectx: ComposeContext ->
                    VStack { ->
                        ComposeBuilder { composectx: ComposeContext -> ComposeResult.ok }
                    }.Compose(composectx)
                }
            }
            internal open val v2: View
                get() {
                    return VStack { ->
                        ComposeBuilder { composectx: ComposeContext -> ComposeResult.ok }
                    }
                }
            override fun f(): View {
                return ComposeBuilder { composectx: ComposeContext ->
                    VStack { ->
                        ComposeBuilder { composectx: ComposeContext -> ComposeResult.ok }
                    }.Compose(composectx)
                }
            }
            internal open fun f2(): View {
                return VStack { ->
                    ComposeBuilder { composectx: ComposeContext -> ComposeResult.ok }
                }
            }
            internal open fun f3(b: Boolean): View = (if (b) v() else v2).sref()
            internal open fun f4(b: Boolean, c: C): View = (if (b) c.v() else c.v2).sref()
        }
        """)
    }

    func testNestedView() async throws {
        try await check(supportingSwift: baseSupportingSwift, swift: """
        import SwiftUI
        struct V: View {
            var body: some View {
                MyText()
            }

            private struct MyText: View {
                var body: some View {
                    Text("Hello")
                }
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class V: View {
            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext -> MyText().Compose(composectx) }
            }

            private class MyText: View {
                override fun body(): View {
                    return ComposeBuilder { composectx: ComposeContext -> Text("Hello").Compose(composectx) }
                }
            }
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
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal fun f() {
            VStack { ->
                ComposeBuilder { composectx: ComposeContext ->
                    V().Compose(composectx)
                    ComposeResult.ok
                }
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
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class MyV: View {
            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext ->
                    VStack { ->
                        ComposeBuilder { composectx: ComposeContext ->
                            V().mod().Compose(composectx)
                            ComposeResult.ok
                        }
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
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class MyV: View {
            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext ->
                    VStack { ->
                        ComposeBuilder { composectx: ComposeContext ->
                            val v = V().mod()
                            v.Compose(composectx)
                            v.Compose(composectx)
                            ComposeResult.ok
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
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class MyV: View {
            override fun body(): View {
                return ComposeBuilder l@{ composectx: ComposeContext ->
                    if (b(v = V())) {
                        return@l VStack { ->
                            ComposeBuilder { composectx: ComposeContext ->
                                V().mod().Compose(composectx)
                                ComposeResult.ok
                            }
                        }.Compose(composectx)
                    } else {
                        val test = b(v = V())
                        return@l v(b = test) { ->
                            ComposeBuilder { composectx: ComposeContext ->
                                VStack { ->
                                    ComposeBuilder { composectx: ComposeContext ->
                                        V().mod().Compose(composectx)
                                        ComposeResult.ok
                                    }
                                }.Compose(composectx)
                                ComposeResult.ok
                            }
                        }.Compose(composectx)
                    }
                    ComposeResult.ok
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
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal fun f() {
            VStack { ->
                ComposeBuilder { composectx: ComposeContext ->
                    val v = if (true) {
                        V()
                    } else {
                        V()
                    }
                    v.Compose(composectx)
                    ComposeResult.ok
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
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal fun f() {
            VStack { ->
                ComposeBuilder { composectx: ComposeContext ->
                    val i = 1
                    val v = when (i) {
                        0 -> V()
                        else -> V()
                    }
                    v.Compose(composectx)
                    ComposeResult.ok
                }
            }
        }
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        import SwiftUI
        @ViewBuilder func f(i: Int?) -> some View {
            if let i {
                V()
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal fun f(i: Int?): View {
            return ComposeBuilder { composectx: ComposeContext ->
                if (i != null) {
                    V().Compose(composectx)
                }
                ComposeResult.ok
            }
        }
        """)
    }

    func testGenericConstrainedToView() async throws {
        try await check(supportingSwift: baseSupportingSwift, swift: """
        import SwiftUI
        struct V: View {
            @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
                if condition {
                    transform(self)
                } else {
                    self
                }
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class V: View {
            internal fun <Content> if_(condition: Boolean, transform: (V) -> Content): View where Content: View {
                return ComposeBuilder { composectx: ComposeContext ->
                    if (condition) {
                        transform(this).Compose(composectx)
                    } else {
                        this.Compose(composectx)
                    }
                    ComposeResult.ok
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
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        @Stable
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
                return ComposeBuilder { composectx: ComposeContext ->
                    VStack { ->
                        ComposeBuilder { composectx: ComposeContext ->
                            Text("O: ${o}").Compose(composectx)
                            Button("Tap") { -> s += 1 }.Compose(composectx)
                            ComposeResult.ok
                        }
                    }.Compose(composectx)
                }
            }

            @Composable
            @Suppress("UNCHECKED_CAST")
            override fun ComposeContent(composectx: ComposeContext) {
                val remembereds by rememberSaveable(stateSaver = composectx.stateSaver as Saver<skip.ui.State<Int>, Any>) { mutableStateOf(_s) }
                _s = remembereds

                val rememberedo by rememberSaveable(stateSaver = composectx.stateSaver as Saver<skip.ui.State<O>, Any>) { mutableStateOf(_o) }
                _o = rememberedo

                super.ComposeContent(composectx)
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
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
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
                return ComposeBuilder { composectx: ComposeContext ->
                    VStack { ->
                        ComposeBuilder { composectx: ComposeContext ->
                            Button("Tap") { -> s = S(x = 100) }.Compose(composectx)
                            ComposeResult.ok
                        }
                    }.Compose(composectx)
                }
            }

            @Composable
            @Suppress("UNCHECKED_CAST")
            override fun ComposeContent(composectx: ComposeContext) {
                val remembereds by rememberSaveable(stateSaver = composectx.stateSaver as Saver<skip.ui.State<S>, Any>) { mutableStateOf(_s) }
                _s = remembereds

                super.ComposeContent(composectx)
            }

            constructor(s: S = S()) {
                this._s = skip.ui.State(s.sref())
            }
        }
        """)
    }

    func testIfLetStateVariable() async throws {
        try await check(supportingSwift: baseSupportingSwift, swift: """
        import SwiftUI
        struct V: View {
            @State var x: String?

            var body: some View {
                if let x {
                    Text(x)
                } else {
                    Text("no")
                }
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class V: View {
            internal var x: String?
                get() = _x.wrappedValue
                set(newValue) {
                    _x.wrappedValue = newValue
                }
            internal var _x: skip.ui.State<String?> = skip.ui.State(null)

            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext ->
                    linvokeComposable l@{
                        val matchtarget_0 = x
                        if (matchtarget_0 != null) {
                            val x = matchtarget_0
                            return@l Text(x).Compose(composectx)
                        } else {
                            return@l Text("no").Compose(composectx)
                        }
                    }
                    ComposeResult.ok
                }
            }

            @Composable
            @Suppress("UNCHECKED_CAST")
            override fun ComposeContent(composectx: ComposeContext) {
                val rememberedx by rememberSaveable(stateSaver = composectx.stateSaver as Saver<skip.ui.State<String?>, Any>) { mutableStateOf(_x) }
                _x = rememberedx

                super.ComposeContent(composectx)
            }

            constructor(x: String? = null) {
                this._x = skip.ui.State(x)
            }
        }
        """)
    }

    func testKeyedEnvironmentVariable() async throws {
        try await check(supportingSwift: baseSupportingSwift + """
        extension Int {
            static let min = 0
        }
        """, swift: """
        import SwiftUI
        struct V: View {
            @Environment(\\.envvalue) var envvalue
            var body: some View {
                Text("Value: \\(envvalue)")
            }
            var isMin: Bool {
                return envvalue == .min
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class V: View {
            internal var envvalue: Int = Int(0)
            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext -> Text("Value: ${envvalue}").Compose(composectx) }
            }
        
            @Composable
            override fun ComposeContent(composectx: ComposeContext) {
                envvalue = EnvironmentValues.shared.envvalue

                super.ComposeContent(composectx)
            }
            internal val isMin: Boolean
                get() = envvalue == Int.min
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
            @Environment(EnvValue<String>.self) var envvalue
            var body: some View {
                Text("Value: \\(envvalue.x)")
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class V: View {
            internal lateinit var envvalue: EnvValue<String>
            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext -> Text("Value: ${envvalue.x}").Compose(composectx) }
            }

            @Composable
            override fun ComposeContent(composectx: ComposeContext) {
                envvalue = EnvironmentValues.shared.environmentObject(type = EnvValue::class)!!

                super.ComposeContent(composectx)
            }
        }
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        import SwiftUI
        struct V: View {
            @EnvironmentObject var envvalue: EnvValue<String>
            var body: some View {
                Text("Value: \\(envvalue.x)")
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class V: View {
            internal lateinit var envvalue: EnvValue<String>
            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext -> Text("Value: ${envvalue.x}").Compose(composectx) }
            }

            @Composable
            override fun ComposeContent(composectx: ComposeContext) {
                envvalue = EnvironmentValues.shared.environmentObject(type = EnvValue::class)!!

                super.ComposeContent(composectx)
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
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class V: View {
            internal lateinit var envvalue: V.EnvValue
            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext -> Text("Value: ${envvalue.x}").Compose(composectx) }
            }

            @Composable
            override fun ComposeContent(composectx: ComposeContext) {
                envvalue = EnvironmentValues.shared.environmentObject(type = V.EnvValue::class)!!

                super.ComposeContent(composectx)
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
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class V: View {
            internal var envvalue: EnvValue? = null
            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext ->
                    Text("Value: ${envvalue?.x ?: 1}").Compose(composectx)
                }
            }

            @Composable
            override fun ComposeContent(composectx: ComposeContext) {
                envvalue = EnvironmentValues.shared.environmentObject(type = EnvValue::class)

                super.ComposeContent(composectx)
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
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class V: View {
            internal var count: Int
                get() = _count.wrappedValue
                set(newValue) {
                    _count.wrappedValue = newValue
                }
            internal var _count: Binding<Int>
            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext ->
                    Button("Tap") { -> count += 1 }.Compose(composectx)
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
        public struct V: View {
            @State public var text = ""
            public var body: some View {
                TextField($text)
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        class V: View {
            var text: String
                get() = _text.wrappedValue
                set(newValue) {
                    _text.wrappedValue = newValue
                }
            var _text: skip.ui.State<String>
            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext -> TextField(Binding({ _text.wrappedValue }, { it -> _text.wrappedValue = it })).Compose(composectx) }
            }

            @Composable
            @Suppress("UNCHECKED_CAST")
            override fun ComposeContent(composectx: ComposeContext) {
                val rememberedtext by rememberSaveable(stateSaver = composectx.stateSaver as Saver<skip.ui.State<String>, Any>) { mutableStateOf(_text) }
                _text = rememberedtext

                super.ComposeContent(composectx)
            }

            constructor(text: String = "") {
                this._text = skip.ui.State(text)
            }

            companion object {
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
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class V: View {
            internal var text: String
                get() = _text.wrappedValue
                set(newValue) {
                    _text.wrappedValue = newValue
                }
            internal var _text: skip.ui.State<String>
            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext -> TextField(Binding({ this._text.wrappedValue }, { it -> this._text.wrappedValue = it })).Compose(composectx) }
            }

            @Composable
            @Suppress("UNCHECKED_CAST")
            override fun ComposeContent(composectx: ComposeContext) {
                val rememberedtext by rememberSaveable(stateSaver = composectx.stateSaver as Saver<skip.ui.State<String>, Any>) { mutableStateOf(_text) }
                _text = rememberedtext

                super.ComposeContent(composectx)
            }

            constructor(text: String = "") {
                this._text = skip.ui.State(text)
            }
        }
        """)
    }

    func testMutableStructPathBinding() async throws {
        try await check(supportingSwift: baseSupportingSwift + """
        struct Item {
          let id: UUID
          var s: String
        }
        struct BindingView: View {
            @Binding var text: String
            var body: some View {
            }
        }
        """, swift: """
        import SwiftUI
        struct V: View {
            @State var item = Item(id: UUID(), s: "New Item")
            var body: some View {
                VStack {
                    Text(item.s)
                    BindingView(text: $item.s)
                }
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class V: View {
            internal var item: Item
                get() = _item.wrappedValue.sref({ this.item = it })
                set(newValue) {
                    _item.wrappedValue = newValue.sref()
                }
            internal var _item: skip.ui.State<Item>
            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext ->
                    VStack { ->
                        ComposeBuilder { composectx: ComposeContext ->
                            Text(item.s).Compose(composectx)
                            BindingView(text = Binding({ _item.wrappedValue.s }, { it -> _item.wrappedValue.s = it })).Compose(composectx)
                            ComposeResult.ok
                        }
                    }.Compose(composectx)
                }
            }

            @Composable
            @Suppress("UNCHECKED_CAST")
            override fun ComposeContent(composectx: ComposeContext) {
                val remembereditem by rememberSaveable(stateSaver = composectx.stateSaver as Saver<skip.ui.State<Item>, Any>) { mutableStateOf(_item) }
                _item = remembereditem

                super.ComposeContent(composectx)
            }

            constructor(item: Item = Item(id = UUID(), s = "New Item")) {
                this._item = skip.ui.State(item.sref())
            }
        }
        """)
    }

    func testBindingToBinding() async throws {
        try await check(supportingSwift: baseSupportingSwift + """
        struct S {
            var text = ""
        }
        """, swift: """
        import SwiftUI
        struct V: View {
            @Binding var s: S
            var body: some View {
                TextField("", text: $s.text)
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class V: View {
            internal var s: S
                get() = _s.wrappedValue.sref({ this.s = it })
                set(newValue) {
                    _s.wrappedValue = newValue.sref()
                }
            internal var _s: Binding<S>
            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext -> TextField("", text = Binding({ _s.wrappedValue.text }, { it -> _s.wrappedValue.text = it })).Compose(composectx) }
            }

            constructor(s: Binding<S>) {
                this._s = s
            }
        }
        """)
    }

    func testBindable() async throws {
        try await check(supportingSwift: baseSupportingSwift, swift: """
        import SwiftUI

        @Observable class O {
            var string = ""
        }

        struct V: View {
            @Bindable var o: O
            var body: some View {
                TextField($o.string)
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.Stable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*

        @Stable
        internal open class O: Observable {
            internal open var string: String
                get() = _string.wrappedValue
                set(newValue) {
                    _string.wrappedValue = newValue
                }
            internal var _string: skip.model.Observed<String> = skip.model.Observed("")
        }

        internal class V: View {
            internal var o: O
                get() = _o.wrappedValue
                set(newValue) {
                    _o.wrappedValue = newValue
                }
            internal var _o: skip.ui.Bindable<O>
            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext -> TextField(Binding({ _o.wrappedValue.string }, { it -> _o.wrappedValue.string = it })).Compose(composectx) }
            }

            @Composable
            override fun ComposeContent(composectx: ComposeContext) {

                super.ComposeContent(composectx)
            }

            constructor(o: O) {
                this._o = skip.ui.Bindable(o)
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
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class V: View {
            internal var o: O
                get() = _o.wrappedValue
                set(newValue) {
                    _o.wrappedValue = newValue
                }
            internal var _o: skip.ui.Bindable<O>
            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext -> TextField(Binding({ this._o.wrappedValue.s.string }, { it -> this._o.wrappedValue.s.string = it })).Compose(composectx) }
            }

            @Composable
            override fun ComposeContent(composectx: ComposeContext) {

                super.ComposeContent(composectx)
            }

            constructor(o: O) {
                this._o = skip.ui.Bindable(o)
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
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class V: View {
            internal var o: O
                get() = _o.wrappedValue
                set(newValue) {
                    _o.wrappedValue = newValue
                }
            internal var _o: skip.ui.Bindable<O>
            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext -> TextField(Binding({ _o.wrappedValue.strings[0] }, { it -> _o.wrappedValue.strings[0] = it })).Compose(composectx) }
            }

            @Composable
            override fun ComposeContent(composectx: ComposeContext) {

                super.ComposeContent(composectx)
            }

            constructor(o: O) {
                this._o = skip.ui.Bindable(o)
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
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue
        import skip.lib.Array

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class V: View {
            internal val os: Array<O>
            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext ->
                    for (o in os.sref()) {
                        var o = o
                        val _o = Binding({ o }, { it -> o = it })
                        TextField(Binding({ _o.wrappedValue.string }, { it -> _o.wrappedValue.string = it })).Compose(composectx)
                    }
                    ComposeResult.ok
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
            @Bindable var o: O
            var i = 0

            var body: some View {
                Text("Hello")
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
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
            internal var o: O
                get() = _o.wrappedValue.sref({ this.o = it })
                set(newValue) {
                    _o.wrappedValue = newValue.sref()
                }
            internal var _o: skip.ui.Bindable<O>
            internal var i: Int
                set(newValue) {
                    willmutate()
                    field = newValue
                    didmutate()
                }

            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext -> Text("Hello").Compose(composectx) }
            }

            @Composable
            @Suppress("UNCHECKED_CAST")
            override fun ComposeContent(composectx: ComposeContext) {
                val rememberedcount by rememberSaveable(stateSaver = composectx.stateSaver as Saver<skip.ui.State<Int>, Any>) { mutableStateOf(_count) }
                _count = rememberedcount

                envvalue = EnvironmentValues.shared.envvalue

                super.ComposeContent(composectx)
            }

            constructor(count: Int = 0, text: Binding<String>, o: O, i: Int = 0) {
                this._count = skip.ui.State(count)
                this._text = text
                this._o = skip.ui.Bindable(o)
                this.i = i
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = V(count, _text, o, i)
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
            @Bindable var o: O
            var i = 0
        
            init(text: Binding<String>, o: O) {
                self._text = text
                self.o = o
            }
        
            var body: some View {
                Text("Hello")
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
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
            internal var o: O
                get() = _o.wrappedValue.sref({ this.o = it })
                set(newValue) {
                    _o.wrappedValue = newValue.sref()
                }
            internal var _o: skip.ui.Bindable<O>
            internal var i = 0
                set(newValue) {
                    willmutate()
                    field = newValue
                    didmutate()
                }

            internal constructor(text: Binding<String>, o: O) {
                this._text = text.sref()
                this._o = skip.ui.Bindable(o)
            }

            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext -> Text("Hello").Compose(composectx) }
            }

            @Composable
            @Suppress("UNCHECKED_CAST")
            override fun ComposeContent(composectx: ComposeContext) {
                val rememberedcount by rememberSaveable(stateSaver = composectx.stateSaver as Saver<skip.ui.State<Int>, Any>) { mutableStateOf(_count) }
                _count = rememberedcount

                envvalue = EnvironmentValues.shared.envvalue

                super.ComposeContent(composectx)
            }

            private constructor(copy: MutableStruct) {
                @Suppress("NAME_SHADOWING", "UNCHECKED_CAST") val copy = copy as V
                this._count = skip.ui.State(copy.count)
                this._text = copy._text
                this._o = skip.ui.Bindable(copy.o)
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
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class HStack<Content>: View where Content: View {
            internal val content: Content

            internal constructor(content: () -> Content) {
                this.content = content()
            }

            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext -> content.Compose(composectx) }
            }
        }
        """)
    }

    func testOmitPreviewProvider() async throws {
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
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class MyV: View {
            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext -> Text("Hello").Compose(composectx) }
            }
        }
        """)
    }

    func testOmitPreviewMacro() async throws {
        try await check(supportingSwift: baseSupportingSwift, swift: """
        import SwiftUI
        struct MyV: View {
            var body: some View {
                return Text("Hello")
            }
        }

        #Preview {
            MyV()
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class MyV: View {
            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext -> Text("Hello").Compose(composectx) }
            }
        }

        // #Preview omitted
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
            @Composable public override func ComposeContent(context: ComposeContext) {
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
                ComposeView { _ in
                    androidx.compose.Text("y")
                }
                ComposeView(content: { _ in androidx.compose.Text("y") })
                ComposeView { context in
                    if true { return }
                    if false {
                        androidx.compose.Text("y")
                    } else {
                        androidx.compose.Text("y")
                    }
                }
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class MyV: View {
            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext ->
                    Text("x").Compose(composectx)
                    ComposeView { it ->
                        androidx.compose.Column(modifier = it.modifier) { -> androidx.compose.Text("y") }
                    }.Compose(composectx)
                    ComposeView { _ -> androidx.compose.Text("y") }.Compose(composectx)
                    ComposeView(content = { _ -> androidx.compose.Text("y") }).Compose(composectx)
                    ComposeView l@{ context ->
                        if (true) {
                            return@l
                        }
                        if (false) {
                            androidx.compose.Text("y")
                        } else {
                            androidx.compose.Text("y")
                        }
                    }.Compose(composectx)
                    ComposeResult.ok
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
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class MyV: View {
            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext -> Color.red.Compose(composectx) }
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
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
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
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
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
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class MyV: View {
            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext ->
                    VStack().environment({ it -> EnvironmentValues.shared.setfont(it) }, Font.body).Compose(composectx)
                }
            }
        }
        """)
    }

    func testAppStorage() async throws {
        try await check(supportingSwift: baseSupportingSwift, swift: """
        import SwiftUI
        struct V: View {
            @AppStorage("appStorageKey") var appStorageProp = "appStorageDefaultValue"
            var body: some View {
                VStack {
                    Text("A: \\(appStorageProp)")
                    Button("Tap") {
                        appStorageProp += "X"
                    }
                }
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class V: View {
            internal var appStorageProp: String
                get() = _appStorageProp.wrappedValue
                set(newValue) {
                    _appStorageProp.wrappedValue = newValue
                }
            internal var _appStorageProp: skip.ui.AppStorage<String>
            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext ->
                    VStack { ->
                        ComposeBuilder { composectx: ComposeContext ->
                            Text("A: ${appStorageProp}").Compose(composectx)
                            Button("Tap") { -> appStorageProp += "X" }.Compose(composectx)
                            ComposeResult.ok
                        }
                    }.Compose(composectx)
                }
            }

            @Composable
            override fun ComposeContent(composectx: ComposeContext) {
                val rememberedappStorageProp by rememberSaveable(stateSaver = composectx.stateSaver as Saver<skip.ui.AppStorage<String>, Any>) { mutableStateOf(_appStorageProp) }
                _appStorageProp = rememberedappStorageProp

                super.ComposeContent(composectx)
            }

            constructor(appStorageProp: String = "appStorageDefaultValue") {
                this._appStorageProp = skip.ui.AppStorage(wrappedValue = appStorageProp, "appStorageKey")
            }
        }
        """)
    }

    func testAppStorageWithCustomStore() async throws {
        try await check(supportingSwift: baseSupportingSwift, swift: """
        import SwiftUI
        struct V: View {
            @AppStorage("storageKey", store: UserDefaults.standard) var doublePref: Double = 1.0

            var body: some View {
                VStack {
                    Text("A: \\(doublePref)")
                    Button("Tap") {
                        doublePref += 1.0
                    }
                }
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class V: View {
            internal var doublePref: Double
                get() = _doublePref.wrappedValue
                set(newValue) {
                    _doublePref.wrappedValue = newValue
                }
            internal var _doublePref: skip.ui.AppStorage<Double>

            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext ->
                    VStack { ->
                        ComposeBuilder { composectx: ComposeContext ->
                            Text("A: ${doublePref}").Compose(composectx)
                            Button("Tap") { -> doublePref += 1.0 }.Compose(composectx)
                            ComposeResult.ok
                        }
                    }.Compose(composectx)
                }
            }

            @Composable
            override fun ComposeContent(composectx: ComposeContext) {
                val remembereddoublePref by rememberSaveable(stateSaver = composectx.stateSaver as Saver<skip.ui.AppStorage<Double>, Any>) { mutableStateOf(_doublePref) }
                _doublePref = remembereddoublePref

                super.ComposeContent(composectx)
            }

            constructor(doublePref: Double = 1.0) {
                this._doublePref = skip.ui.AppStorage(wrappedValue = doublePref, "storageKey", store = UserDefaults.standard)
            }
        }
        """)
    }

    func testAppStorageWithRawRepresentable() async throws {
        try await check(supportingSwift: baseSupportingSwift + """
        enum E: String {
            case a, b
        }
        struct S: RawRepresentable {
            let rawValue: Int
            init(rawValue: Int) {
                self.rawValue = rawValue
            }
        }
        """, swift: """
        import SwiftUI
        struct V: View {
            @AppStorage("enumKey") var enumProp: E = .a
            @AppStorage("structKey") var structProp = S(rawValue: 1)
            var body: some View {
                Text("Hello")
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class V: View {
            internal var enumProp: E
                get() = _enumProp.wrappedValue
                set(newValue) {
                    _enumProp.wrappedValue = newValue
                }
            internal var _enumProp: skip.ui.AppStorage<E>
            internal var structProp: S
                get() = _structProp.wrappedValue
                set(newValue) {
                    _structProp.wrappedValue = newValue
                }
            internal var _structProp: skip.ui.AppStorage<S>
            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext -> Text("Hello").Compose(composectx) }
            }

            @Composable
            override fun ComposeContent(composectx: ComposeContext) {
                val rememberedenumProp by rememberSaveable(stateSaver = composectx.stateSaver as Saver<skip.ui.AppStorage<E>, Any>) { mutableStateOf(_enumProp) }
                _enumProp = rememberedenumProp

                val rememberedstructProp by rememberSaveable(stateSaver = composectx.stateSaver as Saver<skip.ui.AppStorage<S>, Any>) { mutableStateOf(_structProp) }
                _structProp = rememberedstructProp

                super.ComposeContent(composectx)
            }

            constructor(enumProp: E = E.a, structProp: S = S(rawValue = 1)) {
                this._enumProp = skip.ui.AppStorage(wrappedValue = enumProp, "enumKey", serializer = { it.rawValue }, deserializer = { if (it is String) E(rawValue = it) else null })
                this._structProp = skip.ui.AppStorage(wrappedValue = structProp, "structKey", serializer = { it.rawValue }, deserializer = { if (it is Int) S(rawValue = it) else null })
            }
        }
        """)
    }

    func testMainActorViewBody() async throws {
        let supportingSwift = """
        struct Task<Success, Failure> where Failure: Error {
            init(priority: TaskPriority? = nil, operation: @escaping () async throws -> Success) {
            }
            static func detached<T>(operation: () throws -> T) async -> T {
                fatalError()
            }
            static func sleep(nanoseconds: UInt64) async throws {
            }
        }

        extension View {
            public func task(priority: TaskPriority = .userInitiated, _ action: @escaping () async -> Void) -> some View {
                return self
            }
        }
        """

        try await check(supportingSwift: baseSupportingSwift + supportingSwift, swift: """
        import SwiftUI
        struct V: View {
            var body: some View {
                Task {
                    print("task")
                }
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class V: View {
            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext ->
                    Task(isMainActor = true) { -> print("task") }
                }
            }
        }
        """)

        try await check(supportingSwift: baseSupportingSwift + supportingSwift, swift: """
        import SwiftUI
        struct V: View {
            var body: some View {
                VStack {
                }
                .task {
                    print("task")
                }
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class V: View {
            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext ->
                    VStack { ->
                        ComposeBuilder { composectx: ComposeContext -> ComposeResult.ok }
                    }
                    .task { -> MainActor.run { print("task") } }.Compose(composectx)
                }
            }
        }
        """)
    }

    func testCustomViewModifier() async throws {
        try await check(supportingSwift: baseSupportingSwift, swift: """
        import SwiftUI
        struct CustomModifier: ViewModifier {
            @State var isPresented = false
            func body(content: Content) -> some View {
                content
                    .mod()
            }
        }
        struct PassthroughModifier: ViewModifier {
            func body(content: Content) -> some View {
                content
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class CustomModifier: ViewModifier {
            internal var isPresented: Boolean
                get() = _isPresented.wrappedValue
                set(newValue) {
                    _isPresented.wrappedValue = newValue
                }
            internal var _isPresented: skip.ui.State<Boolean>
            override fun body(content: View): View {
                return ComposeBuilder { composectx: ComposeContext ->
                    content
                        .mod().Compose(composectx)
                }
            }

            @Composable
            @Suppress("UNCHECKED_CAST")
            override fun Compose(content: View, composectx: ComposeContext) {
                val rememberedisPresented by rememberSaveable(stateSaver = composectx.stateSaver as Saver<skip.ui.State<Boolean>, Any>) { mutableStateOf(_isPresented) }
                _isPresented = rememberedisPresented

                super.Compose(content, composectx)
            }

            constructor(isPresented: Boolean = false) {
                this._isPresented = skip.ui.State(isPresented)
            }
        }
        internal class PassthroughModifier: ViewModifier {
            override fun body(content: View): View {
                return ComposeBuilder { composectx: ComposeContext -> content.Compose(composectx) }
            }
        }
        """)
    }

    func testViewBuilderContentVar() async throws {
        try await check(supportingSwift: baseSupportingSwift, swift: """
        import SwiftUI
        struct Stack<Content: View>: View {
            @ViewBuilder var content: Content

            var body: some View {
                VStack {
                    content
                    self.content
                }
            }
        }
        struct V: View {
            var body: some View {
                Stack {
                    Text("1")
                }
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class Stack<Content>: View, MutableStruct where Content: View {
            internal var content: Content
                get() = field.sref({ this.content = it })
                set(newValue) {
                    @Suppress("NAME_SHADOWING") val newValue = newValue.sref()
                    willmutate()
                    field = newValue
                    didmutate()
                }

            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext ->
                    VStack { ->
                        ComposeBuilder { composectx: ComposeContext ->
                            content.Compose(composectx)
                            this.content.Compose(composectx)
                            ComposeResult.ok
                        }
                    }.Compose(composectx)
                }
            }

            constructor(content: () -> Content) {
                this.content = content()
            }

            private constructor(copy: MutableStruct) {
                @Suppress("NAME_SHADOWING", "UNCHECKED_CAST") val copy = copy as Stack<Content>
                this.content = copy.content
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = Stack<Content>(this as MutableStruct)
        }
        internal class V: View {
            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext ->
                    Stack { ->
                        ComposeBuilder { composectx: ComposeContext ->
                            Text("1").Compose(composectx)
                            ComposeResult.ok
                        }
                    }.Compose(composectx)
                }
            }
        }
        """)
    }

    func testViewBuilderContentBlock() async throws {
        try await check(supportingSwift: baseSupportingSwift, swift: """
        import SwiftUI
        struct Stack<Content: View>: View {
            @ViewBuilder var content: () -> Content

            var body: some View {
                VStack {
                    content()
                    self.content()
                }
            }
        }
        struct V: View {
            var body: some View {
                Stack {
                    Text("1")
                    Text("2")
                }
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import skip.ui.*
        import skip.foundation.*
        import skip.model.*
        internal class Stack<Content>: View, MutableStruct where Content: View {
            internal var content: () -> Content
                set(newValue) {
                    willmutate()
                    field = newValue
                    didmutate()
                }

            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext ->
                    VStack { ->
                        ComposeBuilder { composectx: ComposeContext ->
                            content().Compose(composectx)
                            this.content().Compose(composectx)
                            ComposeResult.ok
                        }
                    }.Compose(composectx)
                }
            }

            constructor(content: () -> Content) {
                this.content = content
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = Stack<Content>(content)
        }
        internal class V: View {
            override fun body(): View {
                return ComposeBuilder { composectx: ComposeContext ->
                    Stack { ->
                        ComposeBuilder { composectx: ComposeContext ->
                            Text("1").Compose(composectx)
                            Text("2").Compose(composectx)
                            ComposeResult.ok
                        }
                    }.Compose(composectx)
                }
            }
        }
        """)
    }
}
