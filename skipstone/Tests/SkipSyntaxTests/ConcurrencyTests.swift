import Foundation
@testable import SkipSyntax
import XCTest

final class ConcurrencyTests: XCTestCase {
    private func setUpContext(swift: String) async throws -> CodebaseInfo.Context {
        let srcFile = try tmpFile(named: "Source.swift", contents: swift)
        let source = Source(file: Source.FilePath(path: srcFile.path), content: swift)
        let syntaxTree = SyntaxTree(source: source)

        let codebaseInfo = CodebaseInfo()
        codebaseInfo.gather(from: syntaxTree)
        codebaseInfo.prepareForUse()
        return codebaseInfo.context(importedModuleNames: [], sourceFile: source.file)
    }

    func testNonisolated() async throws {
        let context = try await setUpContext(swift: """
        @MainActor class C {
            nonisolated func f() {
            }
        }
        """)
        let infos = context.global.lookup(name: "f")
        XCTAssertEqual(infos.count, 1)
        XCTAssertTrue(infos[0] is CodebaseInfo.FunctionInfo)
        XCTAssertTrue(infos[0].modifiers.isNonisolated)
    }

    func testMainActorSubclassInference() async throws {
        let context = try await setUpContext(swift: """
        class A {
        }
        @MainActor class B: A {
        }
        class C: B {
        }
        class D: C {
        }
        class E: A {
        }
        """)
        let a = context.primaryTypeInfo(forNamed: .named("A", []))
        XCTAssertTrue(a?.apiFlags?.contains(.mainActor) == false)
        let b = context.primaryTypeInfo(forNamed: .named("B", []))
        XCTAssertTrue(b?.apiFlags?.contains(.mainActor) == true)
        let c = context.primaryTypeInfo(forNamed: .named("C", []))
        XCTAssertTrue(c?.apiFlags?.contains(.mainActor) == true)
        let d = context.primaryTypeInfo(forNamed: .named("D", []))
        XCTAssertTrue(d?.apiFlags?.contains(.mainActor) == true)
        let e = context.primaryTypeInfo(forNamed: .named("E", []))
        XCTAssertTrue(e?.apiFlags?.contains(.mainActor) == false)
    }

    func testMainActorProtocolInference() async throws {
        let context = try await setUpContext(swift: """
        @MainActor protocol PA {
        }
        protocol PB: PA {
        }
        class A: PB {
        }
        class B: A {
        }
        class C {
        }
        extension C: PA {
        }
        """)
        let pa = context.primaryTypeInfo(forNamed: .named("PA", []))
        XCTAssertTrue(pa?.apiFlags?.contains(.mainActor) == true)
        let pb = context.primaryTypeInfo(forNamed: .named("PB", []))
        XCTAssertTrue(pb?.apiFlags?.contains(.mainActor) == true)
        let a = context.primaryTypeInfo(forNamed: .named("A", []))
        XCTAssertTrue(a?.apiFlags?.contains(.mainActor) == true)
        let b = context.primaryTypeInfo(forNamed: .named("B", []))
        XCTAssertTrue(b?.apiFlags?.contains(.mainActor) == true)
        let c = context.primaryTypeInfo(forNamed: .named("C", []))
        XCTAssertTrue(c?.apiFlags?.contains(.mainActor) == false)
    }

    func testMainActorOverrideMemberInference() async throws {
        let context = try await setUpContext(swift: """
        class A {
            @MainActor var v: Int { 1 }
            @MainActor func f() {}
        }
        class B: A {
        }
        class C: B {
            override var v: Int { 2 }
            override func f() {}
        }
        class D: C {
        }
        class E: A {
        }
        """)
        let a = context.primaryTypeInfo(forNamed: .named("A", []))
        XCTAssertTrue(a?.apiFlags?.contains(.mainActor) == false)
        let v = a?.variables.first
        XCTAssertTrue(v?.apiFlags?.contains(.mainActor) == true)
        let f = a?.functions.first
        XCTAssertTrue(f?.apiFlags?.contains(.mainActor) == true)

        let c = context.primaryTypeInfo(forNamed: .named("C", []))
        XCTAssertTrue(c?.apiFlags?.contains(.mainActor) == false)
        let v1 = c?.variables.first
        XCTAssertTrue(v1?.apiFlags?.contains(.mainActor) == true)
        let f1 = c?.functions.first
        XCTAssertTrue(f1?.apiFlags?.contains(.mainActor) == true)
    }

    func testMainActorProtocolMemberInference() async throws {
        let context = try await setUpContext(swift: """
        protocol P {
            @MainActor var v: Int
            @MainActor func f()
        }
        protocol P2: P {
        }
        class A: P2 {
            var v: Int { 1 }
            func f() {}
        }
        class B {
        }
        extension B: P {
            var v: Int { 1 }
            func f() {}
        }
        """)
        let a = context.primaryTypeInfo(forNamed: .named("A", []))
        XCTAssertTrue(a?.apiFlags?.contains(.mainActor) == false)
        let v = a?.variables.first
        XCTAssertTrue(v?.apiFlags?.contains(.mainActor) == true)
        let f = a?.functions.first
        XCTAssertTrue(f?.apiFlags?.contains(.mainActor) == true)

        let b = context.typeInfos(forNamed: .named("B", [])).first { $0.declarationType == .extensionDeclaration }
        XCTAssertTrue(b?.apiFlags?.contains(.mainActor) == false)
        let v1 = b?.variables.first
        XCTAssertTrue(v1?.apiFlags?.contains(.mainActor) == true)
        let f1 = b?.functions.first
        XCTAssertTrue(f1?.apiFlags?.contains(.mainActor) == true)
    }

    func testTaskValueAsFunction() async throws {
        let supportingSwift = """
        struct Task<Success, Failure> where Failure: Error {
            var value: Success {
                get async throws { fatalError() }
            }

            init(priority: TaskPriority? = nil, operation: @escaping () async throws -> Success) {
            }

            // SKIP NOWARN
            static func detached(priority: TaskPriority? = nil, operation: @escaping () async -> Success) -> Task<Success, Failure> {
                fatalError()
            }
        }
        """

        try await check(supportingSwift: supportingSwift, swift: """
        func f() async -> Int {
            let task = Task { 10 }
            return await task.value
        }
        """, kotlin: """
        internal suspend fun f(): Int = Task.run l@{
            val task = Task { 10 }
            return@l task.value()
        }
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        func f() async -> Int {
            await Task { 10 }.value
        }
        """, kotlin: """
        internal suspend fun f(): Int = Task.run l@{
            return@l Task { 10 }.value()
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
        let supportingSwift = """
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
        """

        try await check(supportingSwift: supportingSwift, swift: """
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

        try await check(supportingSwift: supportingSwift, swift: """
        func a(c: C, i: C.Inner) -> Int {
            return 1
        }
        @MainActor func b(c: C, i: C.Inner) -> Int {
            return 1
        }
        func f() async {
            let sum = await a(c: C(), i: C.Inner()) + b(c: C(), i: C.Inner())
        }
        """, kotlin: """
        internal fun a(c: C, i: C.Inner): Int = 1
        internal fun b(c: C, i: C.Inner): Int = 1
        internal suspend fun f() = Task.run {
            val sum = a(c = MainActor.run { C() }, i = MainActor.run { C.Inner() }) + MainActor.run { b(c = C(), i = C.Inner()) }
        }
        """)
    }

    func testAwaitMainActorStatics() async throws {
        let supportingSwift = """
        class C {
            static let x = 0
            @MainActor
            static let i = 1
            @MainActor
            static func f() -> Int {
                return 1
            }

            class Inner {
                @MainActor
                static let j = 1
            }
        }
        """

        try await check(supportingSwift: supportingSwift, swift: """
        func f() {
            let x = C.x
            let i = C.i
            let f = C.f()
            let j = C.Inner.j
        }
        func g() async {
            let x = C.x
            let i = await C.i
            let f = await C.f()
            let j = await C.Inner.j
        }
        """, kotlin: """
        internal fun f() {
            val x = C.x
            val i = C.i
            val f = C.f()
            val j = C.Inner.j
        }
        internal suspend fun g() = Task.run {
            val x = C.x
            val i = MainActor.run { C.i }
            val f = MainActor.run { C.f() }
            val j = MainActor.run { C.Inner.j }
        }
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        func f(i: Int) async {
            await f(i: C.i)
            await f(i: C.Inner.j + C.f() - C.i)
        }
        """, kotlin: """
        internal suspend fun f(i: Int) = Task.run {
            f(i = MainActor.run { C.i })
            f(i = MainActor.run { C.Inner.j } + MainActor.run { C.f() } - MainActor.run { C.i })
        }
        """)
    }

    func testAwaitMainActorMemberVariable() async throws {
        let supportingSwift = """
        class C {
            @MainActor
            var i = 1
            @MainActor
            var mainC = C()
            var c = C()
        }
        """

        try await check(supportingSwift: supportingSwift, swift: """
        func f(c: C) async {
            let i = await C().i
            let mainCi = await c.mainC.i
            let ci = await c.c.i
            let mainCci = await c.mainC.c.i
        }
        """, kotlin: """
        internal suspend fun f(c: C) = Task.run {
            val i = C().mainactor { it.i }
            val mainCi = c.mainactor { it.mainC }.mainactor { it.i }
            val ci = c.c.mainactor { it.i }
            val mainCci = c.mainactor { it.mainC }.c.mainactor { it.i }
        }
        """)
    }

    func testAwaitMainActorMemberFunction() async throws {
        let supportingSwift = """
        class C {
            @MainActor
            func i() -> Int {
                return 1
            }
            @MainActor
            func j(i: Int) -> Int {
                return i
            }
            @MainActor
            func mainC() -> C {
                return C()
            }
            func c() -> C {
                return C()
            }
        }
        """

        try await check(supportingSwift: supportingSwift, swift: """
        func f(c: C) async {
            let i = await C().i()
            let mainCi = await c.mainC().i()
            let ci = await c.c().i()
            let mainCci = await c.mainC().c().i()
        }
        """, kotlin: """
        internal suspend fun f(c: C) = Task.run {
            val i = C().mainactor { it.i() }
            val mainCi = c.mainactor { it.mainC() }.mainactor { it.i() }
            val ci = c.c().mainactor { it.i() }
            val mainCci = c.mainactor { it.mainC() }.c().mainactor { it.i() }
        }
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        func f(c: C) async {
            let i = await c.j(i: c.i())
        }
        """, kotlin: """
        internal suspend fun f(c: C) = Task.run {
            val i = c.mainactor { it.j(i = c.i()) }
        }
        """)
    }

    func testMainActorStruct() async throws {
        let supportingSwift = """
        struct S {
            @MainActor
            var r = R()
        }
        struct R {
            @MainActor
            var i = 1
            var j = 1
            @MainActor
            func f() -> Int {
                return 1
            }
        }
        """

        try await check(supportingSwift: supportingSwift, swift: """
        func f() -> Int async {
            let r = await S().r
            let i = await S().r.i
            let j = await S().r.j
            return await i + j + r.f()
        }
        """, kotlin: """
        internal suspend fun f(): Int = Task.run l@{
            val r = S().mainactor { it.r }.sref()
            val i = S().mainactor { it.r }.mainactor { it.i }
            val j = S().mainactor { it.r }.j
            return@l i + j + r.mainactor { it.f() }
        }
        """)
    }

    func testMainActorAndAsync() async throws {
        let supportingSwift = """
        class C {
            @MainActor
            func f(i: Int) {
            }
        }
        func i() async -> Int {
            return 1
        }
        """

        // Note that the call to i() within the mainactor block would require an await call in Swift.
        // In Kotlin we don't need await calls, and the mainactor block is a suspending closure
        try await check(supportingSwift: supportingSwift, swift: """
        func f() async {
            let c = C()
            await c.f(i: i())
        }
        """, kotlin: """
        internal suspend fun f() = Task.run {
            val c = C()
            c.mainactor { it.f(i = i()) }
        }
        """)
    }

    // Running this and observing the output verifies that Swift hops to the main thread when required by @MainActor, but does
    // not stay there for chained calls. Commented out to avoid warnings about using Thread.isMainThread within async code.
//    func testMainActorBehavior() async throws {
//        print("testMainActorBehavior: \(Thread.isMainThread)")
//        let _ = await MainS().anys().f().mains().f()
//    }
//
//    @MainActor
//    private struct MainS {
//        init() {
//            print("MainS.init: \(Thread.isMainThread)")
//        }
//
//        func f() async -> MainS {
//            print("MainS.f: \(Thread.isMainThread)")
//            return self
//        }
//
//        func anys() async -> AnyS {
//            print("MainS.anys: \(Thread.isMainThread)")
//            let anys = AnyS()
//            print("Now MainS.anys: \(Thread.isMainThread)")
//            return anys
//        }
//    }
//    private struct AnyS {
//        init() {
//            print("AnyS.init: \(Thread.isMainThread)")
//        }
//
//        func f() async -> AnyS {
//            print("AnyS.f: \(Thread.isMainThread)")
//            return self
//        }
//
//        func mains() async -> MainS {
//            print("AnyS.mains: \(Thread.isMainThread)")
//            let mains = await MainS()
//            print("Now AnyS.mains: \(Thread.isMainThread)")
//            return mains
//        }
//    }
}
