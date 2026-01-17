// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest

fileprivate extension String {
    /// Parity with Kotlin's `String.length`
    var length: Int { count }
}

/// A test case that verifies that transpilation are *not* working as hoped.
final class FeatureSupportTests: XCTestCase {
    func testExtendArrayShouldImportArray() async throws {
        // https://github.com/skiptools/skip/issues/134
        try await check(expectFailure: true, swift: """
        extension Array {
            func doSomething()
        }
        """, kotlin: """
        import skip.lib.Array

        internal fun Array.doSomething()
        """)
    }

    func testExtendSetShouldImportSet() async throws {
        // https://github.com/skiptools/skip/issues/134
        try await check(expectFailure: true, swift: """
        extension Set {
            func doSomething()
        }
        """, kotlin: """
        import skip.lib.Set

        internal fun Set.doSomething()
        """)
    }

    func testExtendCollectionShouldImportCollection() async throws {
        // https://github.com/skiptools/skip/issues/134
        try await check(expectFailure: true, swift: """
        extension Collection {
            func doSomething()
        }
        """, kotlin: """
        import skip.lib.Collection

        internal fun Collection.doSomething()
        """)
    }

    func testJetpackCompose() async throws {
        try await check(compiler: nil, swiftCode: {
            func JetpackCompose() {
                Card {
                    var expanded = remember { mutableStateOf(false) }
                    Column(Modifier.clickable { expanded.value = !expanded.value }) {
                        Image(painterResource(R.drawable.jetpack_compose))
                        AnimatedVisibility(expanded) {
                            Text(text: "Jetpack Compose", style: MaterialTheme.typography.bodyLarge)
                        }
                    }
                }
            }
            return ""
        }, kotlin: """
            fun JetpackCompose() {
                Card { ->
                    var expanded = remember { -> mutableStateOf(false) }
                    Column(Modifier.clickable { -> expanded.value = !expanded.value }) { ->
                        Image(painterResource(R.drawable.jetpack_compose))
                        AnimatedVisibility(expanded) { -> Text(text = "Jetpack Compose", style = MaterialTheme.typography.bodyLarge) }
                    }
                }
            }
            return ""
            """)

        try await check(expectMessages: true, compiler: nil, swiftCode: {
            class MyViewModel : ViewModel {
                let myProperty = mutableStateOf("Initial value")
            }
            return ""
        }, kotlin: """
            open class MyViewModel: ViewModel {
                val myProperty = mutableStateOf("Initial value")
            }
            return ""
            """)

        //@Observable
        try await check(swiftCode: {
            class Car {
               var name: String = ""
               var needsRepairs: Bool = false

               init(name: String, needsRepairs: Bool = false) {
                   self.name = name
                   self.needsRepairs = needsRepairs
               }
            }
            return ""
        }, kotlin: """
            open class Car {
                open var name: String = ""
                open var needsRepairs: Boolean = false
                constructor(name: String, needsRepairs: Boolean = false) {
                    this.name = name
                    this.needsRepairs = needsRepairs
                }
            }
            return ""
            """)

        // This is what it might look like if we converted @Swift.Observable to use mutableStateOf
        // https://developer.apple.com/documentation/Observation
        // https://developer.apple.com/documentation/observation/observable-swift.macro
        // https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro
        //
        // Note the @android.compose.Model annotation might have a better fit, but it is deprecated
        try await check(expectFailure: true, compiler: nil, swiftCode: {
            /* @Observable */ class Car {
               var name: String = ""
               var needsRepairs: Bool = false

               init(name: String, needsRepairs: Bool = false) {
                   self.name = name
                   self.needsRepairs = needsRepairs
               }
            }
            return ""
        }, kotlin: """
            data class Car {
                private var _name by remember { mutableStateOf("") }
                var name: String
                    get() = _name.value
                    set(newValue) {
                        _name.value = newValue
                    }
                private var _needsRepairs by remember { mutableStateOf(false) }
                var : Bool
                    get() = _needsRepairs.value
                    set(newValue) {
                        _needsRepairs.value = newValue
                    }

                constructor(name: String, needsRepairs: Boolean = false) {
                    this.name = name
                    this.needsRepairs = needsRepairs
                }
            }
            return ""
            """)

        /// Remember the value produced by calculation. calculation will only be evaluated during the composition. Recomposition will always return the value produced by composition.
        ///
        /// https://developer.android.com/reference/kotlin/androidx/compose/runtime/package-summary#remember(kotlin.Function0)
        func remember<T>(_ calculation: () -> T) -> T {
            return calculation()
        }

        /// Return a new MutableState initialized with the passed in value
        ///
        /// The MutableState class is a single value holder whose reads and writes are observed by Compose. Additionally, writes to it are transacted as part of the Snapshot system.
        /// https://developer.android.com/reference/kotlin/androidx/compose/runtime/package-summary#mutableStateOf(kotlin.Any,androidx.compose.runtime.SnapshotMutationPolicy)
        func mutableStateOf<T>(_ value: T) -> MutableState<T> {
            return MutableState(value: value)
        }

        struct MutableState<T> {
            var value: T
        }

        /// ViewModel is a class that is responsible for preparing and managing the data for an Activity or a Fragment. It also handles the communication of the Activity / Fragment with the rest of the application (e.g. calling the business logic classes).
        /// https://developer.android.com/reference/androidx/lifecycle/ViewModel
        class ViewModel {
        }

        // MARK: Composable Layouts
        // https://developer.android.com/jetpack/compose/layouts

        /// Component that represents an empty space layout, whose size can be defined using Modifier.width, Modifier.height and Modifier.size modifiers.
        /// https://developer.android.com/reference/kotlin/androidx/compose/foundation/layout/package-summary#Spacer(androidx.compose.ui.Modifier)
        func Spacer(_ modifier: Modifier) { }

        /// A layout composable that places its children in a horizontal sequence.
        /// https://developer.android.com/reference/kotlin/androidx/compose/foundation/layout/package-summary#Row(androidx.compose.ui.Modifier,androidx.compose.foundation.layout.Arrangement.Horizontal,androidx.compose.ui.Alignment.Vertical,kotlin.Function1)
        func Row(_ modifier: Modifier, _ content: () -> ()) { }

        /// A layout composable that places its children in a vertical sequence.
        /// https://developer.android.com/reference/kotlin/androidx/compose/foundation/layout/package-summary#Column(androidx.compose.ui.Modifier,androidx.compose.foundation.layout.Arrangement.Vertical,androidx.compose.ui.Alignment.Horizontal,kotlin.Function1)
        func Column(_ modifier: Modifier, _ content: () -> ()) { }

        /// A layout composable with content. The Box will size itself to fit the content, subject to the incoming constraints.
        /// https://developer.android.com/reference/kotlin/androidx/compose/foundation/layout/package-summary#Box(androidx.compose.ui.Modifier,androidx.compose.ui.Alignment,kotlin.Boolean,kotlin.Function1)
        func Box(_ modifier: Modifier, _ content: () -> ()) { }

        func Card(_ content: () -> ()) { }

        func Image(_ resource: PainterResource) { }

        func AnimatedVisibility(_ value: MutableState<Bool>, _ block: () -> ()) { }

        /// An ordered, immutable collection of modifier elements that decorate or add behavior to Compose UI elements. For example, backgrounds, padding and click event listeners decorate or add behavior to rows, text or buttons.
        /// https://developer.android.com/reference/kotlin/androidx/compose/ui/Modifier
        struct Modifier {
            static func clickable(_ block: () -> ()) -> Modifier {
                return Modifier()
            }
        }

        struct Text {
            let text: String
            let style: MaterialTheme.Typography.Value

            @discardableResult init(text: String, style: MaterialTheme.Typography.Value) {
                self.text = text
                self.style = style
            }
        }

        /// Create a Painter from an Android resource id
        /// https://developer.android.com/reference/kotlin/androidx/compose/ui/res/package-summary#painterResource(kotlin.Int)
        func painterResource(_ id: Int) -> PainterResource {
            return PainterResource()
        }

        struct PainterResource {
        }

        struct MaterialTheme {
            static var typography = Typography()

            struct Typography {
                let bodyLarge: Value = Value()
                struct Value { }
            }
        }

        struct R {
            struct drawable {
                static let jetpack_compose: Int = 0
            }
        }
    }

    func testCheckSwiftCompiledSource() async throws {
        try await check(swiftCode: {
            return "\(1 + 2)"
        }, kotlin: """
            return "${1 + 2}"
            """)
    }

    func testNamedParameterOverridesOuterDefinition() async throws {
        // the "a" part of the "a b: String" parameter is unused in Swift, but it acts as being locally declared in Kotlin and thus overrides the outer definition of "a".
        // These two functions thus return different values: "xy" vs. "yy"
        // There might not be an easy solution to this (and will cause confusing errors when the outer "a" and inner "a" are different types), so we may just need Skippy to disallow such name clashes.
        try await check(compiler: nil, swiftCode: {
            let a = "x"
            func f(a b: String) -> String {
                a + b
            }
            return f(a: "y")
        }, kotlin: """
            val a = "x"
            fun f(a: String): String {
                val b = a
                return a + b
            }
            return f(a = "y")
            """)
    }

    func testUnicodeCombiningCharacters() async throws {
        // "cafe" appending "COMBINING ACUTE ACCENT, U+0301" should still have `.count` of 4.
        // This will be tricky to get right, since Swift's count is built-in, but to get equivalent
        // behavior we'd need to use java.text.BreakIterator or java.text.StringCharacterIterator
        // to get the correct character count. We could, perhaps, have a `count`
        // implementation that does an initial check for combining characters, and if any are
        // detected, use the slow-track method for getting the count.
        try await check(expectFailure: true, compiler: nil, swiftCode: {
            var word = "cafe"
            word += "\u{301}"
            return "\(word.count)"
        }, kotlin: """
            var word = "cafe"
            word += "\\u0301"
            return "${word.count}"
            """)
    }

    /// Trying to reproduce `UUID(uuidString: "Invalid UUID")` in `TestUUID.swift` throwing a `NullReturnException`.
    /// But this works fine…
    func testInferredNilConstructor() async throws {
        try await check(swift: """
        class Foo {
            init?() {
                return nil
            }
        }

        let foo = Foo()
        assert(foo == nil)
        """, kotlin: """
        internal open class Foo {
            internal constructor() {
                throw NullReturnException()
            }
        }

        internal val foo = (try { Foo() } catch (_: NullReturnException) { null })
        assert(foo == null)
        """)
    }

    func testEnumRawValueKeywords() async throws {
        // The case match label is wrong for KeywordsEnum.null
        try await check(compiler: nil, swiftCode: {
            enum KeywordsEnum : Int {
                case null
                case string
                case boolean
                case object
                case `case`

                var index: Int {
                    switch self {
                    case .null:
                        return 0
                    case .string:
                        return 1
                    case .boolean:
                        return 2
                    case .object:
                        return 3
                    case .case:
                        return 4
                    }
                }
            }
            return ""
        }, kotlin: """
            enum class KeywordsEnum(override val rawValue: Int, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): RawRepresentable<Int> {
                null_(0),
                string(1),
                boolean(2),
                object_(3),
                case(4);
                val index: Int
                    get() {
                        when (this) {
                            KeywordsEnum.null_ -> return 0
                            KeywordsEnum.string -> return 1
                            KeywordsEnum.boolean -> return 2
                            KeywordsEnum.object_ -> return 3
                            KeywordsEnum.case -> return 4
                        }
                    }

                companion object {
                    fun init(rawValue: Int): KeywordsEnum? {
                        return when (rawValue) {
                            0 -> KeywordsEnum.null_
                            1 -> KeywordsEnum.string
                            2 -> KeywordsEnum.boolean
                            3 -> KeywordsEnum.object_
                            4 -> KeywordsEnum.case
                            else -> null
                        }
                    }
                }
            }

            fun KeywordsEnum(rawValue: Int): KeywordsEnum? = KeywordsEnum.init(rawValue = rawValue)
            return ""
            """)
    }


    func testEnumKeywords() async throws {
        // Postfix-underscored (e.g. "Object_") keyword name-derived case classes are do not use the escaped version when checking cases
        try await check(swiftCode: {
            enum KeywordsEnum {
                case null
                case string(String)
                case boolean(Bool)
                case object(Any)
                case `case`

                var index: Int {
                    switch self {
                    case .null:
                        return 0
                    case .string(_):
                        return 1
                    case .boolean(_):
                        return 2
                    case .object(_):
                        return 3
                    case .case:
                        return 4
                    }
                }
            }
            return ""
        }, kotlin: """
            sealed class KeywordsEnum {
                class NullCase: KeywordsEnum() {
                }
                class StringCase(val associated0: String): KeywordsEnum() {
                }
                class BooleanCase(val associated0: Boolean): KeywordsEnum() {
                }
                class ObjectCase(val associated0: Any): KeywordsEnum() {
                }
                class CaseCase: KeywordsEnum() {
                }
                val index: Int
                    get() {
                        when (this) {
                            is KeywordsEnum.NullCase -> return 0
                            is KeywordsEnum.StringCase -> return 1
                            is KeywordsEnum.BooleanCase -> return 2
                            is KeywordsEnum.ObjectCase -> return 3
                            is KeywordsEnum.CaseCase -> return 4
                        }
                    }
            
                companion object {
                    val null_: KeywordsEnum = NullCase()
                    fun string(associated0: String): KeywordsEnum = StringCase(associated0)
                    fun boolean(associated0: Boolean): KeywordsEnum = BooleanCase(associated0)
                    fun object_(associated0: Any): KeywordsEnum = ObjectCase(associated0)
                    val case: KeywordsEnum = CaseCase()
                }
            }
            return ""
            """)
    }

    func testInitNumberLiterals() async throws {
        // Kotlin doesn't seem to allow initializing non-Ints with literals without being explicit

        // see the very end of SkipFoundation/…/TestNSNumberBridging.swift for examples of number literals initializers we might want to support

        // error: the integer literal does not conform to the expected type Double
        try await check(expectFailure: true, compiler: nil, swiftCode: {
            var x: Int8
            var y: UInt32
            var z: Double

            x = 1
            y = 2
            z = 3
            _ = x
            _ = y
            _ = z
            return ""
        }, kotlin: """
            var x: Byte
            var y: UInt
            var z: Double
            x = 1
            y = 2
            z = 3
            x
            y
            z
            return ""
            """)
    }

    func testArrayOfDoubles() async throws {
        // error: type mismatch: inferred type is IntegerLiteralType[Int,Long,Byte,Short] but Double was expected
        try await check(compiler: nil, swiftCode: {
            let doubles: Array<Double> = [1,2,3,4]
            return "\(doubles)"
        }, kotlin: """
            import skip.lib.Array
            
            val doubles: Array<Double> = arrayOf(1, 2, 3, 4)
            return "${doubles}"
            """)
    }

    func testNestedSimpleEnumInFunction() async throws {
        // error: Skip does not support type declarations within functions. Consider making this an independent type
        // error: modifier 'enum' is not applicable to 'local class'
        try await check(expectFailure: true, swift: """
        class Foo {
            public func someFunction() {
                enum NestedEnum {
                    case case1, case2, case3
                }
            }
        }
        """, kotlin: """
        """)
    }

    /// 1.406 seconds
    func testInferPerf15() async throws {
        try await check(swiftCode: {
            func f(_ number: Int) -> String { "\(number)" }
            func f(_ string: String) -> Int { string.length }
            let x = f(f(f(f(f(f(f(f(f(f(f(f(f(f(f(88888888)))))))))))))))
            return x
        }, kotlin: """
            fun f(number: Int): String = "${number}"
            fun f(string: String): Int = string.length
            val x = f(f(f(f(f(f(f(f(f(f(f(f(f(f(f(88888888)))))))))))))))
            return x
            """)
    }

    func testCheckSwiftEnum() async throws {
        try await check(swiftCode: {
            enum EnumType {
                case a,
                     b,
                     c
            }
            return nil
        }, kotlin: """
            enum class EnumType {
                a,
                b,
                c;
            }
            return null
            """)
    }

    func testCheckSwiftFib() async throws {
        try await fibCheck(n: 2, expectFailure: false)
        try await fibCheck(n: 40, expectFailure: false)

        // 32-bit int overflow behavior
        // XCTAssertEqual failed: ("12586269025") is not equal to ("-298632863")
        //try await fibCheck(n: 50, expectFailure: true) // needs KOTLINC env variable set
    }

    func fibCheck(n fibIndex: Int, expectFailure: Bool) async throws {
        try await check(expectFailure: expectFailure, swiftCode: {
            func fibonacci(_ n: Int) -> Int {
                if n <= 1 {
                    return n
                }
                var a = 0, b = 1
                for _ in 2...n {
                    let c = a + b
                    a = b
                    b = c
                }
                return b
            }
            return "\(fibonacci(fibIndex))"
        }, kotlin: """
            fun fibonacci(n: Int): Int {
                if (n <= 1) {
                    return n
                }
                var a = 0
                var b = 1
                for (unusedbinding in 2..n) {
                    val c = a + b
                    a = b
                    b = c
                }
                return b
            }
            return "${fibonacci(\(fibIndex))}"
            """,
        fixup: { $0.replacingOccurrences(of: "fibIndex", with: "\(fibIndex)") }) // needed for source code comparison
    }


    func testCheckUnicodeString() async throws {
        // interestingly, the special case check fails on Linux
        #if !os(Linux)
        try await check(expectFailure: true, swiftCode: {
            let currencySpacing = "\u{00A0}"
            return "\(currencySpacing)"
        }, kotlin: """
            val currencySpacing = " "
            return "${currencySpacing}"
            """)
        #endif
    }
}
