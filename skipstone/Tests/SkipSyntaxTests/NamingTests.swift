@testable import SkipSyntax
import XCTest

final class NamingTests: XCTestCase {
    func testPackageNaming() throws {
        XCTAssertEqual("net.scape", KotlinTranslator.packageName(forModule: "NetScape"))
        XCTAssertEqual("my.module", KotlinTranslator.packageName(forModule: "MyModule"))
        XCTAssertEqual("my.mmodule", KotlinTranslator.packageName(forModule: "MyMModule"))
        XCTAssertEqual("my.mmmmodule", KotlinTranslator.packageName(forModule: "MyMMMModule"))
        XCTAssertEqual("com.package.name.some.module", KotlinTranslator.packageName(forModule: "ComPackageNameSomeModule"))
        XCTAssertEqual("urlutility.library", KotlinTranslator.packageName(forModule: "URLUtilityLibrary"))
        XCTAssertEqual("my.module", KotlinTranslator.packageName(forModule: "My"), "single-word modules should add package suffix")
    }

    /// Checks that Kotlin's "hard" keywords are escaped by appending an undescore to the end of the name.
    func testCheckReservedKeywords() async throws {
        try await check(swiftCode: {
            class KeywordHolder {
                let null = "ABC"
                let null_ = "DEF"
                var interface: Int = 2
                var this = 1.234
                var `enum`: EnumType = EnumType.null

                func packageFunction(package: String) { }
                func objectArgFunction(object o: EnumType) { }
            }
            enum EnumType {
                case null,
                     interface,
                     this
            }
            let holder = KeywordHolder()
            assert(holder.null == "ABC")
            holder.interface += 1
            holder.enum = EnumType.this
            holder.this += holder.this
            assert(holder.this == 2.468)
            holder.packageFunction(package: "ABC")
            holder.objectArgFunction(object: EnumType.this)
            return holder.null
        }, kotlin: """
            open class KeywordHolder {
                val null_ = "ABC"
                val null__ = "DEF"
                open var interface_: Int = 2
                open var this_ = 1.234
                open var enum: EnumType = EnumType.null_
                fun packageFunction(package_: String) = Unit
                fun objectArgFunction(object_: EnumType) = Unit
            }
            enum class EnumType {
                null_,
                interface_,
                this_;
            }
            val holder = KeywordHolder()
            assert(holder.null_ == "ABC")
            holder.interface_ += 1
            holder.enum = EnumType.this_
            holder.this_ += holder.this_
            assert(holder.this_ == 2.468)
            holder.packageFunction(package_ = "ABC")
            holder.objectArgFunction(object_ = EnumType.this_)
            return holder.null_
            """)
    }

    func testReservedTypeNames() async throws {
        try await checkProducesMessage(swift: """
        struct Unit {
            var x = 1
        }
        """)

        try await checkProducesMessage(swift: """
        struct Short {
            var x = 1
        }
        """)
    }

    func testMutableStructTypeVariableKeyword() async throws {
        try await check(swift: """
        struct S {
            var object: S
        """, kotlin: """
        @Suppress("MUST_BE_INITIALIZED")
        internal class S: MutableStruct {
            internal var object_: S
                get() = field.sref({ this.object_ = it })
                set(newValue) {
                    @Suppress("NAME_SHADOWING") val newValue = newValue.sref()
                    willmutate()
                    field = newValue
                    didmutate()
                }

            constructor(object_: S) {
                this.object_ = object_
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = S(object_)
        }
        """)
    }

    func testSwiftModuleQualifiedType() async throws {
        try await check(supportingSwift: """
        extension Swift.Int {
            static let myValue = 0
        }
        """, swift: """
        func f(a: Int, b: Swift.Int) {
            let b1 = a == .myValue
            let b2 = b == .myValue
            let b3 = a == Swift.Int.myValue
        }
        """, kotlin: """
        internal fun f(a: Int, b: Int) {
            val b1 = a == Int.myValue
            val b2 = b == Int.myValue
            val b3 = a == kotlin.Int.myValue
        }
        """)
    }

    func testModuleQualifiedNames() async throws {
        let moduleOne = try CodebaseInfo.ModuleExport(of: codebaseInfo(moduleName: "ModuleOne", swift: """
        public class A {
            public func f() -> Swift.Int {
                return 0
            }
        }
        public func g(i: Swift.Int) -> Swift.Int {
            return 0
        }
        """))
        let moduleTwo = try CodebaseInfo.ModuleExport(of: codebaseInfo(moduleName: "ModuleTwo", swift: """
        public class B {
            public func f() -> Swift.String {
                return ""
            }
        }
        public func g(i: Swift.Int) -> Swift.String {
            return ""
        }
        """))

        try await check(dependentModules: [moduleOne, moduleTwo], supportingSwift: """
        extension Int {
            static var myValue: Int {
                return 0
            }
        }
        extension String {
            static var myValue: String {
                return ""
            }
        }
        """, swift: """
        import ModuleOne
        import ModuleTwo

        class C: ModuleTwo.B {
        }

        func f(obj: ModuleOne.A) -> Int {
            return obj.f()
        }
        func f(obj: ModuleTwo.B) -> String {
            return obj.f()
        }
        func g() {
            let b1 = ModuleOne.g(i: 0) == .myValue
            let b2 = ModuleTwo.g(i: 0) == .myValue

            let a = ModuleOne.A()
            let b3 = a.f() == .myValue
            let c = C()
            let b4 = c.f() == .myValue

            let b5 = f(obj: ModuleOne.A()) == .myValue
            let b6 = f(obj: ModuleTwo.B()) == .myValue
        }
        """, kotlin: """
        import module.one.*
        import module.two.*

        internal open class C: module.two.B() {

            companion object: module.two.B.CompanionClass() {
            }
        }

        internal fun f(obj: module.one.A): Int = obj.f()
        internal fun f(obj: module.two.B): String = obj.f()
        internal fun g() {
            val b1 = module.one.g(i = 0) == Int.myValue
            val b2 = module.two.g(i = 0) == String.myValue

            val a = module.one.A()
            val b3 = a.f() == Int.myValue
            val c = C()
            val b4 = c.f() == String.myValue

            val b5 = f(obj = module.one.A()) == Int.myValue
            val b6 = f(obj = module.two.B()) == String.myValue
        }
        """)
    }


    func testExplicitImportKotlinBuiltinNamedType() async throws {
        let moduleOne = try CodebaseInfo.ModuleExport(of: codebaseInfo(moduleName: "ModuleOne", swift: """
        public class List {
        }
        """))

        try await check(dependentModules: [moduleOne], swift: """
        import ModuleOne

        func f(l: List) {
        }
        """, kotlin: """
        import module.one.*
        import module.one.List

        internal fun f(l: List) = Unit
        """)
    }

    private func codebaseInfo(moduleName: String, swift: String) throws -> CodebaseInfo {
        let srcFile = try tmpFile(named: "Source_\(moduleName).swift", contents: swift)
        let source = Source(file: Source.FilePath(path: srcFile.path), content: swift)
        let syntaxTree = SyntaxTree(source: source)
        let codebaseInfo = CodebaseInfo(moduleName: moduleName)
        codebaseInfo.gather(from: syntaxTree)
        codebaseInfo.prepareForUse()
        return codebaseInfo
    }
}





