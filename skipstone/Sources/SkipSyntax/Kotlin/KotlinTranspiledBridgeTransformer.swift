import Foundation

/// Generate transpiled Swift (Kotlin) to compiled Swift bridging code.
final class KotlinTranspiledBridgeTransformer: KotlinTransformer {
    private var swiftDefinitions: [SwiftDefinitions] = []
    private var lock = NSLock()

    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        guard !syntaxTree.isBridgeFile else {
            return
        }
        var localSwiftDefinitions: [SwiftDefinitions] = []
        syntaxTree.root.visit { node in
            if let variableDeclaration = node as? KotlinVariableDeclaration, variableDeclaration.role == .global, variableDeclaration.attributes.contains(directive: Directive.bridge) {
                addSwiftDefinitions(forGlobal: variableDeclaration, to: &localSwiftDefinitions, translator: translator)
                return .skip
            }
            return .recurse(nil)
        }
        if !localSwiftDefinitions.isEmpty {
            lock.lock()
            swiftDefinitions += localSwiftDefinitions
            lock.unlock()
        }
    }

    func apply(toSwiftBridge syntaxTree: SyntaxTree, translator: KotlinTranslator) -> Bool {
        guard !swiftDefinitions.isEmpty else {
            return false
        }
        // TODO: Imports
        let fileClassDeclarations = Set<String>(swiftDefinitions.compactMap {
            guard let declaration = $0.globalsClassDeclaration else {
                return nil
            }
            return "private let " + declaration.identifier + " = try! JClass(name: \"" + declaration.className + "\")"
        }).sorted()
        let fileClassStatements = fileClassDeclarations.map { RawStatement(sourceCode: $0) }

        let swiftStatements = swiftDefinitions.map { swiftDefinitionStatements(for: $0) }
        syntaxTree.root.statements += fileClassStatements + swiftStatements
        return true
    }

    private func addSwiftDefinitions(forGlobal variableDeclaration: KotlinVariableDeclaration, to swiftDefinitions: inout [SwiftDefinitions], translator: KotlinTranslator) {
        guard let type = variableDeclaration.checkBridgable(translator: translator) else {
            return
        }
        guard !addConstantDefinition(for: variableDeclaration, type: type, to: &swiftDefinitions, translator: translator) else {
            return
        }
        let globalsClassDeclaration = globalsClassDeclaration(translator: translator)

        let propertyName = variableDeclaration.propertyName
        var swift: [String] = []
        swift.append("var " + propertyName + ": " + type.description + " {")

        // Getter
        swift.append(1, "get {")
        swift.append(2, "let value_java: " + type.java.description + " = try! " + globalsClassDeclaration.identifier + ".getStatic(field: " + propertyName + "_fieldID)")
        swift.append(2, "return " + type.convertFromJava(value: "value_java"))
        swift.append(1, "}")

        // Setter
        if variableDeclaration.apiFlags.options.contains(.writeable) && variableDeclaration.modifiers.setVisibility != .private && variableDeclaration.modifiers.setVisibility != .fileprivate {
            swift.append(1, "set {")
            swift.append(2, "let value_java = " + type.convertToJava(value: "newValue"))
            swift.append(2, globalsClassDeclaration.identifier + ".setStatic(field: " + propertyName + "_fieldID, value: value_java)")
            swift.append(1, "}")
        }
        
        swift.append("}")
        swift.append("private let " + propertyName + "_fieldID = " + globalsClassDeclaration.identifier + ".getStaticFieldID(name: \"" + propertyName + "\", sig: \"" + type.jni + "\")!")

        let definitions = SwiftDefinitions(globalsClassDeclaration: globalsClassDeclaration, definitions: swift)
        swiftDefinitions.append(definitions)
    }

    private func addConstantDefinition(for variableDeclaration: KotlinVariableDeclaration, type: TypeSignature, to swiftDefinitions: inout [SwiftDefinitions], translator: KotlinTranslator) -> Bool {
        guard variableDeclaration.isLet, let value = variableDeclaration.value else {
            return false
        }
        var assignment: String? = nil
        switch value.type {
        case .booleanLiteral:
            if type == .bool, let literal = value as? KotlinBooleanLiteral {
                assignment = " = " + literal.literal.description
            }
        case .nullLiteral:
            assignment = ": " + type.description + " = nil"
        case .numericLiteral:
            if type.isNumeric, let literal = value as? KotlinNumericLiteral {
                assignment = ": " + type.description + " = " + literal.literal
            }
        case .stringLiteral:
            if type == .string, let stringLiteral = variableDeclaration.value as? KotlinStringLiteral, let swiftString = stringLiteral.swiftString, !stringLiteral.isMultiline {
                assignment = " = \"" + swiftString + "\""
            }
        default:
            if type.isNumeric, let functionCall = value as? KotlinFunctionCall, let literal = numericLiteral(from: functionCall) {
                assignment = ": " + type.description + " = " + literal.literal
            }
        }
        guard let assignment else {
            return false
        }
        let definition = variableDeclaration.modifiers.visibility.swift(suffix: " ") + "let " + variableDeclaration.propertyName + assignment
        swiftDefinitions.append(SwiftDefinitions(definitions: [definition]))
        return true
    }

    /// If this is a numeric literal cast - e.g. `Int64(<literal>)` - return the literal.
    private func numericLiteral(from functionCall: KotlinFunctionCall) -> KotlinNumericLiteral? {
        let arguments = functionCall.arguments
        guard arguments.count == 1, arguments[0].label == nil, let numberLiteral = arguments[0].value as? KotlinNumericLiteral else {
            return nil
        }
        let functionName: String
        if let identifier = functionCall.function as? KotlinIdentifier {
            functionName = identifier.name
        } else if let memberAccess = functionCall.function as? KotlinMemberAccess {
            guard let baseIdentifier = memberAccess.base as? KotlinIdentifier, baseIdentifier.name == "Swift" else {
                return nil
            }
            functionName = memberAccess.member
        } else {
            return nil
        }
        return TypeSignature.for(name: functionName, genericTypes: []).isNumeric ? numberLiteral : nil
    }

    private func swiftDefinitionStatements(for swiftDefinitions: SwiftDefinitions) -> RawStatement {
        let sourceCode = swiftDefinitions.definitions.joined(separator: "\n")
        return RawStatement(sourceCode: sourceCode)
    }

    private func globalsClassDeclaration(translator: KotlinTranslator) -> (identifier: String, className: String) {
        let file = translator.syntaxTree.source.file
        var identifier = file.name
        let ext = file.extension
        if !ext.isEmpty {
            identifier = String(identifier.dropLast(ext.count + 1))
        }
        identifier += "Kt"
        let className: String
        if let packageName = translator.packageName {
            className = packageName + "." + identifier
        } else {
            className = identifier
        }
        return (identifier + "_fileClass", className)
    }
}

private struct SwiftDefinitions {
    let globalsClassDeclaration: (identifier: String, className: String)?
    let definitions: [String]

    init(globalsClassDeclaration: (String, String)? = nil, definitions: [String]) {
        self.globalsClassDeclaration = globalsClassDeclaration
        self.definitions = definitions
    }
}

extension Array where Element == String {
    fileprivate mutating func append(_ indentation: Indentation, _ value: String) {
        self.append(indentation.description + value)
    }
}
