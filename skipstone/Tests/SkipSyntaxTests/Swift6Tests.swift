// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

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

    func testNoncopyableTypes() async throws {
        try await check(swift: """
        struct NonCopyable: ~Copyable {
            consuming func terminate() {
                print("Terminating")
            }
        }

        func borrow(_ user: borrowing NonCopyable) {
            print("\\(user)")
        }
        """, kotlin: """
        internal class NonCopyable {
            internal fun terminate(): Unit = print("Terminating")
        }

        internal fun borrow(user: NonCopyable): Unit = print("${user}")
        """)

        try await checkProducesMessage(swift: """
        struct NonCopyable: ~Copyable {
            consuming func terminate() {
                discard self
            }
        }
        """)
    }
}
