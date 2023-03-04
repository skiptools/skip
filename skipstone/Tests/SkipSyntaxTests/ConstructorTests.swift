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
        
            companion object {
            }
        }
        
        internal open class B: A() {
        
            companion object {
            }
        }
        
        internal open class C: A() {
            internal constructor() {
            }
        
            companion object {
            }
        }
        
        internal open class D: A {
            internal constructor(): super() {
            }
        
            companion object {
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
        
            companion object {
            }
        }
        
        internal open class B: A {
        
            internal constructor(): super() {
            }
        
            companion object {
            }
        }
        
        internal open class C: A() {
            internal constructor() {
            }
        
            companion object {
            }
        }
        
        internal open class D: A() {
            internal constructor(i: Int) {
            }
        
            companion object {
            }
        }
        
        internal open class E: A {
            internal constructor(i: Int): super() {
            }
        
            companion object {
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
        
            companion object {
            }
        }
        
        internal open class B: A {
        
            internal constructor(p_0: Int, s: String): super(p_0, s) {
            }
        
            internal constructor(p_0: Int): super(p_0) {
            }
        
            companion object {
            }
        }
        
        internal open class C: A {
            internal val d: Double
        
            internal constructor(d: Double, i: Int, s: String): super(i, s = s) {
                this.d = d
            }
        
            companion object {
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

            companion object {
            }
        }
        
        internal class B: MutableStruct {
            internal var i: Int
        
            internal constructor(i: Int) {
                this.i = i
            }
        
            private constructor(copy: MutableStruct) {
                val copy = copy as B
                this.i = copy.i
            }
        
            override var supdate: ((Any) -> Unit)? = null
        
            override fun scopy(): MutableStruct {
                return B(this as MutableStruct)
            }
        
            companion object {
            }
        }
        
        internal class C {
            internal val i = 100
            internal val s: String
                get() {
                    return "100"
                }
        
            companion object {
            }
        }
        
        internal class D: MutableStruct {
            internal val letVar = 100
            internal val computedVar: Int
                get() {
                    return 100
                }
            internal var i = 100
            internal var s: String
        
            constructor(i: Int = 100, s: String) {
                this.i = i
                this.s = s
            }
        
            override var supdate: ((Any) -> Unit)? = null
        
            override fun scopy(): MutableStruct {
                return D(i, s)
            }
        
            companion object {
            }
        }
        
        internal class E: MutableStruct {
            internal var i = 100
            private var s: String
        
            constructor(i: Int = 100, s: String) {
                this.i = i
                this.s = s
            }
        
            override var supdate: ((Any) -> Unit)? = null
        
            override fun scopy(): MutableStruct {
                return E(i, s)
            }
        
            companion object {
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
