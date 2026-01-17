// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

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
        XCTAssertTrue(a?.apiFlags?.options.contains(.mainActor) == false)
        let b = context.primaryTypeInfo(forNamed: .named("B", []))
        XCTAssertTrue(b?.apiFlags?.options.contains(.mainActor) == true)
        let c = context.primaryTypeInfo(forNamed: .named("C", []))
        XCTAssertTrue(c?.apiFlags?.options.contains(.mainActor) == true)
        let d = context.primaryTypeInfo(forNamed: .named("D", []))
        XCTAssertTrue(d?.apiFlags?.options.contains(.mainActor) == true)
        let e = context.primaryTypeInfo(forNamed: .named("E", []))
        XCTAssertTrue(e?.apiFlags?.options.contains(.mainActor) == false)
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
        XCTAssertTrue(pa?.apiFlags?.options.contains(.mainActor) == true)
        let pb = context.primaryTypeInfo(forNamed: .named("PB", []))
        XCTAssertTrue(pb?.apiFlags?.options.contains(.mainActor) == true)
        let a = context.primaryTypeInfo(forNamed: .named("A", []))
        XCTAssertTrue(a?.apiFlags?.options.contains(.mainActor) == true)
        let b = context.primaryTypeInfo(forNamed: .named("B", []))
        XCTAssertTrue(b?.apiFlags?.options.contains(.mainActor) == true)
        let c = context.primaryTypeInfo(forNamed: .named("C", []))
        XCTAssertTrue(c?.apiFlags?.options.contains(.mainActor) == false)
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
        XCTAssertTrue(a?.apiFlags?.options.contains(.mainActor) == false)
        let v = a?.variables.first
        XCTAssertTrue(v?.apiFlags?.options.contains(.mainActor) == true)
        let f = a?.functions.first
        XCTAssertTrue(f?.apiFlags?.options.contains(.mainActor) == true)

        let c = context.primaryTypeInfo(forNamed: .named("C", []))
        XCTAssertTrue(c?.apiFlags?.options.contains(.mainActor) == false)
        let v1 = c?.variables.first
        XCTAssertTrue(v1?.apiFlags?.options.contains(.mainActor) == true)
        let f1 = c?.functions.first
        XCTAssertTrue(f1?.apiFlags?.options.contains(.mainActor) == true)
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
        XCTAssertTrue(a?.apiFlags?.options.contains(.mainActor) == false)
        let v = a?.variables.first
        XCTAssertTrue(v?.apiFlags?.options.contains(.mainActor) == true)
        let f = a?.functions.first
        XCTAssertTrue(f?.apiFlags?.options.contains(.mainActor) == true)

        let b = context.typeInfos(forNamed: .named("B", [])).first { $0.declarationType == .extensionDeclaration }
        XCTAssertTrue(b?.apiFlags?.options.contains(.mainActor) == false)
        let v1 = b?.variables.first
        XCTAssertTrue(v1?.apiFlags?.options.contains(.mainActor) == true)
        let f1 = b?.functions.first
        XCTAssertTrue(f1?.apiFlags?.options.contains(.mainActor) == true)
    }

    func testMainActorRun() async throws {
        let supportingSwift = """
        class MainActor {
            // SKIP @nodispatch
            static func run<T>(body: () throws -> T) async -> T {
                fatalError()
            }
        }
        """

        try await check(supportingSwift: supportingSwift, swift: """
        func f() async {
            await MainActor.run { print("main") }
            let x = await MainActor.run { 1 }
            let y = await MainActor.run { return 1 }
        }
        """, kotlin: """
        internal suspend fun f(): Unit = Async.run {
            MainActor.run { -> print("main") }
            val x = MainActor.run { -> 1 }
            val y = MainActor.run l@{ -> return@l 1 }
        }
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        func f() async {
            await MainActor.run {
                Task { print("here") }
            }
        }
        """, kotlin: """
        internal suspend fun f(): Unit = Async.run {
            MainActor.run { ->
                Task { -> print("here") }
            }
        }
        """)

        try await checkProducesMessage(swift: """
        func f() async {
            let mainActorClosure = {}
            await MainActor.run(body: mainActorClosure)
        }
        """)
    }

    func testTask() async throws {
        let supportingSwift = """
        struct Task<Success, Failure> where Failure: Error {
            init(priority: TaskPriority? = nil, operation: @escaping () async throws -> Success) {
            }
            static func detached<T>(operation: () throws -> T) async -> T {
                fatalError()
            }
            static func sleep(nanoseconds: UInt64) async throws {
            }
        }
        class C {
            func a() async -> C { return C() }
            @MainActor func m() {}
        }
        """

        try await check(supportingSwift: supportingSwift, swift: """
        func sleep(millis: Int) async throws {
            try await Task.sleep(nanoseconds: UInt64(1_000_000 * millis))
        }
        """, kotlin: """
        internal suspend fun sleep(millis: Int): Unit = Async.run {
            Task.sleep(nanoseconds = ULong(1_000_000 * millis))
        }
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        func f() {
            Task {
                await C().a().m()
            }
            Task { @MainActor in
                await C().a().m()
            }
            Task.detached {
                await C().a().m()
            }
            Task.detached { @MainActor in
                await C().a().m()
            }
        }
        @MainActor func g() {
            Task {
                await C().a().m()
            }
            Task { @MainActor in
                await C().a().m()
            }
            Task.detached {
                await C().a().m()
            }
            Task.detached { @MainActor in
                await C().a().m()
            }
        }
        """, kotlin: """
        internal fun f() {
            Task { -> C().a().mainactor { it.m() } }
            Task(isMainActor = true) { -> C().a().m() }
            Task.detached { -> C().a().mainactor { it.m() } }
            Task.detached { -> MainActor.run { C().a().m() } }
        }
        internal fun g() {
            Task(isMainActor = true) { -> C().a().m() }
            Task(isMainActor = true) { -> C().a().m() }
            Task.detached { -> C().a().mainactor { it.m() } }
            Task.detached { -> MainActor.run { C().a().m() } }
        }
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        func f() {
            let c = { print("any") }
            let a: () async -> Void = { print("async") }
            let m1: @MainActor () -> Void = { print("main") }
            let m2 = { @MainActor in print("main") }
            let ma: @MainActor () async -> Void = { print("main") }

            Task {
                c()
                await a()
                await m1()
                await m2()
                await ma()
            }
            Task { @MainActor in
                c()
                await a()
                m1()
                m2()
                await ma()
            }
        }

        @MainActor func g(c: () -> Void, a: () async -> Void, m: @MainActor () -> Void, ma: @MainActor () async -> Void) {
            Task {
                c()
                await a()
                m()
                await ma()
            }
        }
        """, kotlin: """
        internal fun f() {
            val c = { -> print("any") }
            val a: suspend () -> Unit = { -> Async.run { print("async") } }
            val m1: () -> Unit = { -> print("main") }
            val m2 = { -> print("main") }
            val ma: suspend () -> Unit = { -> MainActor.run { print("main") } }

            Task { ->
                c()
                a()
                MainActor.run { m1() }
                MainActor.run { m2() }
                ma()
            }
            Task(isMainActor = true) { ->
                c()
                a()
                m1()
                m2()
                ma()
            }
        }

        internal fun g(c: () -> Unit, a: suspend () -> Unit, m: () -> Unit, ma: suspend () -> Unit) {
            Task(isMainActor = true) { ->
                c()
                a()
                m()
                ma()
            }
        }
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        func f() {
            Task<Int, Error> {
                print("task")
            }
        }
        """, kotlin: """
        internal fun f() {
            Task<Int> { -> print("task") }
        }
        """)

        try await checkProducesMessage(swift: """
        func f() {
            let c = {}
            Task(operation: c)
        }
        """)

        try await checkProducesMessage(swift: """
        func f() {
            let c = {}
            Swift.Task(operation: c)
        }
        """)

        try await checkProducesMessage(swift: """
        func f() {
            let c = {}
            Task.detached(operation: c)
        }
        """)

        try await checkProducesMessage(swift: """
        func f() {
            let c = {}
            Swift.Task.detached(operation: c)
        }
        """)
    }

    func testTaskValue() async throws {
        let supportingSwift = """
        struct Task<Success, Failure> where Failure: Error {
            var value: Success {
                get async throws { fatalError() }
            }

            init(priority: TaskPriority? = nil, operation: @escaping () async throws -> Success) {
            }
        }
        """

        try await check(supportingSwift: supportingSwift, swift: """
        func f() async -> Int {
            let task = Task { 10 }
            return await task.value
        }
        """, kotlin: """
        internal suspend fun f(): Int = Async.run l@{
            val task = Task { -> 10 }
            return@l task.value()
        }
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        func f() async -> Int {
            await Task { 10 }.value
        }
        """, kotlin: """
        internal suspend fun f(): Int = Async.run l@{
            return@l Task { -> 10 }.value()
        }
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        func f() async -> Int {
            let task = Task { @MainActor in
                return 10
            }
            return await task.value
        }
        """, kotlin: """
        internal suspend fun f(): Int = Async.run l@{
            val task = Task(isMainActor = true) l@{ -> return@l 10 }
            return@l task.value()
        }
        """)
    }

    func testTaskGroup() async throws {
        let supportingSwift = """
        struct ThrowingTaskGroup<ChildTaskResult, Failure> where Failure : Error {
            // SKIP @nodispatch
            public mutating func addTask(priority: TaskPriority? = nil, operation: () async throws -> ChildTaskResult) {
            }
        }
        // SKIP @nodispatch
        func withThrowingTaskGroup<ChildTaskResult, GroupResult>(of childTaskResultType: ChildTaskResult.Type, returning returnType: GroupResult.Type? = nil, body: (ThrowingTaskGroup<ChildTaskResult, Error>) async throws -> GroupResult) async rethrows -> GroupResult {
            fatalError()
        }
        func delayedInt(millis: Int) async -> Int {
            return millis
        }
        """

        try await check(supportingSwift: supportingSwift, swift: """
        func f() async -> [Int] {
            return try await withThrowingTaskGroup(of: Int.self) { group in
                group.addTask {
                    return try await delayedInt(millis: 200)
                }
                group.addTask {
                    return try await delayedInt(millis: 100)
                }
                group.addTask {
                    return try await delayedInt(millis: 400)
                }
                var results: [Int] = []
                for try await result in group {
                    results.append(result)
                }
                return results
            }
        }
        """, kotlin: """
        import skip.lib.Array

        internal suspend fun f(): Array<Int> = Async.run l@{
            return@l withThrowingTaskGroup(of = Int::class) l@{ group ->
                group.addTask l@{ ->
                    return@l delayedInt(millis = 200)
                }
                group.addTask l@{ ->
                    return@l delayedInt(millis = 100)
                }
                group.addTask l@{ ->
                    return@l delayedInt(millis = 400)
                }
                var results: Array<Int> = arrayOf()
                for (result in group.sref()) {
                    results.append(result)
                }
                return@l results
            }
        }
        """)

        // NOTE: We require the use of "as [Int]" to tell Kotlin the generic type of the array when processing the result
        try await check(supportingSwift: supportingSwift, swift: """
        func f() async throws -> [Int] {
            try await withThrowingTaskGroup(of: [Int].self) { group in
                var results: [Int] = []
                for i in 1...5 {
                    group.addTask {
                        return [i]
                    }
                }
                for try await result in group {
                    results.append(contentsOf: result as! [Int])
                }
                return results
            }
        }
        """, kotlin: """
        import skip.lib.Array

        internal suspend fun f(): Array<Int> = Async.run l@{
            return@l withThrowingTaskGroup(of = Array::class) l@{ group ->
                var results: Array<Int> = arrayOf()
                for (i in 1..5) {
                    group.addTask l@{ -> return@l arrayOf(i) }
                }
                for (result in group.sref()) {
                    results.append(contentsOf = result as Array<Int>)
                }
                return@l results
            }
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
        internal suspend fun f(): Unit = Async.run {
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
        internal suspend fun g(): Unit = Async.run {
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
        internal suspend fun f(): Unit = Async.run {
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
        internal suspend fun g(): Unit = Async.run {
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
        internal suspend fun f(i: Int): Unit = Async.run {
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
        internal suspend fun f(c: C): Unit = Async.run {
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
        internal suspend fun f(c: C): Unit = Async.run {
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
        internal suspend fun f(c: C): Unit = Async.run {
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
        internal suspend fun f(): Int = Async.run l@{
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
        internal suspend fun f(): Unit = Async.run {
            val c = C()
            c.mainactor { it.f(i = i()) }
        }
        """)
    }

    func testMainActorClosure() async throws {
        try await check(swift: """
        @MainActor func m(p: Int) {
            print(p)
        }
        func f1(c: () async -> Void) {
        }
        func f2(c: (Int) async -> Void) {
        }
        func g() {
            let c1: () async -> Void = { @MainActor in m(p: 1) }
            f1(c: c1)
            f1(c: { @MainActor in m(p: 1) })
            let c2: (Int) async -> Void = { @MainActor in m(p: $0) }
            f2(c: c2)
            f2(c: { @MainActor in m(p: $0) })
        }
        """, kotlin: """
        internal fun m(p: Int): Unit = print(p)
        internal fun f1(c: suspend () -> Unit) = Unit
        internal fun f2(c: suspend (Int) -> Unit) = Unit
        internal fun g() {
            val c1: suspend () -> Unit = { -> MainActor.run { m(p = 1) } }
            f1(c = c1)
            f1(c = { -> MainActor.run { m(p = 1) } })
            val c2: suspend (Int) -> Unit = { it -> MainActor.run { m(p = it) } }
            f2(c = c2)
            f2(c = { it -> MainActor.run { m(p = it) } })
        }
        """)
    }

    func testAsyncClosure() async throws {
        // Normally when we specify a return type we use an anonymous function, but they don't support suspend
        try await check(swift: """
        func f1(c: () -> Int) {
        }
        func f2(c: () async -> Int) {
        }
        func g() {
            f1(c: { () -> Int in 1 })
            f2(c: { () async -> Int in 1 })
        }
        """, kotlin: """
        internal fun f1(c: () -> Int) = Unit
        internal fun f2(c: suspend () -> Int) = Unit
        internal fun g() {
            f1(c = fun(): Int = 1)
            f2(c = { -> Async.run { 1 } })
        }
        """)

        try await check(swift: """
        func f(i: Int = 0, s: String, c: (Int) async -> Int) {
        }
        func g() {
            f(s: "") { i in i + 1 }
            f(s: "", c: { i in return i + 1 })
            let c: (Int) async -> Int = { i in i }
            f(s: "", c: c)
        }
        """, kotlin: """
        internal fun f(i: Int = 0, s: String, c: suspend (Int) -> Int) = Unit
        internal fun g() {
            f(s = "") { i -> Async.run { i + 1 } }
            f(s = "", c = { i -> Async.run l@{ return@l i + 1 } })
            val c: suspend (Int) -> Int = { i -> Async.run { i } }
            f(s = "", c = c)
        }
        """)
    }

    func testExplicitUnitReturnForThrowingFunction() async throws {
        // Kotlin requires an explicit return type when the body is a lambda (as it is for async) and just throws
        try await check(swift: """
        func f() async {
            throw SomeError()
        }
        """, kotlin: """
        internal suspend fun f(): Unit = Async.run {
            throw SomeError() as Throwable
        }
        """)
    }

    func testAwaitWhileLoop() async throws {
        try await check(swift: """
        func gen() async -> Int? {
            return nil
        }
        func f() async {
            while let i = await gen() {
                print(i)
            }
        }
        """, kotlin: """
        internal suspend fun gen(): Int? = Async.run l@{
            return@l null
        }
        internal suspend fun f(): Unit = Async.run {
            while (true) {
                val i_0 = gen()
                if (i_0 == null) {
                    break
                }
                print(i_0)
            }
        }
        """)

        try await check(swift: """
        @MainActor func g() -> Gen {
            return Gen()
        }
        class Gen {
            func gen() async -> Int? {
                return nil
            }
        }
        func f() async {
            while let i = await g().gen() {
                print(i)
            }
        }
        """, kotlin: """
        internal fun g(): Gen = Gen()
        internal open class Gen {
            internal open suspend fun gen(): Int? = Async.run l@{
                return@l null
            }
        }
        internal suspend fun f(): Unit = Async.run {
            while (true) {
                val i_0 = MainActor.run { g() }.gen()
                if (i_0 == null) {
                    break
                }
                print(i_0)
            }
        }
        """)
    }

    func testAwaitForLoop() async throws {
        try await check(swift: """
        func f() async {
            for await i in [1, 2, 3] {
                print(i)
            }
        }
        """, kotlin: """
        import skip.lib.Array

        internal suspend fun f(): Unit = Async.run {
            for (i in arrayOf(1, 2, 3)) {
                print(i)
            }
        }
        """)

        try await check(swift: """
        @MainActor func g() -> [Int] {
            return [1, 2, 3]
        }
        func f() async {
            for await i in g() {
                print(i)
            }
        }
        """, kotlin: """
        import skip.lib.Array
        
        internal fun g(): Array<Int> = arrayOf(1, 2, 3)
        internal suspend fun f(): Unit = Async.run {
            for (i in MainActor.run { g() }) {
                print(i)
            }
        }
        """)
    }

    func testAsyncLet() async throws {
        try await check(supportingSwift: """
        func g() async -> Int {
            return 1
        }
        """, swift: """
        func f() async -> Int {
            async let a = g()
            async let b = g()
            return await a + b
        }
        """, kotlin: """
        internal suspend fun f(): Int = Async.run l@{
            val a = Task { g() }
            val b = Task { g() }
            return@l a.value() + b.value()
        }
        """)

        try await check(supportingSwift: """
        func g() async -> Int {
            return 1
        }
        """, swift: """
        @MainActor func f() async -> Int {
            async let a = g()
            async let b = g()
            return await a + b
        }
        """, kotlin: """
        internal suspend fun f(): Int = MainActor.run l@{
            val a = Task { g() }
            val b = Task { g() }
            return@l a.value() + b.value()
        }
        """)

        try await check(supportingSwift: """
        @MainActor func g() -> Int {
            return 1
        }
        func collect(a: Int, b: Int) {
        }
        """, swift: """
        func f() async {
            async let a = g()
            async let b = g()
            collect(a: a, b: b)
        }
        """, kotlin: """
        internal suspend fun f(): Unit = Async.run {
            val a = Task { MainActor.run { g() } }
            val b = Task { MainActor.run { g() } }
            collect(a = a.value(), b = b.value())
        }
        """)

        try await check(supportingSwift: """
        struct S {
            var x = 0
        }
        @MainActor func g() -> S {
            return S(x: 1)
        }
        @MainActor var v: S {
            return S(x: 2)
        }
        func collect(a: S, b: S) {
        }
        """, swift: """
        func f() async {
            async let a = g()
            async let b = v
            let x = a
            let y = b
            return a.x + x.x + b.x + y.x
        }
        """, kotlin: """
        internal suspend fun f(): Unit = Async.run l@{
            val a = Task { MainActor.run { g() } }
            val b = Task { MainActor.run { v }.sref() }
            val x = a.value().sref()
            val y = b.value().sref()
            return@l a.value().x + x.x + b.value().x + y.x
        }
        """)

        try await checkProducesMessage(swift: """
        func f() async -> Int {
            async let a = f()
            if a > 0 {
                let a = 5 // Cannot re-bind
                return a
            }
            return a
        }
        """)
    }

    func testLocalFunction() async throws {
        try await check(swift: """
        func f() -> Int {
            @MainActor func b(i: Int) -> Int { i }
            func c() async -> Int {
                return await b(i: 100)
            }
            return await c()
        }
        """, kotlin: """
        internal fun f(): Int {
            fun b(i: Int): Int = i
            suspend fun c(): Int = Async.run l@{
                return@l MainActor.run { b(i = 100) }
            }
            return c()
        }
        """)
    }

    func testActorDeclaration() async throws {
        try await checkProducesMessage(swift: """
        actor A {
            var x = 1
        }
        """)

        try await checkProducesMessage(swift: """
        actor A {
            var x: Int {
                get {
                    return 1
                }
                set {
                }
            }
        }
        """)

        try await check(swift: """
        actor A {
            let c = 100
            private var x: Int

            init(x: Int) {
                self.x = x
            }

            var y: Int {
                return x
            }

            func f() {
                g()
                print(y)
            }

            func g() {
                x += 1
            }

            static var staticx = 1

            static func staticf() {
            }

            nonisolated func syncf() {
                print("nonisolated")
            }
        }
        """, kotlin: """
        internal class A: Actor {
            override val isolatedContext = Actor.isolatedContext()
            internal val c = 100
            private var x: Int

            internal constructor(x: Int) {
                this.x = x
            }

            internal suspend fun y(): Int = Actor.run(this) l@{
                return@l x
            }

            internal suspend fun f(): Unit = Actor.run(this) {
                g()
                print(y())
            }

            internal suspend fun g(): Unit = Actor.run(this) {
                x += 1
            }

            internal fun syncf(): Unit = print("nonisolated")

            companion object {

                internal var staticx = 1

                internal fun staticf() = Unit
            }
        }
        """)
    }

    func testActorExtension() async throws {
        try await check(swift: """
        actor A {
            func f() {
            }
        }

        extension A {
            var x: Int {
                return 1
            }

            func g() {
                f()
            }

            nonisolated func h() {
            }
        }
        """, kotlin: """
        internal class A: Actor {
            override val isolatedContext = Actor.isolatedContext()
            internal suspend fun f(): Unit = Unit

            internal suspend fun x(): Int = Actor.run(this) l@{
                return@l 1
            }

            internal suspend fun g(): Unit = Actor.run(this) {
                f()
            }

            internal fun h() = Unit
        }
        """)
    }

    func testActorAccess() async throws {
        try await check(supportingSwift: """
        actor A {
            private var _x: Int

            init(x: Int) {
                _x = x
            }

            var x: Int {
                return _x
            }

            func f() {
            }

            nonisolated func g() {
            }
        }
        """, swift: """
        func test() async {
            let a = A(x: 100)
            print(a.x)
            await a.f()
            a.g()
        }
        """, kotlin: """
        internal suspend fun test(): Unit = Async.run {
            val a = A(x = 100)
            print(a.x())
            a.f()
            a.g()
        }
        """)
    }

    func testSuspendingNestingClosure() async throws {
        try await check(swift: """
        func f() async -> Int? {
            return if let x = await f() {
                x + 1
            } else {
                0
            }
        }
        """, kotlin: """
        internal suspend fun f(): Int? = Async.run l@{
            return@l linvokeSuspend l@{
                val matchtarget_0 = f()
                if (matchtarget_0 != null) {
                    val x = matchtarget_0
                    return@l x + 1
                } else {
                    return@l 0
                }
            }
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
