@testable import SkipSyntax
import XCTest

final class ConstructorTests: XCTestCase {
    func testBaseClassNoConstructor() async throws {
        try await check(swift: """
        class A {
        }
        
        class B: A {
        }
        
        class C: A {
            init() {
            }
        }
        
        class D: A {
            init() {
                super.init()
            }
        }
        """, kotlin: """
        internal open class A {
        }

        internal open class B: A() {
        }

        internal open class C: A {
            internal constructor(): super() {
            }
        }

        internal open class D: A {
            internal constructor(): super() {
            }
        }
        """)
    }
    
    func testBaseClassConstructorNoParameters() async throws {
        try await check(swift: """
        class A {
            init() {
            }
        }
        
        class B: A {
        }
        
        class C: A {
            override init() {
            }
        }
        
        class D: A {
            init(i: Int) {
            }
        }
        
        class E: A {
            init(i: Int) {
                super.init()
            }
        }
        """, kotlin: """
        internal open class A {
            internal constructor() {
            }
        }

        internal open class B: A {

            internal constructor(): super() {
            }
        }

        internal open class C: A {
            internal constructor(): super() {
            }
        }

        internal open class D: A {
            internal constructor(i: Int): super() {
            }
        }

        internal open class E: A {
            internal constructor(i: Int): super() {
            }
        }
        """)
    }
    
    func testBaseClassConstructorWithParameters() async throws {
        try await check(swift: """
        class A {
            let i: Int
            let s: String
        
            init(_ i: Int, s: String) {
                self.i = i
                self.s = s
            }
        
            convenience init(_ both: Int) {
                self.init(both, s: "\\(both)")
            }
        }
        
        class B: A {
        }
        
        class C: A {
            let d: Double
        
            init(d: Double, i: Int, s: String {
                self.d = d
                super.init(i, s: s)
            }
        }
        """, kotlin: """
        internal open class A {
            internal val i: Int
            internal val s: String
        
            internal constructor(i: Int, s: String) {
                this.i = i
                this.s = s
            }
        
            internal constructor(both: Int): this(both, s = "$both") {
            }
        }
        
        internal open class B: A {
        
            internal constructor(p_0: Int, s: String): super(p_0, s) {
            }
        
            internal constructor(p_0: Int): super(p_0) {
            }
        }
        
        internal open class C: A {
            internal val d: Double
        
            internal constructor(d: Double, i: Int, s: String): super(i, s = s) {
                this.d = d
            }
        }
        """)
    }
    
    func testStructMemberwiseConstructors() async throws {
        try await check(swift: """
        struct A {
        }
        
        struct B {
            var i: Int
        
            init(i: Int) {
                self.i = i
            }
        }
        
        struct C {
            let i = 100
            var s: String {
                return "100"
            }
        }
        
        struct D {
            let letVar = 100
            var computedVar: Int {
                return 100
            }
            var i = 100
            var s: String
        }
        
        struct E {
            var i = 100
            private var s: String
        }
        """, kotlin: """
        internal class A {
        }
        
        internal class B: MutableStruct {
            internal var i: Int
                set(newValue) {
                    willmutate()
                    field = newValue
                    didmutate()
                }
        
            internal constructor(i: Int) {
                this.i = i
            }
        
            private constructor(copy: MutableStruct) {
                val copy = copy as B
                this.i = copy.i
            }
        
            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct {
                return B(this as MutableStruct)
            }
        }
        
        internal class C {
            internal val i = 100
            internal val s: String
                get() {
                    return "100"
                }
        }
        
        internal class D: MutableStruct {
            internal val letVar = 100
            internal val computedVar: Int
                get() {
                    return 100
                }
            internal var i = 100
                set(newValue) {
                    willmutate()
                    field = newValue
                    didmutate()
                }
            internal var s: String
                set(newValue) {
                    willmutate()
                    field = newValue
                    didmutate()
                }
        
            constructor(i: Int = 100, s: String) {
                this.i = i
                this.s = s
            }
        
            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct {
                return D(i, s)
            }
        }
        
        internal class E: MutableStruct {
            internal var i = 100
                set(newValue) {
                    willmutate()
                    field = newValue
                    didmutate()
                }
            private var s: String
                set(newValue) {
                    willmutate()
                    field = newValue
                    didmutate()
                }
        
            constructor(i: Int = 100, s: String) {
                this.i = i
                this.s = s
            }
        
            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct {
                return E(i, s)
            }
        }
        """)
    }

    func testSetterSideEffects() {
        let base = ConstructorTestsSideEffectBase()
        XCTAssertFalse(base.didSet1)
        XCTAssertFalse(base.didSet2)

        let sub = ConstructorTestsSideEffectSub()
        XCTAssertTrue(sub.didSet1)
        XCTAssertFalse(sub.didSet2)
        XCTAssertFalse(sub.didSet3)
        XCTAssertFalse(sub.didSet4)
    }

    func testConstructorSkipsVariableWillDidSet() async throws {
        try await check(swift: """
        class A {
            var i = 1 {
                willSet {
                    print(newValue)
                }
            }
            var j = 2 {
                didSet {
                    print(j == 2)
                }
            }

            init(i: Int, j: Int) {
                self.i = i
                self.j = j
            }
        }
        """, kotlin: """
        internal open class A {
            internal var i = 1
                set(newValue) {
                    if (!isconstructing) {
                        print(newValue)
                    }
                    field = newValue
                }
            internal var j = 2
                set(newValue) {
                    val oldValue = field
                    field = newValue
                    if (!isconstructing) {
                        print(j == 2)
                    }
                }

            internal constructor(i: Int, j: Int) {
                isconstructing = true
                try {
                    this.i = i
                    this.j = j
                } finally {
                    isconstructing = false
                }
            }

            private var isconstructing = false
        }
        """)
    }
}

private class ConstructorTestsSideEffectBase {
    var i1: Int {
        didSet {
            didSet1 = true
        }
    }
    var i2 = 200 {
        didSet {
            didSet2 = true
        }
    }

    var didSet1 = false
    var didSet2 = false

    init() {
        self.i1 = 100
        self.i2 = 200
    }
}

private class ConstructorTestsSideEffectSub: ConstructorTestsSideEffectBase {
    var i3: Int {
        didSet {
            didSet3 = true
        }
    }
    var i4 = 400 {
        didSet {
            didSet4 = true
        }
    }

    var didSet3 = false
    var didSet4 = false

    override init() {
        self.i3 = 300
        super.init()
        self.i4 = 400
        self.i1 = 150
    }
}
