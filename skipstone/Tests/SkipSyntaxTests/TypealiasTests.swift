@testable import SkipSyntax
import XCTest

final class TypealiasTests: XCTestCase {
    func testTypealiasSubstitution() async throws {
        try await check(swift: """
        typealias AA = a.b.C

        class Sub: AA {
            let a: AA = AA()
            let b: B = AA.f()

            func subf(p: AA) -> [AA]? {
                return nil
            }
        }
        """, kotlin: """
        internal open class Sub: a.b.C() {
            internal val a: a.b.C = a.b.C()
                get() = field.sref()
            internal val b: B = a.b.C.f()
                get() = field.sref()

            internal open fun subf(p: a.b.C): Array<a.b.C>? = null
        }
        """)
    }

    func testMemberTypealias() async throws {
        try await check(swift: """
        class A {
            static let a = A()
        }
        class B {
            typealias Member = A
            let b = Member.a
            let b2: Member = .a
        }
        class C {
            let c = B.Member.a
            func f(m: B.Member) -> B.Member {
                return .a
            }
        }
        """, kotlin: """
        internal open class A {

            companion object {
                internal val a = A()
            }
        }
        internal open class B {
            internal val b = A.a
            internal val b2: A = A.a
        }
        internal open class C {
            internal val c = A.a
            internal open fun f(m: A): A = A.a
        }
        """)
    }

    func testTypealiasWithGenerics() async throws {
        try await check(supportingSwift: """
        extension Int {
            static var max = 1
        }
        """, swift: """
        typealias AA = Array<Int>
        func f(a: AA) -> Bool {
            return a[0] == .max
        }
        """, kotlin: """
        internal fun f(a: Array<Int>): Boolean = a[0] == Int.max
        """)
    }

    func testRecursivelyNamedUnknownTypealias() async throws {
        try await check(swift: """
        public typealias MessageDigest = java.security.MessageDigest
        public protocol NamedHashFunction {
            var digest: MessageDigest { get }
        }
        """, kotlin: """
        interface NamedHashFunction {
            val digest: java.security.MessageDigest
        }
        """)
    }

    func testTypealiasParameter() async throws {
        try await check(supportingSwift: """
        protocol Collection {
            associatedtype Element
            // SKIP NOWARN
            subscript(i: Int) -> Element
            func firstIndex(of: Element) -> Int?
        }
        struct S: Collection {
            typealias Element = Character
            typealias Index = Int
        }
        """, swift: """
        func f(s: S) {
            let i: S.Index = s.firstIndex(of: "a")!
            let b = s[i] == "a"
        }
        """, kotlin: """
        internal fun f(s: S) {
            val i: Int = s.firstIndex(of = 'a')!!
            val b = s[i] == 'a'
        }
        """)
    }

    func testConstrainedGenericTypealias() async throws {
        try await checkProducesMessage(swift: """
        private typealias EArray<E> = Array<E> where E: Comparable
        """)
    }

    func testTypealiasToSelf() async throws {
        // Note: this is invalid Swift, so it doesn't really matter that the output is also invalid
        try await check(swift: """
        typealias A = A

        class A {
        }

        class B : A {
        }
        """, kotlin: """
        internal open class A {
        }

        internal open class B: A {

            internal constructor(): super() {
            }

            internal constructor(): super() {
            }

            internal constructor(): super() {
            }

            internal constructor(): super() {
            }

            internal constructor(): super() {
            }

            internal constructor(): super() {
            }

            internal constructor(): super() {
            }

            internal constructor(): super() {
            }

            internal constructor(): super() {
            }

            internal constructor(): super() {
            }
        }
        """)
    }
}
