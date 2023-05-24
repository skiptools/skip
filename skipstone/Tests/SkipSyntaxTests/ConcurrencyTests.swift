import XCTest

final class ConcurrencyTests: XCTestCase {
    func testTaskValueAsFunction() async throws {
        try await check(swift: """
        func f() -> Int async {
            let task: Task = Task { 10 }
            // SKIP NOWARN
            return await task.value
        }
        """, kotlin: """
        internal suspend fun f(): Int = Task.run l@{
            val task: Task = Task { 10 }
            return@l task.value()
        }
        """)
    }

    func testAwaitMainActorGlobal() async throws {
        try await check(swift: """
        @MainActor
        func a() {
        }
        func b() {
            a()
            b()
        }
        func f() async {
            await a()
            await b()
        }
        """, kotlin: """
        internal fun a() = Unit
        internal fun b() {
            a()
            b()
        }
        internal suspend fun f() = Task.run {
            MainActor.run { a() }
            b()
        }
        """)
    }

    func testAwaitMainActorConstructor() async throws {
        try await check(supportingSwift: """
        class C {
            @MainActor
            init() {
            }

            class Inner {
                @MainActor
                init() {
                }
            }
        }
        """, swift: """
        func f() {
            let c = C()
            let i = C.Inner()
        }
        func g() async {
            let c = await C()
            let i = await C.Inner()
        }
        """, kotlin: """
        internal fun f() {
            val c = C()
            val i = C.Inner()
        }
        internal suspend fun g() = Task.run {
            val c = MainActor.run { C() }
            val i = MainActor.run { C.Inner() }
        }
        """)
    }
}
