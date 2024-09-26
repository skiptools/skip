import Foundation

/// Generate transpiled Swift (Kotlin) to compiled Swift bridging code.
final class KotlinTranspiledBridgeTransformer: KotlinTransformer {
    private var swiftDefinitions: [SwiftDefinition] = []
    private var globalsJavaClasses: Set<JavaClassRef> = []
    private var lock = NSLock()

    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        guard !syntaxTree.isBridgeFile, translator.codebaseInfo != nil else {
            return
        }
        var localSwiftDefinitions: [SwiftDefinition] = []
        var localGlobalsJavaClasses:  Set<JavaClassRef> = []
        syntaxTree.root.visit { node in
            if let variableDeclaration = node as? KotlinVariableDeclaration, variableDeclaration.role == .global {
                if variableDeclaration.attributes.contains(directive: Directive.bridge) {
                    addSwiftDefinitions(forGlobal: variableDeclaration, to: &localSwiftDefinitions, globalsJavaClasses: &localGlobalsJavaClasses, translator: translator)
                }
                return .skip
            } else if let functionDeclaration = node as? KotlinFunctionDeclaration, functionDeclaration.role == .global {
                if functionDeclaration.attributes.contains(directive: Directive.bridge) {
                    addSwiftDefinitions(forGlobal: functionDeclaration, to: &localSwiftDefinitions, globalsJavaClasses: &localGlobalsJavaClasses, translator: translator)
                }
                return .skip
            } else if let classDeclaration = node as? KotlinClassDeclaration {
                if classDeclaration.attributes.contains(directive: Directive.bridge) {
                    addSwiftDefinitions(for: classDeclaration, to: &localSwiftDefinitions, translator: translator)
                }
                return .recurse(nil)
            } else {
                return .recurse(nil)
            }
        }
        if !localSwiftDefinitions.isEmpty {
            lock.lock()
            swiftDefinitions += localSwiftDefinitions
            globalsJavaClasses.formUnion(localGlobalsJavaClasses)
            lock.unlock()
        }
    }

    func swiftBridgeOutput(translator: KotlinTranslator) -> OutputNode? {
        guard !swiftDefinitions.isEmpty else {
            return nil
        }
        // TODO: Imports
        let globalsJavaClasses = self.globalsJavaClasses
        return SwiftDefinition(children: swiftDefinitions) { output, indentation, children in
            globalsJavaClasses.map(\.description).sorted().forEach {
                output.append(indentation).append($0).append("\n")
            }
            children.forEach { output.append($0, indentation: indentation) }
        }
    }

    private func addSwiftDefinitions(forGlobal variableDeclaration: KotlinVariableDeclaration, to swiftDefinitions: inout [SwiftDefinition], globalsJavaClasses: inout Set<JavaClassRef>, translator: KotlinTranslator) {
        guard let type = variableDeclaration.checkBridgable(translator: translator) else {
            return
        }
        guard !addConstantDefinition(for: variableDeclaration, type: type, to: &swiftDefinitions, translator: translator) else {
            return
        }
        let classRef = globalsJavaClass(translator: translator)
        globalsJavaClasses.insert(classRef)

        let swift = swift(for: variableDeclaration, type: type, targetIdentifier: classRef.identifier, classIdentifier: classRef.identifier, fieldIdentifier: "Java_" + variableDeclaration.propertyName + "_fieldID")
        swiftDefinitions.append(SwiftDefinition(statement: variableDeclaration, swift: swift))
    }

    private func addSwiftDefinitions(for variableDeclaration: KotlinVariableDeclaration, to swiftDefinitions: inout [SwiftDefinition], translator: KotlinTranslator) {
        guard variableDeclaration.modifiers.visibility != .private && variableDeclaration.modifiers.visibility != .fileprivate && !variableDeclaration.attributes.contains(directive: Directive.nobridge) else {
            return
        }
        guard let type = variableDeclaration.checkBridgable(translator: translator) else {
            return
        }
        guard !addConstantDefinition(for: variableDeclaration, type: type, to: &swiftDefinitions, translator: translator) else {
            return
        }

        let swift = swift(for: variableDeclaration, type: type, targetIdentifier: "Java_peer", classIdentifier: "Java_class", fieldIdentifier: "Java_" + variableDeclaration.propertyName + "_fieldID")
        swiftDefinitions.append(SwiftDefinition(statement: variableDeclaration, swift: swift))
    }

    private func swift(for variableDeclaration: KotlinVariableDeclaration, type: TypeSignature, targetIdentifier: String, classIdentifier: String, fieldIdentifier: String) -> [String] {
        var swift: [String] = []
        let propertyName = variableDeclaration.propertyName
        let visibility = variableDeclaration.modifiers.visibility.swift(suffix: " ")
        swift.append(visibility + "var " + propertyName + ": " + type.description + " {")

        // Getter
        let getType = variableDeclaration.role == .global ? "getStatic" : "get"
        let callField = variableDeclaration.role == .global ? fieldIdentifier : "Self." + fieldIdentifier
        swift.append(1, "get {")
        swift.append(2, [
            "let value_java: " + type.java.description + " = try! " + targetIdentifier + "." + getType + "(field: " + callField  + ")",
            "return " + type.convertFromJava(value: "value_java")
        ])
        swift.append(1, "}")

        // Setter
        if variableDeclaration.apiFlags.options.contains(.writeable) && variableDeclaration.modifiers.setVisibility != .private && variableDeclaration.modifiers.setVisibility != .fileprivate {
            let setVisibility: String
            if variableDeclaration.modifiers.setVisibility < variableDeclaration.modifiers.visibility {
                setVisibility = variableDeclaration.modifiers.setVisibility.swift(suffix: " ")
            } else {
                setVisibility = ""
            }
            let setType = variableDeclaration.role == .global ? "setStatic" : "set"
            swift.append(1, setVisibility + "set {")
            swift.append(2, [
                "let value_java = " + type.convertToJava(value: "newValue"),
                targetIdentifier + "." + setType + "(field: " + callField + ", value: value_java)"
            ])
            swift.append(1, "}")
        }
        swift.append("}")

        let declarationType = variableDeclaration.role == .global ? "let " : "static let "
        let getFieldIDType = variableDeclaration.role == .global ? "getStaticFieldID" : "getFieldID"
        let fieldID = "private " + declarationType + fieldIdentifier + " = " + classIdentifier + "." + getFieldIDType + "(name: \"" + propertyName + "\", sig: \"" + type.jni + "\")!"
        swift.append(fieldID)
        return swift
    }

    private func addConstantDefinition(for variableDeclaration: KotlinVariableDeclaration, type: TypeSignature, to swiftDefinitions: inout [SwiftDefinition], translator: KotlinTranslator) -> Bool {
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
        let swift = variableDeclaration.modifiers.visibility.swift(suffix: " ") + "let " + variableDeclaration.propertyName + assignment
        swiftDefinitions.append(SwiftDefinition(statement: variableDeclaration, swift: [swift]))
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

    private func addSwiftDefinitions(forGlobal functionDeclaration: KotlinFunctionDeclaration, to swiftDefinitions: inout [SwiftDefinition], globalsJavaClasses: inout Set<JavaClassRef>, translator: KotlinTranslator) {
        guard functionDeclaration.checkBridgable(translator: translator) else {
            return
        }

        let classRef = globalsJavaClass(translator: translator)
        globalsJavaClasses.insert(classRef)

        let swift = swift(for: functionDeclaration, targetIdentifier: classRef.identifier, classIdentifier: classRef.identifier, methodIdentifier: "Java_" + functionDeclaration.name + "_methodID")
        swiftDefinitions.append(SwiftDefinition(statement: functionDeclaration, swift: swift))
    }

    private func addSwiftDefinitions(for functionDeclaration: KotlinFunctionDeclaration, to swiftDefinitions: inout [SwiftDefinition], translator: KotlinTranslator) {
        guard functionDeclaration.modifiers.visibility != .private && functionDeclaration.modifiers.visibility != .fileprivate && !functionDeclaration.attributes.contains(directive: Directive.nobridge) else {
            return
        }
        guard functionDeclaration.checkBridgable(translator: translator) else {
            return
        }

        let swift = swift(for: functionDeclaration, targetIdentifier: "Java_peer", classIdentifier: "Java_class", methodIdentifier: "Java_" + functionDeclaration.name + "_methodID")
        swiftDefinitions.append(SwiftDefinition(statement: functionDeclaration, swift: swift))
    }

    private func swift(for functionDeclaration: KotlinFunctionDeclaration, targetIdentifier: String, classIdentifier: String, methodIdentifier: String) -> [String] {
        var swift: [String] = []

        let visibility = functionDeclaration.modifiers.visibility.swift(suffix: " ")
        let parameterString = functionDeclaration.parameters.map(\.swift).joined(separator: ", ")
        let returnString = functionDeclaration.returnType == .void ? "" : " -> " + functionDeclaration.returnType.description
        swift.append(visibility + "func " + functionDeclaration.name + "(" + parameterString + ")" + returnString + " {")

        var javaParameterNames: [String] = []
        for p in functionDeclaration.parameters {
            let name = p.internalLabel + "_java"
            javaParameterNames.append(name)
            swift.append(1, "let " + name + " = " + p.declaredType.convertToJava(value: p.internalLabel) + ".toJavaParameter()")
        }

        let callType = functionDeclaration.role == .global ? "callStatic" : "call"
        let callMethod = functionDeclaration.role == .global ? methodIdentifier : "Self." + methodIdentifier
        let call = "try! " + targetIdentifier + "." + callType + "(method: " + callMethod + ", [" + javaParameterNames.joined(separator: ", ") + "])"
        if functionDeclaration.returnType == .void {
            swift.append(1, call)
        } else {
            swift.append(1, "let f_return_java: " + functionDeclaration.returnType.java.description + " = " + call)
            swift.append(1, "return " + functionDeclaration.returnType.convertFromJava(value: "f_return_java"))
        }
        swift.append("}")

        let declarationType = functionDeclaration.role == .global ? "let " : "static let "
        let getType = functionDeclaration.role == .global ? "getStaticMethodID" : "getMethodID"
        let methodID = "private " + declarationType + methodIdentifier + " = " + classIdentifier + "." + getType + "(name: \"" + functionDeclaration.name + "\", sig: \"" + functionDeclaration.functionType.jni + "\")!"
        swift.append(methodID)
        return swift
    }

    private func addSwiftDefinitions(for classDeclaration: KotlinClassDeclaration, to swiftDefinitions: inout [SwiftDefinition], translator: KotlinTranslator) {
        guard classDeclaration.checkBridgable(translator: translator) else {
            return
        }
        let classRef = typeJavaClass(classDeclaration, translator: translator)

        let visibility = classDeclaration.modifiers.visibility.swift(suffix: " ")
        var swift: [String] = []
        swift.append(visibility + "class " + classDeclaration.name + " {")

        swift.append(1, "private static let Java_class = try! JClass(name: \"" + classRef.className + "\")")
        swift.append(1, "let Java_peer: JObject")
        swift.append("")
        swift.append(1, [
            "init(Java_ptr: JavaObjectPointer) {",
            "    Java_peer = JObject(Java_ptr)",
            "}"
        ])
        swift.append("")

        if !classDeclaration.members.contains(where: { $0.type == .constructorDeclaration }) {
            swift.append(1, [
                visibility + "init() {",
                "    let ptr = try! Self.Java_class.create(ctor: Self.Java_init_methodID, [])",
                "    Java_peer = JObject(ptr)",
                "}",
                "private static let Java_init_methodID = Java_class.getMethodID(name: \"<init>\", sig: \"()V\")!"
            ])
            swift.append("")
        }

        var memberDefinitions: [SwiftDefinition] = []
        for member in classDeclaration.members {
            if let variableDeclaration = member as? KotlinVariableDeclaration {
                addSwiftDefinitions(for: variableDeclaration, to: &memberDefinitions, translator: translator)
            } else if let functionDeclaration = member as? KotlinFunctionDeclaration {
                addSwiftDefinitions(for: functionDeclaration, to: &memberDefinitions, translator: translator)
            }
        }

        let definition = SwiftDefinition(statement: classDeclaration, children: memberDefinitions) { output, indentation, children in
            swift.forEach { output.append(indentation).append($0).append("\n") }
            let childIndentation = indentation.inc()
            children.forEach { output.append($0, indentation: childIndentation) }
            output.append(indentation).append("}\n")
        }
        swiftDefinitions.append(definition)
    }

    private func globalsJavaClass(translator: KotlinTranslator) -> JavaClassRef {
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
        return JavaClassRef(identifier: "Java_" + identifier, className: className)
    }

    private func typeJavaClass(_ classDeclaration: KotlinClassDeclaration, translator: KotlinTranslator) -> JavaClassRef {
        let className: String
        if let packageName = translator.packageName {
            className = packageName + "." + classDeclaration.name
        } else {
            className = classDeclaration.name
        }
        return JavaClassRef(identifier: "Java_class", className: className)
    }
}

private struct JavaClassRef: Hashable, CustomStringConvertible {
    let identifier: String
    let className: String

    var description: String {
        return "private let " + identifier + " = try! JClass(name: \"" + className + "\")"
    }
}
