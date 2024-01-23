import XCTest

final class ObservationTests: XCTestCase {
    func testDefaultObservableProperties() async throws {
        try await check(swift: """
        import Observation

        @Observable class C {
            let a = 1
            var b: Int {
                return 1
            }
            var c: Int {
                get {
                    return 1
                }
                set {
                }
            }
            var d = 1
            var e = 1 {
                didSet {
                    print("didSet: \\(e)")
                }
            }
            @ObservationIgnored var f = 1

            static var s = 1
        }
        """, kotlin: """
        import androidx.compose.runtime.Stable
        import androidx.compose.runtime.mutableStateOf

        import skip.model.*

        @Stable
        internal open class C: Observable {
            internal val a = 1
            internal open val b: Int
                get() = 1
            internal open var c: Int
                get() = 1
                set(newValue) {
                }
            internal open var d: Int
                get() = _d.wrappedValue
                set(newValue) {
                    _d.wrappedValue = newValue
                }
            internal var _d: skip.model.Observed<Int> = skip.model.Observed(1)
            internal open var e: Int
                get() = _e.wrappedValue
                set(newValue) {
                    _e.wrappedValue = newValue
                    print("didSet: ${e}")
                }
            internal var _e: skip.model.Observed<Int> = skip.model.Observed(1)
            internal open var f = 1

            override fun trackstate() {
                _d.track()
                _e.track()
            }

            open class CompanionClass {

                internal var s = 1
            }
            companion object: CompanionClass()
        }
        """)
    }

    func testObservedArray() async throws {
        try await check(supportingSwift: """
        struct A {
            var x = 1
        }
        """, swift: """
        @Observable class C {
            var a: [A] = []
        }
        """, kotlin: """
        import androidx.compose.runtime.Stable
        import androidx.compose.runtime.mutableStateOf
        import skip.lib.Array

        @Stable
        internal open class C: Observable {
            internal open var a: Array<A>
                get() = _a.wrappedValue.sref({ this.a = it })
                set(newValue) {
                    _a.wrappedValue = newValue.sref()
                }
            internal var _a: skip.model.Observed<Array<A>> = skip.model.Observed(arrayOf())

            override fun trackstate(): Unit = _a.track()
        }
        """)
    }

    func testObservableObject() async throws {
        try await check(swift: """
        import Combine

        class C1: ObservableObject {
            var a = 1
            @Published var b = 1
        }
        class C2: C1 {
            @Published var c = 1
        }
        """, kotlin: """
        import androidx.compose.runtime.Stable
        import androidx.compose.runtime.mutableStateOf

        import skip.model.*

        @Stable
        internal open class C1: ObservableObject {
            override val objectWillChange = ObservableObjectPublisher()
            internal open var a = 1
            internal open var b: Int
                get() = _b.wrappedValue
                set(newValue) {
                    objectWillChange.send()
                    _b.wrappedValue = newValue
                }
            internal var _b: skip.model.Published<Int> = skip.model.Published(1)

            override fun trackstate(): Unit = _b.track()
        }
        @Stable
        internal open class C2: C1() {
            internal open var c: Int
                get() = _c.wrappedValue
                set(newValue) {
                    objectWillChange.send()
                    _c.wrappedValue = newValue
                }
            internal var _c: skip.model.Published<Int> = skip.model.Published(1)

            override fun trackstate() {
                super.trackstate()
                _c.track()
            }
        }
        """)
    }

    func testPublishedWithoutInitialValue() async throws {
        try await check(supportingSwift: """
        struct S {
            var x = 1
        }
        """, swift: """
        class C: ObservableObject {
            @Published var a: S
            @Published var b: S?
            init(a: S) {
                self.a = a
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Stable
        import androidx.compose.runtime.mutableStateOf

        @Stable
        internal open class C: ObservableObject {
            override val objectWillChange = ObservableObjectPublisher()
            internal open var a: S
                get() = _a.wrappedValue.sref({ this.a = it })
                set(newValue) {
                    objectWillChange.send()
                    _a.wrappedValue = newValue.sref()
                }
            internal var _a: skip.model.Published<S>
            internal open var b: S?
                get() = _b.wrappedValue.sref({ this.b = it })
                set(newValue) {
                    objectWillChange.send()
                    _b.wrappedValue = newValue.sref()
                }
            internal var _b: skip.model.Published<S?> = skip.model.Published(null)
            internal constructor(a: S) {
                this._a = skip.model.Published(a)
            }

            override fun trackstate() {
                _a.track()
                _b.track()
            }
        }
        """)
    }

    func testPublishedWithWillSet() async throws {
        try await check(swift: """
        class C: ObservableObject {
            @Published var i = 0 {
                willSet {
                    print("Setting to \\(newValue)")
                }
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Stable
        import androidx.compose.runtime.mutableStateOf

        @Stable
        internal open class C: ObservableObject {
            override val objectWillChange = ObservableObjectPublisher()
            internal open var i: Int
                get() = _i.wrappedValue
                set(newValue) {
                    print("Setting to ${newValue}")
                    objectWillChange.send()
                    _i.wrappedValue = newValue
                }
            internal var _i: skip.model.Published<Int> = skip.model.Published(0)

            override fun trackstate(): Unit = _i.track()
        }
        """)
    }

    func testCustomObjectWillChange() async throws {
        try await check(supportingSwift: """
        class ObservableObjectPublisher {
        }
        """, swift: """
        import Combine
        class C: ObservableObject {
            let objectWillChange = ObservableObjectPublisher()
            @Published var i = 0
            func f() {
                objectWillChange.send()
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Stable
        import androidx.compose.runtime.mutableStateOf

        import skip.model.*
        @Stable
        internal open class C: ObservableObject {
            override val objectWillChange = ObservableObjectPublisher()
            internal open var i: Int
                get() = _i.wrappedValue
                set(newValue) {
                    objectWillChange.send()
                    _i.wrappedValue = newValue
                }
            internal var _i: skip.model.Published<Int> = skip.model.Published(0)
            internal open fun f(): Unit = objectWillChange.send()

            override fun trackstate(): Unit = _i.track()
        }
        """)
    }

    func testPropertyPublisher() async throws {
        try await check(swift: """
        class O: ObservableObject {
            @Published var i = 0
        }
        class C {
            let o: O
            var value = 0
            let token1: AnyCancellable
            let token2: AnyCancellable

            init(o: O) {
                self.o = o
                token1 = o.$i.sink { i in
                    print("i = \\(i)")
                }
                token2 = o.$i.assign(to: \\.value, on: self)
            }
        }
        """, kotlin: """
        import androidx.compose.runtime.Stable
        import androidx.compose.runtime.mutableStateOf

        @Stable
        internal open class O: ObservableObject {
            override val objectWillChange = ObservableObjectPublisher()
            internal open var i: Int
                get() = _i.wrappedValue
                set(newValue) {
                    objectWillChange.send()
                    _i.wrappedValue = newValue
                }
            internal var _i: skip.model.Published<Int> = skip.model.Published(0)

            override fun trackstate(): Unit = _i.track()
        }
        internal open class C {
            internal val o: O
            internal open var value = 0
            internal val token1: AnyCancellable
            internal val token2: AnyCancellable

            internal constructor(o: O) {
                this.o = o
                token1 = o._i.projectedValue.sink { i -> print("i = ${i}") }
                token2 = o._i.projectedValue.assign(to = { it, it_1 -> it.value = it_1 }, on = this)
            }
        }
        """)
    }
}
