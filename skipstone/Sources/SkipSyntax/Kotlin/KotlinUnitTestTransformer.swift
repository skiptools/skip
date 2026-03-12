// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

/// Convert `XCTestCase` test functions and Swift Testing `@Test` functions to JUnit test functions.
///
/// Handles two styles of test declaration:
/// 1. **XCTest**: Classes inheriting from `XCTestCase` with `test`-prefixed methods
/// 2. **Swift Testing**: Functions annotated with `@Test` and types annotated with `@Suite`
///
/// In both cases, JUnit `@Test` annotation is applied.
/// Async test functions are wrapped with coroutine test dispatchers.
///
/// - Seealso: `SkipUnit/XCTest.kt`
final class KotlinUnitTestTransformer: KotlinTransformer {
    /// Swift source attributes gathered during the gather phase.
    /// Maps source file paths to sets of function names that have `@Test` attributes.
    private var swiftTestingFunctions: [Source.FilePath: Set<String>] = [:]
    /// Types annotated with `@Suite` in Swift source.
    private var swiftTestingSuites: [Source.FilePath: Set<String>] = [:]

    static let testRunnerAnnotation: String? = nil // was: "@org.junit.runner.RunWith(androidx.test.ext.junit.runners.AndroidJUnit4::class)"

    func gather(from syntaxTree: SyntaxTree) {
        var testFunctions: Set<String> = []
        var suiteTypes: Set<String> = []

        for statement in syntaxTree.root.statements {
            gatherTestAttributes(from: statement, testFunctions: &testFunctions, suiteTypes: &suiteTypes)
        }

        if !testFunctions.isEmpty {
            swiftTestingFunctions[syntaxTree.source.file] = testFunctions
        }
        if !suiteTypes.isEmpty {
            swiftTestingSuites[syntaxTree.source.file] = suiteTypes
        }
    }

    /// Recursively gather `@Test` and `@Suite` attributes from the Swift AST.
    private func gatherTestAttributes(from statement: Statement, testFunctions: inout Set<String>, suiteTypes: inout Set<String>) {
        if let funcDecl = statement as? FunctionDeclaration {
            if funcDecl.attributes.contains(.test) {
                testFunctions.insert(funcDecl.name)
            }
        }
        if let typeDecl = statement as? TypeDeclaration {
            if typeDecl.attributes.contains(.suite) {
                suiteTypes.insert(typeDecl.name)
            }
            for member in typeDecl.members {
                gatherTestAttributes(from: member, testFunctions: &testFunctions, suiteTypes: &suiteTypes)
            }
        }
        if let codeBlock = statement as? CodeBlock {
            for child in codeBlock.statements {
                gatherTestAttributes(from: child, testFunctions: &testFunctions, suiteTypes: &suiteTypes)
            }
        }
    }

    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> [KotlinTransformerOutput] {
        guard let codebaseInfo = translator.codebaseInfo else {
            return []
        }
        let sourceFile = syntaxTree.source.file
        let testFuncNames = swiftTestingFunctions[sourceFile] ?? []

        var importPackages: Set<String> = []
        syntaxTree.root.visit(ifSkipBlockContent: syntaxTree.isBridgeFile) {
            visit($0, codebaseInfo: codebaseInfo, testFuncNames: testFuncNames, importPackages: &importPackages)
        }
        syntaxTree.dependencies.imports.formUnion(importPackages)
        return []
    }

    private func visit(_ node: KotlinSyntaxNode, codebaseInfo: CodebaseInfo.Context, testFuncNames: Set<String>, importPackages: inout Set<String>) -> VisitResult<KotlinSyntaxNode> {
        if let functionDeclaration = node as? KotlinFunctionDeclaration {
            if let owningClass = functionDeclaration.parent as? KotlinClassDeclaration {
                // Check for XCTest-style test functions (name-based detection)
                let isXCTest = Self.isXCTestFunction(functionDeclaration, owningClass: owningClass, codebaseInfo: codebaseInfo)
                // Check for Swift Testing @Test functions (attribute-based detection)
                let isSwiftTesting = testFuncNames.contains(functionDeclaration.name)

                if isXCTest || isSwiftTesting {
                    if functionDeclaration.apiFlags.options.contains(.async) {
                        transformAsyncTest(functionDeclaration: functionDeclaration, owningClass: owningClass, importPackages: &importPackages)
                    } else {
                        functionDeclaration.annotations += ["@Test"]
                    }
                    if let testRunnerAnnotation = Self.testRunnerAnnotation {
                        if !owningClass.annotations.contains(testRunnerAnnotation) {
                            owningClass.annotations += [testRunnerAnnotation]
                        }
                    }
                    // For Swift Testing @Suite types that don't extend XCTestCase,
                    // make them implement the XCTestCase interface for assertion access
                    if isSwiftTesting && !isXCTest {
                        ensureXCTestCaseConformance(owningClass)
                    }
                    return .skip
                }
            } else if let owningCodeBlock = functionDeclaration.parent as? KotlinCodeBlock,
                      functionDeclaration.role == .global,
                      testFuncNames.contains(functionDeclaration.name) {
                // Freestanding @Test function — wrap in a generated test class
                wrapFreestandingTestFunction(functionDeclaration, in: owningCodeBlock, importPackages: &importPackages)
                return .skip
            }
        }
        return .recurse(nil)
    }

    /// Ensures the given class implements the `XCTestCase` interface if it doesn't already.
    /// This is needed for Swift Testing `@Suite` types that don't inherit from XCTestCase
    /// but still need access to the assertion methods defined on the interface.
    private func ensureXCTestCaseConformance(_ classDeclaration: KotlinClassDeclaration) {
        let hasXCTestCase = classDeclaration.inherits.contains { supertype in
            if case .named(let name, _) = supertype, name == "XCTestCase" {
                return true
            }
            return false
        }
        if !hasXCTestCase {
            classDeclaration.inherits.append(.named("XCTestCase", []))
        }
    }

    /// Wraps a freestanding `@Test` function in a generated JUnit test class.
    /// e.g., `@Test func addition() { ... }` becomes:
    /// ```
    /// class AdditionTests: XCTestCase {
    ///     @Test fun addition() { ... }
    /// }
    /// ```
    private func wrapFreestandingTestFunction(_ functionDeclaration: KotlinFunctionDeclaration, in codeBlock: KotlinCodeBlock, importPackages: inout Set<String>) {
        // Generate a class name from the function name (e.g., "addition" -> "AdditionTests")
        let className = functionDeclaration.name.prefix(1).uppercased() + functionDeclaration.name.dropFirst() + "Tests"

        // Create a wrapper class (final, not open)
        let classDeclaration = KotlinClassDeclaration(name: className, signature: .named(className, []), declarationType: .classDeclaration)
        classDeclaration.modifiers = Modifiers(isFinal: true)
        classDeclaration.inherits = [.named("XCTestCase", [])]
        if let testRunnerAnnotation = Self.testRunnerAnnotation {
            classDeclaration.annotations = [testRunnerAnnotation]
        }
        classDeclaration.extras = functionDeclaration.extras

        // Move the function into the class
        if let index = codeBlock.statements.firstIndex(where: { $0 === functionDeclaration }) {
            functionDeclaration.role = .member
            functionDeclaration.extras = nil
            if functionDeclaration.apiFlags.options.contains(.async) {
                transformAsyncTest(functionDeclaration: functionDeclaration, owningClass: classDeclaration, importPackages: &importPackages)
            } else {
                functionDeclaration.annotations += ["@Test"]
            }
            classDeclaration.members = [functionDeclaration]
            functionDeclaration.parent = classDeclaration

            codeBlock.statements[index] = classDeclaration
            classDeclaration.parent = codeBlock
            classDeclaration.assignParentReferences()
        }
    }

    private func transformAsyncTest(functionDeclaration: KotlinFunctionDeclaration, owningClass: KotlinClassDeclaration, importPackages: inout Set<String>) {
        importPackages.insert("kotlinx.coroutines.*")
        importPackages.insert("kotlinx.coroutines.test.*")

        // Create a wrapper @Test function that will call the original async function
        let testFunctionDeclaration = KotlinFunctionDeclaration(name: "run" + functionDeclaration.name)
        testFunctionDeclaration.annotations += [
            "@OptIn(ExperimentalCoroutinesApi::class)",
            "@Test"
        ]
        testFunctionDeclaration.extras = .singleNewline

        // This wrapper code sets up and tears down the required async test environment
        let lines = [
            "val dispatcher = StandardTestDispatcher()",
            "Dispatchers.setMain(dispatcher)",
            "try {",
            "    runTest { withContext(Dispatchers.Main) { \(functionDeclaration.name)() } }",
            "} finally {",
            "    Dispatchers.resetMain()",
            "}"
        ]
        let statements = lines.map { KotlinRawStatement(sourceCode: $0) }
        let codeBlock = KotlinCodeBlock(statements: statements)
        testFunctionDeclaration.body = codeBlock

        if let testIndex = owningClass.members.firstIndex(where: { $0 === functionDeclaration }) {
            owningClass.members.insert(testFunctionDeclaration, at: testIndex)
            testFunctionDeclaration.parent = owningClass
            testFunctionDeclaration.assignParentReferences()
        }
    }

    /// Checks whether a function is an XCTest-style test function (name starts with "test",
    /// no parameters, non-static, owning class inherits from XCTestCase).
    private static func isXCTestFunction(_ functionDeclaration: KotlinFunctionDeclaration, owningClass: KotlinClassDeclaration, codebaseInfo: CodebaseInfo.Context) -> Bool {
        guard functionDeclaration.name.hasPrefix("test") && !functionDeclaration.isStatic && functionDeclaration.role != .global else {
            return false
        }
        if !functionDeclaration.parameters.isEmpty {
            return false
        }
        let signatures = codebaseInfo.global.inheritanceChainSignatures(forNamed: owningClass.signature)
        guard let owningType = signatures.last else {
            return false
        }
        let infos = codebaseInfo.typeInfos(forNamed: owningType)
        // check for whether the containing class inherits from `XCTestCase`
        return infos.contains { $0.inherits.contains { $0.isNamed("XCTestCase", moduleName: "XCTest", generics: []) } }
    }
}
