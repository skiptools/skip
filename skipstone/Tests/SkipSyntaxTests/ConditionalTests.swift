import XCTest

final class ConditionalTests: XCTestCase {
    func testIfCondition() async throws {
        try await check(swift: """
        if i == 1 {
            print("yes")
        }
        """, kotlin: """
        if (i == 1) {
            print("yes")
        }
        """)
        
        try await check(swift: """
        if !(i == 1) {
            print("yes")
        }
        """, kotlin: """
        if (!(i == 1)) {
            print("yes")
        }
        """)
    }

    func testCompoundIfCondition() async throws {
        try await check(swift: """
        if i > 1 && i < 100 {
            print("yes")
        }
        """, kotlin: """
        if (i > 1 && i < 100) {
            print("yes")
        }
        """)

        try await check(swift: """
        if (i < 0 || i > 1) && i < 100 {
            print("yes")
        }
        """, kotlin: """
        if ((i < 0 || i > 1) && i < 100) {
            print("yes")
        }
        """)

        try await check(swift: """
        if i < 0 || (i > 1 && i < 100) {
            print("yes")
        }
        """, kotlin: """
        if (i < 0 || (i > 1 && i < 100)) {
            print("yes")
        }
        """)
    }

    func testMultipleIfConditions() async throws {
        try await check(swift: """
        if boolValue, i < 100 {
            print("yes")
        }
        """, kotlin: """
        if (boolValue && (i < 100)) {
            print("yes")
        }
        """)
    }

    func testElse() async throws {
        try await check(swift: """
        if i < 100 {
            print("yes")
        } else {
            print("no")
        }
        """, kotlin: """
        if (i < 100) {
            print("yes")
        } else {
            print("no")
        }
        """)
    }

    func testElseIf() async throws {
        try await check(swift: """
        if i < 0 {
            print("negative")
        } else if i > 0 {
            print("positive")
        } else {
            print("zero")
        }
        """, kotlin: """
        if (i < 0) {
            print("negative")
        } else if (i > 0) {
            print("positive")
        } else {
            print("zero")
        }
        """)
    }

    func testOptionalBinding() async throws {
        try await check(swift: """
        {
            var i: Int?
            if let i {
                print(i)
            }
        }
        """, kotlin: """
        {
            var i: Int?
            if (i != null) {
                print(i)
            }
        }
        """)

        try await check(swift: """
        {
            var i: Int?
            if let i = i {
                print(i)
            }
        }
        """, kotlin: """
        {
            var i: Int?
            if (i != null) {
                print(i)
            }
        }
        """)

        try await check(swift: """
        {
            var i: Int?
            if let x = i {
                print(x)
            }
        }
        """, kotlin: """
        {
            var i: Int?
            i?.let { x ->
                print(x)
            }
        }
        """)
    }

    func testOptionalBindingToMember() async throws {
        try await check(swift: """
        class C {
            var i: Int?
            let j: Int?
            func f() {
                if let i {
                    print(i)
                }
                if let j {
                    print(j)
                }
            }
        }
        """, kotlin: """
        internal open class C {
            internal open var i: Int? = null
            internal val j: Int?
            internal open fun f() {
                i?.let { i ->
                    print(i)
                }
                if (j != null) {
                    print(j)
                }
            }
        }
        """)

        try await check(swift: """
        class C {
            var i: Int?
            let j: Int?
            func f() {
                if let i = i {
                    print(i)
                }
                if let j = j {
                    print(j)
                }
            }
        }
        """, kotlin: """
        internal open class C {
            internal open var i: Int? = null
            internal val j: Int?
            internal open fun f() {
                i?.let { i ->
                    print(i)
                }
                if (j != null) {
                    print(j)
                }
            }
        }
        """)

        try await check(swift: """
        class C {
            var i: Int?
            let j: Int?
            func f() {
                if let x = i {
                    print(x)
                }
                if let y = j {
                    print(y)
                }
            }
        }
        """, kotlin: """
        internal open class C {
            internal open var i: Int? = null
            internal val j: Int?
            internal open fun f() {
                i?.let { x ->
                    print(x)
                }
                j?.let { y ->
                    print(y)
                }
            }
        }
        """)
    }

    func testMutableStructOptionalBinding() async throws {
        // Translate let into a simple null check because the value can't change
        try await check(swift: """
        {
            let i: S?
            if let i {
                print(i)
            }
        }
        """, kotlin: """
        {
            val i: S?
            if (i != null) {
                print(i)
            }
        }
        """)

        // Translate var into a new reference because we don't want to mutate the original value
        try await check(swift: """
        {
            let i: S?
            if var i {
                i.mutate()
            }
        }
        """, kotlin: """
        {
            val i: S?
            i.sref()?.let { i ->
                var i = i
                i.mutate()
            }
        }
        """)
    }

    func testOptionalBindingElse() async throws {
        try await check(swift: """
        {
            var i: Int?
            if let i {
                print(i)
            } else {
                print("nil")
            }
        }
        """, kotlin: """
        {
            var i: Int?
            if (i != null) {
                print(i)
            } else {
                print("nil")
            }
        }
        """)

        try await check(swift: """
        {
            var i: Int?
            if let x = i {
                print(x)
            } else {
                print("nil")
            }
        }
        """, kotlin: """
        {
            var i: Int?
            var letexec_0 = false
            i?.let { x ->
                letexec_0 = true
                print(x)
            }
            if (!letexec_0) {
                print("nil")
            }
        }
        """)
    }

    func testOptionalBindingElseIf() async throws {
        try await check(swift: """
        {
            var i: Int?
            if x > 0 {
                print("positive")
            } else if let i {
                print(i)
            } else if let x = i {
                print(x)
            } else {
                print("nil")
            }
        }
        """, kotlin: """
        {
            var i: Int?
            if (x > 0) {
                print("positive")
            } else if (i != null) {
                print(i)
            } else {
                var letexec_0 = false
                i?.let { x ->
                    letexec_0 = true
                    print(x)
                }
                if (!letexec_0) {
                    print("nil")
                }
            }
        }
        """)

        try await check(swift: """
        {
            var i: Int?
            if var i {
                print(i)
            } else if x > 0 {
                print("positive")
            } else if let y = i {
                print(y)
            }
        }
        """, kotlin: """
        {
            var i: Int?
            var letexec_0 = false
            i?.let { i ->
                var i = i
                letexec_0 = true
                print(i)
            }
            if (!letexec_0) {
                if (x > 0) {
                    print("positive")
                } else {
                    i?.let { y ->
                        print(y)
                    }
                }
            }
        }
        """)

        try await check(swift: """
        {
            var i: Int?
            if var i {
                print(i)
            } else if let x = i {
                print(x)
            } else {
                print("nil")
            }
        }
        """, kotlin: """
        {
            var i: Int?
            var letexec_0 = false
            i?.let { i ->
                var i = i
                letexec_0 = true
                print(i)
            }
            if (!letexec_0) {
                var letexec_1 = false
                i?.let { x ->
                    letexec_1 = true
                    print(x)
                }
                if (!letexec_1) {
                    print("nil")
                }
            }
        }
        """)
    }

    func testMultipleOptionalBindings() async throws {
        try await check(swift: """
        {
            var i: Int?
            var j: String?
            var k: Int?
            if var i, i > 5, let x = j, x == "x" || x == "y" {
                print(i)
            } else if boolValue, let x = k {
                print(x)
            }
        }
        """, kotlin: """
        {
            var i: Int?
            var j: String?
            var k: Int?
            var letexec_0 = false
            i?.let { i ->
                var i = i
                if (i > 5) {
                    j?.let { x ->
                        if (x == "x" || x == "y") {
                            letexec_0 = true
                            print(i)
                        }
                    }
                }
            }
            if (!letexec_0) {
                if (boolValue) {
                    k?.let { x ->
                        print(x)
                    }
                }
            }
        }
        """)
    }

    func testOptionalBindingUsingPreviousOptionalBinding() async throws {
        try await check(supportingSwift: """
        class C {
            var related: C?
        }
        """, swift: """
        {
            var c: C?
            if let x = c, let related = x.related, let doublerelated = related.related {
                print(doublerelated)
            }
        }
        """, kotlin: """
        {
            var c: C?
            c?.let { x ->
                x.related?.let { related ->
                    related.related?.let { doublerelated ->
                        print(doublerelated)
                    }
                }
            }
        }
        """)
    }

    func testOptionalBindingTuple() async throws {
        let supportingSwift = """
        func f() -> (Int, String)? {
            return nil
        }
        """

        try await check(supportingSwift: supportingSwift, swift: """
        let a = f()
        if let (x, y) = a {
            print(x)
            print(y)
        }
        """, kotlin: """
        internal val a = f()
        a?.let { (x, y) ->
            print(x)
            print(y)
        }
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        if let (x, y) = f() {
            print(x)
            print(y)
        }
        """, kotlin: """
        f()?.let { (x, y) ->
            print(x)
            print(y)
        }
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        if let (x, y) = f() {
            print(x)
            print(y)
        } else {
            print("nope")
        }
        """, kotlin: """
        var letexec_0 = false
        f()?.let { (x, y) ->
            letexec_0 = true
            print(x)
            print(y)
        }
        if (!letexec_0) {
            print("nope")
        }
        """)
    }

    func testAddUnreachableErrorIfReturnRequired() async throws {
        try await check(swift: """
        func f(i: Int?) -> Int {
            if let x = i {
                return x
            } else {
                return 0
            }
        }
        """, kotlin: """
        internal fun f(i: Int?): Int {
            var letexec_0 = false
            i?.let { x ->
                letexec_0 = true
                return x
            }
            if (!letexec_0) {
                return 0
            }
            error("Unreachable")
        }
        """)

        // No error added if the block ends in 'return'
        try await check(swift: """
        func f(i: Int?) -> Int {
            if let x = i {
                return x
            } else {
                print("null")
            }
            return 0
        }
        """, kotlin: """
        internal fun f(i: Int?): Int {
            var letexec_0 = false
            i?.let { x ->
                letexec_0 = true
                return x
            }
            if (!letexec_0) {
                print("null")
            }
            return 0
        }
        """)

        // No error added for 'if' that retains its 'else'
        try await check(swift: """
        func f(i: Int?) -> Int {
            if let i {
                return i
            } else {
                return 0
            }
        }
        """, kotlin: """
        internal fun f(i: Int?): Int {
            if (i != null) {
                return i
            } else {
                return 0
            }
        }
        """)

        try await check(swift: """
        func f(i: Int?) -> Int {
            let r = {
                if let x = i {
                    return x
                } else {
                    return 0
                }
            }()
            return r
        }
        """, kotlin: """
        internal fun f(i: Int?): Int {
            val r = linvoke l@{
                var letexec_0 = false
                i?.let { x ->
                    letexec_0 = true
                    return@l x
                }
                if (!letexec_0) {
                    return@l 0
                }
                error("Unreachable")
            }
            return r
        }
        """)

        // No error added if no value returned
        try await check(swift: """
        func f(i: Int?) -> Int {
            {
                if let x = i {
                    print(x)
                } else {
                    print(0)
                }
            }()
            return 100
        }
        """, kotlin: """
        internal fun f(i: Int?): Int {
            {
                var letexec_0 = false
                i?.let { x ->
                    letexec_0 = true
                    print(x)
                }
                if (!letexec_0) {
                    print(0)
                }
            }()
            return 100
        }
        """)
    }

    func testCompoundOptionalBinding() async throws {
        try await check(swift: """
        func f() -> String {
            let dict: [String: Any] = ["A": 1]
            if let num = dict["A"] as? Int {
                return "A"
            } else {
                return "B"
            }
        }
        """, kotlin: """
        internal fun f(): String {
            val dict: Dictionary<String, Any> = dictionaryOf(Tuple2("A", 1))
            var letexec_0 = false
            (dict["A"] as? Int)?.let { num ->
                letexec_0 = true
                return "A"
            }
            if (!letexec_0) {
                return "B"
            }
            error("Unreachable")
        }
        """)
    }

    func testIfCase() async throws {
        try await check(supportingSwift: """
        enum E {
            case case1
            case case2
        }
        """, swift: """
        func f(e: E) {
            if case .case1 = e {
                print("A")
            }
        }
        """, kotlin: """
        internal fun f(e: E) {
            if (e == E.case1) {
                print("A")
            }
        }
        """)

        try await check(supportingSwift: """
        enum E {
            case case1(d: Double)
            case case2(Int, String)
        }
        """, swift: """
        func f(e: E) {
            if case .case2 = e {
                print("A")
            }
            if case .case2(_, let s) = e {
                print(s)
            }
            if case var .case1(d: num) = e {
                print(num)
            }
        }
        """, kotlin: """
        internal fun f(e: E) {
            if (e is E.Case2Case) {
                print("A")
            }
            if (e is E.Case2Case) {
                val s = e.associated1
                print(s)
            }
            if (e is E.Case1Case) {
                var num = e.d
                print(num)
            }
        }
        """)
    }

    func testIfCaseTargetVariable() async throws {
        try await check(supportingSwift: """
        func enumFactory() -> E {
            return .case1
        }
        enum E {
            case case1
            case case2(Int, String)
        }
        """, swift: """
        // No target variable needed if no bindings
        if case .case2 = enumFactory() {
            print("case2")
        }

        if case .case2(let i, _) = enumFactory() {
            print(i)
        }
        """, kotlin: """
        // No target variable needed if no bindings
        if (enumFactory() is E.Case2Case) {
            print("case2")
        }

        val matchtarget_0 = enumFactory()
        if (matchtarget_0 is E.Case2Case) {
            val i = matchtarget_0.associated0
            print(i)
        }
        """)
    }

    func testCompoundIfCaseConditions() async throws {
        try await check(supportingSwift: """
        enum E {
            case case1
            case case2(Int, String)
        }
        """, swift: """
        {
            var i: Int?
            let e: E
            if let i {
                print(i)
            } else if case .case2(_, let s) = e {
                print(s)
            } else {
                print("else")
            }
        }
        """, kotlin: """
        {
            var i: Int?
            val e: E
            if (i != null) {
                print(i)
            } else if (e is E.Case2Case) {
                val s = e.associated1
                print(s)
            } else {
                print("else")
            }
        }
        """)

        try await check(supportingSwift: """
        func enumFactory() -> E {
            return .case1
        }
        enum E {
            case case1
            case case2(Int, String)
        }
        """, swift: """
        {
            var i: Int?
            if let i {
                print(i)
            } else if case .case2(let i, let s) = enumFactory(), i > 1 {
                print(s)
            } else {
                print("else")
            }
        }
        """, kotlin: """
        {
            var i: Int?
            if (i != null) {
                print(i)
            } else {
                var letexec_0 = false
                val matchtarget_0 = enumFactory()
                if (matchtarget_0 is E.Case2Case) {
                    val i = matchtarget_0.associated0
                    val s = matchtarget_0.associated1
                    if (i > 1) {
                        letexec_0 = true
                        print(s)
                    }
                }
                if (!letexec_0) {
                    print("else")
                }
            }
        }
        """)

        try await check(supportingSwift: """
        func enumFactory() -> E {
            return .case1
        }
        enum E {
            case case1
            case case2(Int, String)
        }
        """, swift: """
        {
            var i: Int?
            if let x = i, case .case2(let i, _) = enumFactory() {
                print(x + i)
            } else {
                print("else")
            }
        }
        """, kotlin: """
        {
            var i: Int?
            var letexec_0 = false
            i?.let { x ->
                val matchtarget_0 = enumFactory()
                if (matchtarget_0 is E.Case2Case) {
                    val i = matchtarget_0.associated0
                    letexec_0 = true
                    print(x + i)
                }
            }
            if (!letexec_0) {
                print("else")
            }
        }
        """)
    }

    func testIfAsAssignmentExpression() async throws {
        try await check(swift: """
        {
            let i = 0
            let j = if i < 0 {
                "Negative"
            } else if i == 0 {
                "Zero"
            } else {
                "Positive"
            }
        }
        """, kotlin: """
        {
            val i = 0
            val j = if (i < 0) {
                "Negative"
            } else if (i == 0) {
                "Zero"
            } else {
                "Positive"
            }
        }
        """)

        try await check(swift: """
        {
            var i: Int? = nil
            let j = if let i {
                "Non-Nil"
            } else if f() {
                "f"
            } else {
                "Nil"
            }
        }
        """, kotlin: """
        {
            var i: Int? = null
            val j = if (i != null) {
                "Non-Nil"
            } else if (f()) {
                "f"
            } else {
                "Nil"
            }
        }
        """)

        try await check(swift: """
        func f() {
            var i: Int? = nil
            let j = if let x = i {
                x + 1
            } else if let y = i {
                y * 2
            } else if g() {
                -1
            } else {
                0
            }
        }
        """, kotlin: """
        internal fun f() {
            var i: Int? = null
            val j = linvoke l@{
                var letexec_0 = false
                i?.let { x ->
                    letexec_0 = true
                    return@l x + 1
                }
                if (!letexec_0) {
                    var letexec_1 = false
                    i?.let { y ->
                        letexec_1 = true
                        return@l y * 2
                    }
                    if (!letexec_1) {
                        if (g()) {
                            return@l -1
                        } else {
                            return@l 0
                        }
                    }
                }
                error("Unreachable")
            }
        }
        """)
    }

    func testIfAsReturnExpression() async throws {
        try await check(swift: """
        func f(i: Int) -> Int {
            if i < 0 {
                -1
            } else if i == 0 {
                -2
            } else {
                i
            }
        }
        """, kotlin: """
        internal fun f(i: Int): Int {
            return if (i < 0) {
                -1
            } else if (i == 0) {
                -2
            } else {
                i
            }
        }
        """)

        try await check(swift: """
        func f(i: Int) throws -> Int {
            if i < 0 { throw MyError() } else { i }
        }
        """, kotlin: """
        internal fun f(i: Int): Int {
            return if (i < 0) {
                throw MyError() as Throwable
            } else {
                i
            }
        }
        """)

        try await check(swift: """
        func f(i: Int?) -> Int {
            if let x = i {
                x + 1
            } else if let y = g() {
                y
            } else {
                0
            }
        }
        func g(i: Int? = nil) -> Int {
            if let x = i {
                print(x)
            } else {
                print("Nil")
            }
            return 1
        }
        """, kotlin: """
        internal fun f(i: Int?): Int {
            return linvoke l@{
                var letexec_0 = false
                i?.let { x ->
                    letexec_0 = true
                    return@l x + 1
                }
                if (!letexec_0) {
                    var letexec_1 = false
                    g()?.let { y ->
                        letexec_1 = true
                        return@l y
                    }
                    if (!letexec_1) {
                        return@l 0
                    }
                }
                error("Unreachable")
            }
        }
        internal fun g(i: Int? = null): Int {
            var letexec_2 = false
            i?.let { x ->
                letexec_2 = true
                print(x)
            }
            if (!letexec_2) {
                print("Nil")
            }
            return 1
        }
        """)

        try await check(swift: """
        func f(i: Int?) -> Int {
            return if let x = i {
                x + 1
            } else {
                0
            }
        }
        """, kotlin: """
        internal fun f(i: Int?): Int {
            return linvoke l@{
                var letexec_0 = false
                i?.let { x ->
                    letexec_0 = true
                    return@l x + 1
                }
                if (!letexec_0) {
                    return@l 0
                }
                error("Unreachable")
            }
        }
        """)
    }

    func testIfAsClosureReturnExpression() async throws {
        try await check(swift: """
        func f(i: Int) {
            let c = {
                if let x = i {
                    print(x)
                } else {
                    print("Nil")
                }
            }
        }
        """, kotlin: """
        internal fun f(i: Int) {
            val c = {
                var letexec_0 = false
                i?.let { x ->
                    letexec_0 = true
                    print(x)
                }
                if (!letexec_0) {
                    print("Nil")
                }
            }
        }
        """)

        // We have no reliable way to detect using 'if' as an implicit return value vs. a statement in a closure
        try await check(expectFailure: true, swift: """
        func f(i: Int) {
            let c = {
                if let x = i {
                    x + 1
                } else {
                    0
                }
            }
        }
        """, kotlin: """
        internal fun f(i: Int) {
            val c = l@{
                var letexec_0 = false
                i?.let { x ->
                    letexec_0 = true
                    return@l x + 1
                }
                if (!letexec_0) {
                    return@l 0
                }
            }
        }
        """)

        try await check(swift: """
        func f(i: Int) {
            let c = { () -> Int in
                if let x = i {
                    x + 1
                } else {
                    0
                }
            }
        }
        """, kotlin: """
        internal fun f(i: Int) {
            val c = fun(): Int {
                return linvoke l@{
                    var letexec_0 = false
                    i?.let { x ->
                        letexec_0 = true
                        return@l x + 1
                    }
                    if (!letexec_0) {
                        return@l 0
                    }
                    error("Unreachable")
                }
            }
        }
        """)

        try await check(swift: """
        func f(i: Int) {
            let c: () -> Int = {
                if let x = i {
                    x + 1
                } else {
                    0
                }
            }
        }
        """, kotlin: """
        internal fun f(i: Int) {
            val c: () -> Int = {
                linvoke l@{
                    var letexec_0 = false
                    i?.let { x ->
                        letexec_0 = true
                        return@l x + 1
                    }
                    if (!letexec_0) {
                        return@l 0
                    }
                    error("Unreachable")
                }
            }
        }
        """)

        try await check(swift: """
        func f(i: Int) {
            let c: () -> Int = {
                if let x = i {
                    return x + 1
                } else {
                    return 0
                }
            }
        }
        """, kotlin: """
        internal fun f(i: Int) {
            val c: () -> Int = l@{
                var letexec_0 = false
                i?.let { x ->
                    letexec_0 = true
                    return@l x + 1
                }
                if (!letexec_0) {
                    return@l 0
                }
                error("Unreachable")
            }
        }
        """)

        try await check(swift: """
        func f(i: Int) {
            let c: () -> Int = {
                return if let x = i {
                    x + 1
                } else {
                    0
                }
            }
        }
        """, kotlin: """
        internal fun f(i: Int) {
            val c: () -> Int = l@{
                return@l linvoke l@{
                    var letexec_0 = false
                    i?.let { x ->
                        letexec_0 = true
                        return@l x + 1
                    }
                    if (!letexec_0) {
                        return@l 0
                    }
                    error("Unreachable")
                }
            }
        }
        """)
    }

    func testGuardCondition() async throws {
        try await check(swift: """
        guard i == 1 else {
            return
        }
        """, kotlin: """
        if (i != 1) {
            return
        }
        """)

        try await check(swift: """
        guard !(i == 1) else {
            return
        }
        """, kotlin: """
        if ((i == 1)) {
            return
        }
        """)
    }

    func testCompoundGuardCondition() async throws {
        try await check(swift: """
        guard i > 1 && i < 100 else {
            return
        }
        """, kotlin: """
        if (i <= 1 || i >= 100) {
            return
        }
        """)

        try await check(swift: """
        guard (i < 0 || i > 1) && i < 100 else {
            return
        }
        """, kotlin: """
        if ((i >= 0 && i <= 1) || i >= 100) {
            return
        }
        """)

        try await check(swift: """
        guard i < 0 || (i > 1 && i < 100) else {
            return
        }
        """, kotlin: """
        if (i >= 0 && (i <= 1 || i >= 100)) {
            return
        }
        """)
    }

    func testMultipleGuardConditions() async throws {
        try await check(swift: """
        guard boolValue, i <= 100 else {
            return
        }
        """, kotlin: """
        if (!boolValue || (i > 100)) {
            return
        }
        """)
    }

    func testGuardOptionalBinding() async throws {
        try await check(swift: """
        {
            var i: Int?
            guard let i else {
                print(i)
                return
            }
            print(i + 1)
        }
        """, kotlin: """
        l@{
            var i: Int?
            if (i == null) {
                print(i)
                return@l
            }
            print(i + 1)
        }
        """)

        try await check(swift: """
        {
            var i: Int?
            guard let i = i else {
                print(i)
                return
            }
            print(i + 1)
        }
        """, kotlin: """
        l@{
            var i: Int?
            if (i == null) {
                print(i)
                return@l
            }
            print(i + 1)
        }
        """)

        try await check(swift: """
        {
            var i: Int?
            guard var i = i else {
                print(i)
                return
            }
            print(i + 1)
        }
        """, kotlin: """
        l@{
            var i: Int?
            var i_0 = i
            if (i_0 == null) {
                print(i)
                return@l
            }
            print(i_0 + 1)
        }
        """)
    }

    func testGuardOptionalBindingToMember() async throws {
        try await check(swift: """
        class C {
            var i: Int?
            let j: Int?
            func f() {
                guard let i else {
                    print(i)
                    return
                }
                guard let j else {
                    print(j)
                    return
                }
                print(i + j)
            }
        }
        """, kotlin: """
        internal open class C {
            internal open var i: Int? = null
            internal val j: Int?
            internal open fun f() {
                val i_0 = i
                if (i_0 == null) {
                    print(i)
                    return
                }
                if (j == null) {
                    print(j)
                    return
                }
                print(i_0 + j)
            }
        }
        """)

        try await check(swift: """
        class C {
            var i: Int?
            let j: Int?
            func f() {
                guard let i = i else {
                    print(i)
                    return
                }
                guard let j = j else {
                    print(j)
                    return
                }
                print(i + j)
            }
        }
        """, kotlin: """
        internal open class C {
            internal open var i: Int? = null
            internal val j: Int?
            internal open fun f() {
                val i_0 = i
                if (i_0 == null) {
                    print(i)
                    return
                }
                if (j == null) {
                    print(j)
                    return
                }
                print(i_0 + j)
            }
        }
        """)

        try await check(swift: """
        class C {
            var i: Int?
            let j: Int?
            func f() {
                guard var i = i else {
                    print(i)
                    return
                }
                guard var j = j else {
                    print(j)
                    return
                }
                print(i + j)
            }
        }
        """, kotlin: """
        internal open class C {
            internal open var i: Int? = null
            internal val j: Int?
            internal open fun f() {
                var i_0 = i
                if (i_0 == null) {
                    print(i)
                    return
                }
                var j_0 = j
                if (j_0 == null) {
                    print(j)
                    return
                }
                print(i_0 + j_0)
            }
        }
        """)
    }

    func testGuardMutableStructOptionalBinding() async throws {
        try await check(swift: """
        {
            let i: S?
            guard let i else {
                print(i)
                return
            }
            print(i)
        }
        """, kotlin: """
        l@{
            val i: S?
            if (i == null) {
                print(i)
                return@l
            }
            print(i)
        }
        """)

        try await check(swift: """
        {
            guard let x = i else {
                print(i)
                return
            }
            print(x)
        }
        """, kotlin: """
        l@{
            val x_0 = i.sref()
            if (x_0 == null) {
                print(i)
                return@l
            }
            print(x_0)
        }
        """)
    }

    func testGuardOptionalBindingUsingPreviousOptionalBinding() async throws {
        try await check(supportingSwift: """
        class C {
            var related: C?
        }
        """, swift: """
        {
            var c: C?
            guard var c, c > 5, let related = c.related, let doublerelated = related.related else {
                doSomethingWith(c)
                return
            }
            print(doublerelated)
        }
        """, kotlin: """
        l@{
            var c: C?
            var c_0 = c
            if ((c_0 == null) || (c_0 <= 5)) {
                doSomethingWith(c)
                return@l
            }
            val related_0 = c_0.related
            if (related_0 == null) {
                doSomethingWith(c)
                return@l
            }
            val doublerelated_0 = related_0.related
            if (doublerelated_0 == null) {
                doSomethingWith(c)
                return@l
            }
            print(doublerelated_0)
        }
        """)
    }

    func testGuardsWithSameNamedOptionalBindings() async throws {
        try await check(swift: """
        {
            var i: Int?
            guard var i else {
                print(i)
                return
            }
            print(i)
            guard var i = x else {
                print(i)
                return
            }
            print(i)
        }
        """, kotlin: """
        l@{
            var i: Int?
            var i_0 = i
            if (i_0 == null) {
                print(i)
                return@l
            }
            print(i_0)
            var i_1 = x.sref()
            if (i_1 == null) {
                print(i_0)
                return@l
            }
            print(i_1)
        }
        """)
    }

    func testGuardOptionalBindingTuple() async throws {
        let supportingSwift = """
        func f() -> (Int, String)? {
            return nil
        }
        """

        try await check(supportingSwift: supportingSwift, swift: """
        let a = f()
        guard let (x, y) = a else {
            return
        }
        print(x)
        print(y)
        """, kotlin: """
        internal val a = f()
        if (a == null) {
            return
        }
        val (x_0, y_0) = a
        print(x_0)
        print(y_0)
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        guard let (x, y) = f() else {
            return
        }
        print(x)
        print(y)
        """, kotlin: """
        val matchtarget_0 = f()
        if (matchtarget_0 == null) {
            return
        }
        val (x_0, y_0) = matchtarget_0
        print(x_0)
        print(y_0)
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        let a = 1
        guard a >= 1, let (x, y) = f(), x >= y, let (z, _) = f() else {
            return
        }
        print(x)
        print(y)
        print(z)
        """, kotlin: """
        internal val a = 1
        if (a < 1) {
            return
        }
        val matchtarget_0 = f()
        if (matchtarget_0 == null) {
            return
        }
        val (x_0, y_0) = matchtarget_0
        if (x_0 < y_0) {
            return
        }
        val matchtarget_1 = f()
        if (matchtarget_1 == null) {
            return
        }
        val (z_0, _) = matchtarget_1
        print(x_0)
        print(y_0)
        print(z_0)
        """)
    }

    func testGuardCase() async throws {
        try await check(supportingSwift: """
        enum E {
            case case1
            case case2
        }
        """, swift: """
        {
            let e: E
            guard case .case1 = e else {
                print("no")
                return
            }
            print(e)
        }
        """, kotlin: """
        l@{
            val e: E
            if (e != E.case1) {
                print("no")
                return@l
            }
            print(e)
        }
        """)
    }

    func testGuardCaseTargetVariable() async throws {
        try await check(supportingSwift: """
        func enumFactory() -> E {
            return .case1
        }
        enum E {
            case case1
            case case2(Int, String)
        }
        """, swift: """
        guard case var .case2(_, s) = enumFactory() else {
            print("no")
            return
        }
        print(s)
        """, kotlin: """
        val matchtarget_0 = enumFactory()
        if (matchtarget_0 !is E.Case2Case) {
            print("no")
            return
        }
        var s_0 = matchtarget_0.associated1
        print(s_0)
        """)
    }

    func testGuardCaseMultipleConditions() async throws {
        try await check(supportingSwift: """
        func enumFactory() -> E {
            return .case1
        }
        enum E {
            case case1
            case case2(Int, String)
        }
        """, swift: """
        guard case let .case2(i, s) = enumFactory(), i > 10 else {
            print("no")
            return
        }
        print(s)
        """, kotlin: """
        val matchtarget_0 = enumFactory()
        if (matchtarget_0 !is E.Case2Case) {
            print("no")
            return
        }
        val i_0 = matchtarget_0.associated0
        val s_0 = matchtarget_0.associated1
        if (i_0 <= 10) {
            print("no")
            return
        }
        print(s_0)
        """)
    }

    func testIfDefined() async throws {
        try await check(swift: """
        #if SKIP
        doSomething()
        #endif
        """, kotlin: """
        doSomething()
        """)

        try await check(swift: """
        #if !SKIP
        doSomething()
        #endif
        """, kotlin: """
        """)

        try await check(swift: """
        #if !SKIP
        doSomething()
        #else
        doSomethingElse()
        #endif
        """, kotlin: """
        doSomethingElse()
        """)

        try await check(swift: """
        #if os(iOS)
        doSomething()
        #endif
        #if os(Android)
        doSomethingElse()
        #endif
        """, kotlin: """
        doSomethingElse()
        """)

        try await check(swift: """
        #if DEBUG || SKIP
        doSomething()
        #else
        doSomethingElse()
        #endif
        """, kotlin: """
        doSomething()
        """)

        try await check(swift: """
        #if DEBUG && SKIP
        doSomething()
        #endif
        """, kotlin: """
        """)

        try await check(swift: """
        #if !DEBUG && SKIP
        doSomething()
        #endif
        """, kotlin: """
        doSomething()
        """)

        try await check(swift: """
        #if !SKIP
        doSomething()
        #endif
        """, kotlin: """
        """)

        try await check(swift: """
        #if !SKIP || os(Android)
        doSomething()
        #endif
        """, kotlin: """
        doSomething()
        """)

        try await check(swift: """
        #if !SKIP
        doSomething()
        #elif DEBUB
        doSomething2()
        #else
        doSomethingElse()
        #endif
        """, kotlin: """
        doSomethingElse()
        """)

        try await checkProducesMessage(swift: """
        #if SKIP || DEBUG && FOO
        doSomething()
        #endif
        """)

        try await checkProducesMessage(swift: """
        #if (os(Android) || DEBUG) && SKIP
        doSomething()
        #endif
        """)
    }

    func testIfDefinedCaseList() async throws {
        try await check(swift: """
        let x = { 1 }()
        switch x {
        case 0: return "zero"
        #if SKIP
        case 1: return "one"
        #else
        case 1: return "1"
        #endif
        case 2: return "two"
        #if !SKIP
        case 3: return "three"
        #endif
        default: return "other"
        }
        """, kotlin: """
        internal val x = { 1 }()
        when (x) {
            0 -> return "zero"
            1 -> return "one"
            2 -> return "two"
            else -> return "other"
        }
        """)
    }

    func testIfDefinedTrailingCalls() async throws {
        try await check(swift: """
        V().x()
        #if SKIP
            .y()
        #else
            .z()
        #endif
        """, kotlin: """
        V().x().y()
        """)

        try await check(swift: """
        V()
        #if !SKIP
            .x()
        #endif
        """, kotlin: """
        V()
        """)

        try await check(swift: """
        V().x()
        #if SKIP
            .a.b(a: 100).c
        #endif
            .d()
        """, kotlin: """
        V().x().a.b(a = 100).c
            .d()
        """)

        try await check(swift: """
        f(v: V()
            .opacity(1.0)
          #if DEBUG
            .border(Color.red)
          #else
            .border(Color.blue)
          #endif
        )
        """, kotlin: """
        f(v = V()
            .opacity(1.0).border(Color.blue))
        """)
    }

    func testUnknownAttributeRetention() async throws {
        try await checkProducesMessage(swift: """
        @Composable func f() {
        }
        """)

        try await check(swift: """
        #if SKIP
        @Composable func f() {
        }
        #endif
        """, kotlin: """
        @Composable
        internal fun f() = Unit
        """)

        try await checkProducesMessage(swift: """
        #if DEBUG
        #else
        @Composable func f() {
        }
        #endif
        """)

        try await check(swift: """
        #if !SKIP
        @Composable func g() {
        }
        #else
        @Composable func f() {
        }
        #endif
        """, kotlin: """
        @Composable
        internal fun f() = Unit
        """)

        try await check(swift: """
        #if SKIP
        @Composable("x", i = 100)
        func f() {
        }
        #endif
        """, kotlin: """
        @Composable("x", i = 100)
        internal fun f() = Unit
        """)
    }
}
