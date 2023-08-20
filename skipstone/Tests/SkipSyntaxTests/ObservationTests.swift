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
            lazy var g = 1

            static var s = 1
        }
        """, kotlin: """
        import androidx.compose.runtime.Stable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.setValue


        internal open class C: Observable {
            internal val a = 1
            internal open val b: Int
                get() = 1
            internal open var c: Int
                get() = 1
                set(newValue) {
                }
            internal open var d: Int
                get() = dstate
                set(newValue) {
                    dstate = newValue
                }
            internal var dstate: Int by mutableStateOf(1)
            internal open var e: Int
                get() = estate
                set(newValue) {
                    estate = newValue
                    print("didSet: ${e}")
                }
            internal var estate: Int by mutableStateOf(1)
            internal open var f = 1
            internal open var g: Int
                get() {
                    if (!ginitialized) {
                        gstate = 1
                        ginitialized = true
                    }
                    return gstate
                }
                set(newValue) {
                    gstate = newValue
                    ginitialized = true
                }
            internal var gstate: Int by mutableStateOf(Int(0))
            private var ginitialized = false

            companion object {

                internal var s = 1
            }
        }
        """)
    }

    func testMutableStructObservable() async throws {
        try await check(swift: """
        @Observable struct S {
            var a = 1
        }
        """, kotlin: """
        import androidx.compose.runtime.Stable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.setValue

        internal class S: MutableStruct, Observable {
            internal var a: Int
                get() = astate
                set(newValue) {
                    willmutate()
                    astate = newValue
                    didmutate()
                }
            internal var astate: Int by mutableStateOf(Int(0))

            constructor(a: Int = 1) {
                this.a = a
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = S(a)
        }
        """)
    }

    func testObservedLazyProperty() async throws {
        try await check(swift: """
        @Observable class C {
            lazy var a: Int = { 1 }()
        }
        """, kotlin: """
        import androidx.compose.runtime.Stable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.setValue

        internal open class C: Observable {
            internal open var a: Int
                get() {
                    if (!ainitialized) {
                        astate = { 1 }()
                        ainitialized = true
                    }
                    return astate
                }
                set(newValue) {
                    astate = newValue
                    ainitialized = true
                }
            internal var astate: Int by mutableStateOf(Int(0))
            private var ainitialized = false
        }
        """)

        try await check(swift: """
        @Observable struct S {
            lazy var a: Int = { 1 }()
        }
        """, kotlin: """
        import androidx.compose.runtime.Stable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.setValue

        internal class S: MutableStruct, Observable {
            internal var a: Int
                get() {
                    val isinitialized = ainitialized
                    if (!isinitialized) willmutate()
                    try {
                        if (!ainitialized) {
                            astate = { 1 }()
                            ainitialized = true
                        }
                        return astate
                    } finally {
                        if (!isinitialized) didmutate()
                    }
                }
                set(newValue) {
                    willmutate()
                    astate = newValue
                    ainitialized = true
                    didmutate()
                }
            internal var astate: Int by mutableStateOf(Int(0))
            private var ainitialized = false

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = S()
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
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.setValue
        import skip.lib.Array

        internal open class C: Observable {
            internal open var a: Array<A>
                get() = astate.sref({ this.a = it })
                set(newValue) {
                    astate = newValue.sref()
                }
            internal var astate: Array<A> by mutableStateOf(arrayOf())
        }
        """)

        try await check(supportingSwift: """
        struct A {
            var x = 1
        }
        """, swift: """
        @Observable struct S {
            var a: [A] = []
        }
        """, kotlin: """
        import androidx.compose.runtime.Stable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.setValue
        import skip.lib.Array

        internal class S: MutableStruct, Observable {
            internal var a: Array<A>
                get() = astate!!.sref({ this.a = it })
                set(newValue) {
                    @Suppress("NAME_SHADOWING") val newValue = newValue.sref()
                    willmutate()
                    astate = newValue
                    didmutate()
                }
            internal var astate: Array<A>? by mutableStateOf(null)

            constructor(a: Array<A> = arrayOf()) {
                this.a = a
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = S(a)
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
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.setValue

        
        internal open class C1: ObservableObject {
            internal open var a = 1
            internal open var b: Int
                get() = bstate
                set(newValue) {
                    bstate = newValue
                }
            internal var bstate: Int by mutableStateOf(1)
        }
        internal open class C2: C1() {
            internal open var c: Int
                get() = cstate
                set(newValue) {
                    cstate = newValue
                }
            internal var cstate: Int by mutableStateOf(1)
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
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.setValue

        internal open class C: ObservableObject {
            internal open var a: S
                get() = astate!!.sref({ this.a = it })
                set(newValue) {
                    astate = newValue.sref()
                }
            internal var astate: S? by mutableStateOf(null)
            internal open var b: S?
                get() = bstate.sref({ this.b = it })
                set(newValue) {
                    bstate = newValue.sref()
                }
            internal var bstate: S? by mutableStateOf(null)
            internal constructor(a: S) {
                this.a = a
            }
        }
        """)
    }
}
