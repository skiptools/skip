import XCTest

final class Swift6Tests: XCTestCase {
    func testSendingKeywordIgnored() async throws {
        try await check(swift: """
        func f(p: sending Int) {
        }
        func g() -> sending Int {
            return 0
        }
        """, kotlin: """
        internal fun f(p: Int) = Unit
        internal fun g(): Int = 0
        """)
    }

    func testMainActorOnGlobalsAndStatics() async throws {
        try await check(swift: """
        struct S {
            @MainActor
            static var staticMember = true
        }

        @MainActor
        var global = 1

        @MainActor
        func f() {
            let s = S.staticMember
            S.staticMember = false
            let g = global
            global = 100
        }
        func g() async {
            let s = await S.staticMember
            let g = await global
        }
        """, kotlin: """
        internal class S {

            companion object {
                internal var staticMember = true
            }
        }

        internal var global = 1

        internal fun f() {
            val s = S.staticMember
            S.staticMember = false
            val g = global
            global = 100
        }
        internal suspend fun g(): Unit = Async.run {
            val s = MainActor.run { S.staticMember }
            val g = MainActor.run { global }
        }
        """)
    }

    func testImportAccessModifiersIgnored() async throws {
        try await check(swift: """
        private import MyPackage1
        internal import MyPackage2
        import MyPackage3

        struct S {
        }
        """, kotlin: """
        import my.package1.*
        import my.package2.*
        import my.package3.*

        internal class S {
        }
        """)
    }
}


struct XWing {
    @MainActor
    static var sFoilsAttackPosition = true
}

struct WarpDrive {
    static let maximumSpeed = 9.975
}

@MainActor
var idNumber = 24601

@MainActor
func f() {
    let s = XWing.sFoilsAttackPosition
    XWing.sFoilsAttackPosition = false
    idNumber = 100
}

func g() async {
    let s = await XWing.sFoilsAttackPosition
    let i = await idNumber
}
