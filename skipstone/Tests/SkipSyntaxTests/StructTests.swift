import XCTest

final class StructTests: XCTestCase {
    func testImmutableStruct() async throws {
        try await check(swift: """
        struct A {
            let i: Int

            init(i: Int) {
                self.i = i
            }
        }
        """, kotlin: """
        internal class A {
            internal val i: Int

            internal constructor(i: Int) {
                this.i = i
            }
        }
        """)
    }

    func testMutableStruct() async throws {
        try await check(swift: """
        struct A {
            internal var i: Int

            init(i: Int) {
                self.i = i
            }
        }
        """, kotlin: """
        internal class A: MutableStruct {
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
                @Suppress("NAME_SHADOWING") val copy = copy as A
                this.i = copy.i
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = A(this as MutableStruct)
        }
        """)
    }

    func testSynthesizedStructEqualsHash() async throws {
        try await check(swift: """
        struct S: Equatable
            var i: Int
            var j: String {
                return 1
            }
        }
        """, kotlin: """
        internal class S: MutableStruct {
            internal var i: Int
                set(newValue) {
                    willmutate()
                    field = newValue
                    didmutate()
                }
            internal val j: String
                get() = 1

            constructor(i: Int) {
                this.i = i
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = S(i)

            override fun equals(other: Any?): Boolean {
                if (other !is S) return false
                return i == other.i
            }
        }
        """)

        try await check(swift: """
        struct S: Equatable
            let i: Int
            let j: String

            init(i: Int, j: String) {
                self.i = i
                self.j = j
            }
        }
        """, kotlin: """
        internal class S {
            internal val i: Int
            internal val j: String

            internal constructor(i: Int, j: String) {
                this.i = i
                this.j = j
            }

            override fun equals(other: Any?): Boolean {
                if (other !is S) return false
                return i == other.i && j == other.j
            }
        }
        """)

        try await check(swift: """
        struct S: Equatable
            let i: Int
            let j: String

            init(i: Int, j: String) {
                self.i = i
                self.j = j
            }

            static func == (lhs: S, rhs: S) -> Bool {
                return true
            }
        }
        """, kotlin: """
        internal class S {
            internal val i: Int
            internal val j: String

            internal constructor(i: Int, j: String) {
                this.i = i
                this.j = j
            }

            override fun equals(other: Any?): Boolean {
                if (other !is S) {
                    return false
                }
                val lhs = this
                val rhs = other
                return true
            }
        }
        """)

        try await check(swift: """
        struct S: Hashable
            var i: Int
        }
        """, kotlin: """
        internal class S: MutableStruct {
            internal var i: Int
                set(newValue) {
                    willmutate()
                    field = newValue
                    didmutate()
                }

            constructor(i: Int) {
                this.i = i
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = S(i)

            override fun equals(other: Any?): Boolean {
                if (other !is S) return false
                return i == other.i
            }

            override fun hashCode(): Int {
                var result = 1
                result = Hasher.combine(result, i)
                return result
            }
        }
        """)

        try await check(swift: """
        struct S: Hashable
            let i: Int
            let j: String

            init(i: Int, j: String) {
                self.i = i
                self.j = j
            }
        }
        """, kotlin: """
        internal class S {
            internal val i: Int
            internal val j: String

            internal constructor(i: Int, j: String) {
                this.i = i
                this.j = j
            }

            override fun equals(other: Any?): Boolean {
                if (other !is S) return false
                return i == other.i && j == other.j
            }

            override fun hashCode(): Int {
                var result = 1
                result = Hasher.combine(result, i)
                result = Hasher.combine(result, j)
                return result
            }
        }
        """)
    }

    func testRawRepresentableStruct() async throws {
        try await check(supportingSwift: """
        protocol RawRepresentable {
            associatedtype T
            var rawValue: T { get }
        }
        """, swift: """
        struct S: RawRepresentable {
            let rawValue: Int
        }
        """, kotlin: """
        internal class S: RawRepresentable<Int> {
            override val rawValue: Int

            constructor(rawValue: Int) {
                this.rawValue = rawValue
            }
        }
        """)
    }

    func testMutableGenericStructNoConstructor() async throws {
        try await check(swift: """
        struct Gen<T, U, V> {
            var name: String
        }
        """, kotlin: """
        internal class Gen<T, U, V>: MutableStruct {
            internal var name: String
                set(newValue) {
                    willmutate()
                    field = newValue
                    didmutate()
                }

            constructor(name: String) {
                this.name = name
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = Gen<T, U, V>(name)
        }
        """)
    }

    func testMutableGenericStructWithConstructor() async throws {
        try await check(swift: """
        struct Gen<T> {
            var name: String? = nil
            init() {
            }
        }
        """, kotlin: """
        internal class Gen<T>: MutableStruct {
            internal var name: String? = null
                set(newValue) {
                    willmutate()
                    field = newValue
                    didmutate()
                }
            internal constructor() {
            }

            private constructor(copy: MutableStruct) {
                @Suppress("NAME_SHADOWING") val copy = copy as Gen<T>
                this.name = copy.name
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = Gen<T>(this as MutableStruct)
        }
        """)
    }

    func testSref() async throws {
        let supportingSwift = """
        struct MS {
            var i = 0
        }
        struct IS {
            let i = 0
        }
        """

        try await check(supportingSwift: supportingSwift, swift: """
        struct S {
            let letms: MS
            let letis: IS
            var varms: MS
            var varis: IS

            func f() {
                var ms1 = letms // sref for own copy
                ms1.i += 1
                var ms2 = varms  // Property will sref, but sref again to erase onUpdate
                ms2.i += 1

                varms.i += 1 // Property will sref with proper onUpdate
            }
        }
        """, kotlin: """
        internal class S: MutableStruct {
            internal val letms: MS
            internal val letis: IS
            internal var varms: MS
                get() = field.sref({ this.varms = it })
                set(newValue) {
                    @Suppress("NAME_SHADOWING") val newValue = newValue.sref()
                    willmutate()
                    field = newValue
                    didmutate()
                }
            internal var varis: IS
                set(newValue) {
                    willmutate()
                    field = newValue
                    didmutate()
                }

            internal fun f() {
                var ms1 = letms.sref() // sref for own copy
                ms1.i += 1
                var ms2 = varms.sref() // Property will sref, but sref again to erase onUpdate
                ms2.i += 1

                varms.i += 1 // Property will sref with proper onUpdate
            }

            constructor(letms: MS, letis: IS, varms: MS, varis: IS) {
                this.letms = letms.sref()
                this.letis = letis
                this.varms = varms
                this.varis = varis
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = S(letms, letis, varms, varis)
        }
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        struct S {
            let letms: MS
            var varms: MS
            let letarr: [MS]
            var vararr: [MS]
            var letiarr: [IS] = []

            init(a: MS, b: [MS]) {
                letms = a // sref when assign to let
                varms = a // Property will sref itself
                self.letarr = b // sref when assign to let
                self.vararr = b // Property will sref itself
            }

            func f() {
                var a1 = letarr // sref for own copy
                a1.append(MS())
                var a2 = vararr // Property will sref, but sref again to erase onUpdate
                a2.append(MS())

                vararr.append(MS()) // Property will sref with proper onUpdate
            }

            func g() {
                var ms1 = letarr[0] // Array will sref, but sref again to erase onUpdate
                ms1.i += 1
                var ms2 = vararr[0] // Array will sref, but sref again to erase onUpdate
                ms2.i += 1
                var is1 = letiarr[0] // Not mutable so no sref

                vararr[0].i += 1 // Array will sref with proper onUpdate
            }
        }
        """, kotlin: """
        import skip.lib.Array
        
        internal class S: MutableStruct {
            internal val letms: MS
            internal var varms: MS
                get() = field.sref({ this.varms = it })
                set(newValue) {
                    @Suppress("NAME_SHADOWING") val newValue = newValue.sref()
                    willmutate()
                    field = newValue
                    didmutate()
                }
            internal val letarr: Array<MS>
            internal var vararr: Array<MS>
                get() = field.sref({ this.vararr = it })
                set(newValue) {
                    @Suppress("NAME_SHADOWING") val newValue = newValue.sref()
                    willmutate()
                    field = newValue
                    didmutate()
                }
            internal var letiarr: Array<IS> = arrayOf()
                get() = field.sref({ this.letiarr = it })
                set(newValue) {
                    @Suppress("NAME_SHADOWING") val newValue = newValue.sref()
                    willmutate()
                    field = newValue
                    didmutate()
                }

            internal constructor(a: MS, b: Array<MS>) {
                letms = a.sref() // sref when assign to let
                varms = a // Property will sref itself
                this.letarr = b.sref() // sref when assign to let
                this.vararr = b // Property will sref itself
            }

            internal fun f() {
                var a1 = letarr.sref() // sref for own copy
                a1.append(MS())
                var a2 = vararr.sref() // Property will sref, but sref again to erase onUpdate
                a2.append(MS())

                vararr.append(MS()) // Property will sref with proper onUpdate
            }

            internal fun g() {
                var ms1 = letarr[0].sref() // Array will sref, but sref again to erase onUpdate
                ms1.i += 1
                var ms2 = vararr[0].sref() // Array will sref, but sref again to erase onUpdate
                ms2.i += 1
                var is1 = letiarr[0] // Not mutable so no sref

                vararr[0].i += 1 // Array will sref with proper onUpdate
            }

            private constructor(copy: MutableStruct) {
                @Suppress("NAME_SHADOWING") val copy = copy as S
                this.letms = copy.letms
                this.varms = copy.varms
                this.letarr = copy.letarr
                this.vararr = copy.vararr
                this.letiarr = copy.letiarr
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = S(this as MutableStruct)
        }
        """)
    }

    func testNocopyDirective() async throws {
        try await check(swift: """
        // SKIP ATTRIBUTES: nocopy
        struct S {
            var x = 1
        }
        struct A {
            var s = S()
        }
        """, kotlin: """
        internal class S {
            internal var x: Int

            constructor(x: Int = 1) {
                this.x = x
            }
        }
        internal class A: MutableStruct {
            internal var s: S
                set(newValue) {
                    willmutate()
                    field = newValue
                    didmutate()
                }

            constructor(s: S = S()) {
                this.s = s
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = A(s)
        }
        """)

        //~~~
        try await check(swift: """
        // SKIP ATTRIBUTES: nocopy
        struct S {
            var x = 1

            init(p: Int) {
                var s = S()
                s.x = p
                self = s
            }
        }
        """, kotlin: """
        internal class S {
            internal var x = 1

            internal constructor(p: Int) {
                var s = S()
                s.x = p
                assignfrom(s)
            }

            private fun assignfrom(target: S) {
                this.x = target.x
            }
        }
        """)
    }
}
