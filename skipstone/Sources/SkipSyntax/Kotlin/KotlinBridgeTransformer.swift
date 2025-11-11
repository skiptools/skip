import Foundation

/// Available bridge options.
///
/// - Seealso: `JConvertibleOptions` in `SkipBridge`.
public struct KotlinBridgeOptions: OptionSet {
    public static let kotlincompat = KotlinBridgeOptions(rawValue: 1 << 0)

    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Create a set from a list of strings, e.g. `["kotlincompat"]`.
    public static func parse(_ strings: [String]) -> KotlinBridgeOptions {
        var options: KotlinBridgeOptions = []
        for string in strings {
            switch string {
            case "kotlincompat":
                options.insert(.kotlincompat)
            default:
                break
            }
        }
        return options
    }
}

/// Generate bridging code and transformations.
public final class KotlinBridgeTransformer: KotlinTransformer {
    public static var testSkipAndroidBridge = false // For testing

    private let options: KotlinBridgeOptions

    public init(options: KotlinBridgeOptions) {
        self.options = options
    }

    public init() {
        self.options = []
    }

    public func gather(from syntaxTree: SyntaxTree) {
        // Add attributes marking bridged types so that they're recorded in our codebase info
        let isBridgeFile = syntaxTree.isBridgeFile
        syntaxTree.root.visit { node in
            if let typeDeclaration = node as? TypeDeclaration, typeDeclaration.type != .extensionDeclaration {
                let isNativeIfSkipBlock = isBridgeFile && typeDeclaration.isInIfSkipBlock()
                if isBridging(attributes: typeDeclaration.attributes, visibility: typeDeclaration.modifiers.visibility, autoBridge: isNativeIfSkipBlock ? .internal : syntaxTree.autoBridge) {
                    if isBridgeFile && !isNativeIfSkipBlock {
                        typeDeclaration.attributes.attributes.append(.bridgeToKotlin)
                    } else {
                        typeDeclaration.attributes.attributes.append(.bridgeToSwift)
                    }
                }
                return .recurse(nil)
            } else if let typealiasDeclaration = node as? TypealiasDeclaration {
                let isNativeIfSkipBlock = isBridgeFile && typealiasDeclaration.isInIfSkipBlock()
                if isBridging(attributes: typealiasDeclaration.attributes, visibility: typealiasDeclaration.modifiers.visibility, autoBridge: isNativeIfSkipBlock ? .internal : syntaxTree.autoBridge) {
                    if isBridgeFile && !isNativeIfSkipBlock {
                        typealiasDeclaration.attributes.attributes.append(.bridgeToKotlin)
                    } else {
                        typealiasDeclaration.attributes.attributes.append(.bridgeToSwift)
                    }
                }
                return .skip
            } else if node is VariableDeclaration || node is FunctionDeclaration {
                return .skip
            } else {
                return .recurse(nil)
            }
        }
    }

    public func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> [KotlinTransformerOutput] {
        var bridgeToKotlinOutputs: [KotlinTransformerOutput] = []
        if syntaxTree.isBridgeFile, let visitor = KotlinBridgeToKotlinVisitor(for: syntaxTree, options: options, translator: translator) {
            bridgeToKotlinOutputs = visitor.visit()
        }
        var bridgeToSwiftOutputs: [KotlinTransformerOutput] = []
        if let visitor = KotlinBridgeToSwiftVisitor(for: syntaxTree, options: options, translator: translator) {
            // Combine any bridging Swift definitions
            for output in visitor.visit() {
                if let index = bridgeToKotlinOutputs.firstIndex(where: { $0.file == output.file }), let swiftDefinition1 = bridgeToKotlinOutputs[index].node as? SwiftDefinition, let swiftDefinition2 = output.node as? SwiftDefinition {
                    bridgeToKotlinOutputs[index].node = swiftDefinition1.combined(with: swiftDefinition2)
                } else {
                    bridgeToSwiftOutputs.append(output)
                }
            }
        }
        return bridgeToKotlinOutputs + bridgeToSwiftOutputs
    }
}

// MARK - Bridge support

/// Used in Swift code generation.
struct SwiftDefinition: OutputNode {
    var sourceFile: Source.FilePath?
    var sourceRange: Source.Range?
    var children: [SwiftDefinition] = []
    var appendTo: (OutputGenerator, Indentation, [SwiftDefinition]) -> Void = { output, indentation, children in
        children.forEach { $0.append(to: output, indentation: indentation) }
    }

    init(statement: SourceDerived? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil, children: [SwiftDefinition] = [], appendTo: ((OutputGenerator, Indentation, [SwiftDefinition]) -> Void)? = nil) {
        self.sourceFile = sourceFile ?? statement?.sourceFile
        self.sourceRange = sourceRange ?? statement?.sourceRange
        self.children = children
        if let appendTo {
            self.appendTo = appendTo
        }
    }

    init(statement: SourceDerived? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil, swift: [String]) {
        self = .init(statement: statement, sourceFile: sourceFile, sourceRange: sourceRange) { output, indentation, _ in
            swift.forEach { output.append(indentation).append($0).append("\n") }
        }
    }

    func combined(with other: SwiftDefinition) -> SwiftDefinition {
        var combined = SwiftDefinition()
        combined.sourceFile = sourceFile ?? other.sourceFile
        combined.sourceRange = sourceRange ?? other.sourceRange
        combined.children = [self, other]
        return combined
    }

    func leadingTrivia(indentation: Indentation) -> String {
        return ""
    }

    func trailingTrivia(indentation: Indentation) -> String {
        return ""
    }

    func append(to output: OutputGenerator, indentation: Indentation) {
        appendTo(output, indentation, children)
    }
}

/// Utilities for declaring a JNI class reference.
struct JavaClassRef {
    let identifier: String
    let className: String
    let isFileClass: Bool
    let generics: [TypeSignature]

    init(for signature: TypeSignature, packageName: String?) {
        let className: String
        if let packageName {
            className = packageName.replacing(".", with: "/") + "/" + signature.name.replacing(".", with: "$")
        } else {
            className = signature.name.replacing(".", with: "$")
        }
        self.identifier = "Java_class"
        self.className = className
        self.isFileClass = false
        self.generics = signature.generics
    }

    init(forFileName fileName: String, packageName: String?) {
        var identifier = fileName
        if let extensionIndex = fileName.lastIndex(of: ".") {
            let extensionCount = fileName.suffix(from: extensionIndex).count
            identifier = String(identifier.dropLast(extensionCount))
        }
        identifier += "Kt"
        let className: String
        if let packageName {
            className = packageName.replacing(".", with: "/") + "/" + identifier
        } else {
            className = identifier
        }
        self.identifier = "Java_" + identifier
        self.className = className
        self.isFileClass = true
        self.generics = []
    }

    func declaration(visibility: Modifiers.Visibility? = nil, declarationType: StatementType? = nil) -> String {
        return declareStaticLet(identifier, ofType: "JClass", visibility: visibility, in: isFileClass ? nil : .named(className, generics), declarationType: declarationType, value: "try! JClass(name: \"\(className)\")")
    }
}

/// Code to create a static variable in the given class to store the given value.
func declareStaticLet(_ identifier: String, ofType: String, visibility: Modifiers.Visibility? = nil, in signature: TypeSignature? = nil, declarationType: StatementType? = nil, value: String) -> String {
    let visibilityString = (visibility ?? .private).swift(suffix: " ")
    if declarationType == .protocolDeclaration || declarationType == .extensionDeclaration || signature?.generics.isEmpty == false {
        return "nonisolated \(visibilityString)static var \(identifier): \(ofType) { \(value) }"
    } else {
        return "\(signature == nil ? "\(visibilityString)let " : "nonisolated \(visibilityString)static let ")\(identifier) = \(value)"
    }
}

/// `cdecl` function information.
struct CDeclFunction {
    let name: String
    let cdecl: String
    let signature: TypeSignature
    let body: [String]

    /// Return the `cdecl` declarations for a given external function name.
    static func declaration(for statement: KotlinStatement, isCompanion: Bool, name: String, translator: KotlinTranslator) -> (cdecl: String, cdeclFunctionName: String) {
        var cdeclPrefix = "Java_"
        if let package = translator.packageName {
            cdeclPrefix += package.cdeclEscaped.replacing(".", with: "_") + "_"
        }
        let typeName: String
        let cdeclTypeName: String
        if let classDeclaration = statement.owningTypeDeclaration as? KotlinClassDeclaration {
            typeName = classDeclaration.signature.withGenerics([]).description.replacing(".", with: "$")
            if isCompanion {
                cdeclTypeName = typeName + "$Companion"
            } else {
                cdeclTypeName = typeName
            }
        } else {
            var file = translator.syntaxTree.source.file
            file.extension = ""
            typeName = file.name + "Kt"
            cdeclTypeName = typeName
        }
        return (cdeclPrefix + cdeclTypeName.cdeclEscaped + "_" + name.cdeclEscaped, typeName + "_" + name)
    }

    func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(indentation).append("@_cdecl(\"").append(cdecl).append("\")\n")
        output.append(indentation).append("public func ").append(name).append("(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer")
        for parameter in signature.parameters {
            output.append(", _")
            if let label = parameter.label {
                output.append(" ").append(label)
            }
            output.append(": ").append(parameter.type.description)
        }
        output.append(")")
        if signature.returnType != .void {
            output.append(" -> ").append(signature.returnType.description)
        }
        output.append(" {\n")

        let bodyIndentation = indentation.inc()
        body.forEach { output.append(bodyIndentation).append($0).append("\n") }

        output.append(indentation).append("}\n")
    }
}

extension CodebaseInfo {
    /// Whether this module depends on SkipAndroidBridge.
    var needsAndroidBridge: Bool {
        // Exclude our own SkipFuse modules, which should not generate their own Bundle, UserDefaults, etc support code.
        // Doing so lead sto duplicate dex errors
        return dependentModules.contains { $0.moduleName == "SkipAndroidBridge" } && moduleName?.hasPrefix("SkipFuse") != true && moduleName != "SkipSwiftUI"
    }
}

extension Source.FilePath {
    /// Return the JNI class name for this file in the given package.
    func jniClassName(packageName: String?) -> String {
        let name = self.name.dropLast(self.extension.count) + "Kt"
        guard let packageName, !packageName.isEmpty else {
            return String(name)
        }
        return packageName + "." + name
    }
}

extension String {
    private static let backtickEscapingIdentifiers: Set<String> = [
        "Any", "_", "as", "associatedtype", "await", "break", "case", "catch", "class", "convenience", "continue", "default", "defer", "deinit", "didSet", "do", "dynamic", "else", "enum", "extension", "fallthrough", "false", "fileprivate", "final", "for", "func", "get", "guard", "if", "import", "infix", "init", "inout", "internal", "indirect", "is", "lazy", "let", "left", "macro", "mutating", "nil", "nonmutating", "open", "operator", "optional", "override", "postfix", "precedence", "prefix", "private", "protocol", "Protocol", "public", "required", "rethrows", "return", "right", "self", "Self", "set", "some", "static", "struct", "subscript", "super", "switch", "throw", "throws", "true", "try", "typealias", "Type", "unowned", "var", "weak", "while", "willSet"
    ]

    /// Add backticks if this string is a Swift identifier that needs escaping.
    var addingBacktickEscapingIfNeeded: String {
        return Self.backtickEscapingIdentifiers.contains(self) ? "`\(self)`" : self
    }

    /// Escape special characters for use in a `@_cdecl` declaration.
    ///
    /// - Warning: Assumes this is an identifier string that does not contain illegal identifier characters like `;`
    var cdeclEscaped: String {
        // TODO: Unicode chars
        return replacing("_", with: "_1").replacing("$", with: "_00024")
    }

    /// Return this property name as the equivalent Java getter.
    var getterName: String {
        guard !isEmpty else {
            return self
        }
        // Special case for "isX", which Kotlin uses as-is
        guard count < 3 || !hasPrefix("is") || !self[index(self.startIndex, offsetBy: 2)].isUppercase else {
            return self
        }
        let capitalizedPropertyName = (first?.uppercased() ?? "") + dropFirst()
        return "get\(capitalizedPropertyName)"
    }

    /// Return this property name as the equivalent Java setter.
    var setterName: String {
        guard !isEmpty else {
            return self
        }
        // Special case for "isX", which Kotlin maps to "setX"
        guard count < 3 || !hasPrefix("is") || !self[index(self.startIndex, offsetBy: 2)].isUppercase else {
            return "set\(self.dropFirst(2))"
        }
        let capitalizedPropertyName = (first?.uppercased() ?? "") + dropFirst()
        return "set\(capitalizedPropertyName)"
    }
}

extension KotlinBridgeOptions {
    /// Convert these options into the source code to create the equivalent `JConvertibleOptions`.
    var jconvertibleOptions: String {
        if contains(.kotlincompat) {
            return "[.kotlincompat]"
        }
        return "[]"
    }
}

extension TypeSignature {
    static let anyDynamicObject: TypeSignature = .named("AnyDynamicObject", [])
    static let skipUIView: TypeSignature = .module("SkipUI", .named("View", []))
    static let skipUIViewModifier: TypeSignature = .module("SkipUI", .named("ViewModifier", []))
    static let skipUIToolbarContent: TypeSignature = .module("SkipUI", .named("ToolbarContent", []))
    static let skipSwiftUIView: TypeSignature = .module("SkipSwiftUI", .named("View", []))
    static let skipSwiftUIBridging: TypeSignature = .module("SkipSwiftUI", .named("SkipUIBridging", []))
    static let javaObjectPointer: TypeSignature = .named("JavaObjectPointer", [])
    static let javaString: TypeSignature = .named("JavaString", [])
    static func swiftObjectPointer(kotlin: Bool) -> TypeSignature {
        return kotlin ? .named("skip.bridge.SwiftObjectPointer", []) : .named("SwiftObjectPointer", [])
    }
    static let nothing: TypeSignature = .named("Nothing", [])
    static func javaVoid(kotlin: Bool) -> TypeSignature {
        return kotlin ? .module("java.lang", .named("Void", [])) : .void
    }

    enum SwiftUIType : Equatable {
        case none
        case view
        case viewModifier
        case toolbarContent
    }

    /// Whether this is a SwiftUI view, view modifier, or toolbar content.
    var swiftUIType: SwiftUIType {
        if isNamed("View", moduleName: "SwiftUI", generics: []) || isNamed("View", moduleName: "SkipUI", generics: []) || isNamed("View", moduleName: "SkipSwiftUI", generics: []) {
            return .view
        } else if isNamed("ViewModifier", moduleName: "SwiftUI", generics: []) || isNamed("ViewModifier", moduleName: "SkipUI", generics: []) || isNamed("ViewModifier", moduleName: "SkipSwiftUI", generics: []) {
            return .viewModifier
        } else if isNamed("ToolbarContent", moduleName: "SwiftUI", generics: []) || isNamed("ToolbarContent", moduleName: "SkipUI", generics: []) || isNamed("ToolbarContent", moduleName: "SkipSwiftUI", generics: []) {
            return .toolbarContent
        } else {
            return .none
        }
    }

    /// The generated native type used when bridging a protocol with unknown implementation.
    var protocolBridgeImpl: TypeSignature {
        let moduleName = self.moduleName
        return withExistentialMode(.none).withModuleName(nil).withName(name.replacing(".", with: "_") + "_BridgeImpl").withModuleName(moduleName)
    }

    /// Whether this is a generated native type used when bridging a protocol with unknown implementation.
    var isProtocolBridgeImpl: Bool {
        return name.hasSuffix("_BridgeImpl")
    }

    /// The local name of the type-erased version of a generic class.
    var typeErasedClass: TypeSignature {
        let moduleName = self.moduleName
        return withModuleName(nil).withGenerics([]).withName(name.replacing(".", with: "_") + "_TypeErased").withModuleName(moduleName)
    }

    /// Return the `@_cdecl` function equivalent of this type.
    func cdecl(strategy: Bridgable.Strategy, options: KotlinBridgeOptions) -> TypeSignature {
        switch self {
        case .function:
            return .javaObjectPointer
        case .int:
            return .int32
        case .optional(let type):
            return type == .string ? .optional(.javaString) : .optional(.javaObjectPointer)
        case .string:
            return .javaString
        case .tuple:
            return .javaObjectPointer
        case .uint:
            return .uint32
        case .unwrappedOptional(let type):
            return type.cdecl(strategy: strategy, options: options)
        default:
            return strategy == .direct ? self : .javaObjectPointer
        }
    }

    /// Return code that converts the given value of this type to its `@_cdecl` function form.
    func convertToCDecl(value: String, strategy: Bridgable.Strategy, options: KotlinBridgeOptions) -> String {
        switch self.asOptional(false) {
        case .function(let parameters, _, _, _):
            let converted = "SwiftClosure\(parameters.count).javaObject(for: \(value), options: \(options.jconvertibleOptions))"
            return isOptional ? converted : converted + "!"
        case .int:
            if isOptional {
                return value + ".toJavaObject(options: \(options.jconvertibleOptions))"
            } else {
                return "Int32(\(value))"
            }
        case .string:
            let converted = value + ".toJavaObject(options: \(options.jconvertibleOptions))"
            return isOptional ? converted : converted + "!"
        case .tuple:
            let converted = "SwiftTuple.javaObject(for: \(value), options: \(options.jconvertibleOptions))"
            return isOptional ? converted : converted + "!"
        case .uint:
            if isOptional {
                return value + ".toJavaObject(options: \(options.jconvertibleOptions))"
            } else {
                return "UInt32(\(value))"
            }
        case .unwrappedOptional(let type):
            return type.convertToCDecl(value: value, strategy: strategy, options: options)
        default:
            if strategy == .direct && !isOptional {
                return value
            } else if strategy == .protocol || strategy == .unknown {
                let converted = "AnyBridging.toJavaObject(\(value), options: \(options.jconvertibleOptions))"
                return isOptional ? converted : converted + "!"
            } else if strategy == .error {
                let converted = "JThrowable.toThrowable(\(value), options: \(options.jconvertibleOptions))"
                return isOptional ? converted : converted + "!"
            } else if strategy == .view {
                let converted = "(\(value).Java_viewOrEmpty as! JConvertible).toJavaObject(options: \(options.jconvertibleOptions))"
                return isOptional ? converted : converted + "!"
            } else {
                let converted = value + ".toJavaObject(options: \(options.jconvertibleOptions))"
                return isOptional ? converted : converted + "!"
            }
        }
    }

    /// Return code that converts the given value of our `@_cdecl` function type back to this type.
    func convertFromCDecl(value: String, strategy: Bridgable.Strategy, options: KotlinBridgeOptions) -> String {
        switch strategy {
        case .unknown:
            let converted = "AnyBridging.fromJavaObject(\(value), options: \(options.jconvertibleOptions))"
            return castOptionalAny(converted)
        case .polymorphic:
            let converted = "AnyBridging.fromJavaObject(\(value), toBaseType: \(self.asOptional(false)).self, options: \(options.jconvertibleOptions))"
            return converted + (isOptional ? "" : "!")
        case .protocol:
            let converted = "AnyBridging.fromJavaObject(\(value), options: \(options.jconvertibleOptions)) { \(self.protocolBridgeImpl.description).fromJavaObject(\(value), options: \(options.jconvertibleOptions)) as Any }"
            return castOptionalAny(converted)
        case .error:
            let converted = "JThrowable.toError(\(value), options: \(options.jconvertibleOptions))"
            return converted + (isOptional ? "" : "!")
        case .view:
            return "JavaBackedView(\(value))"
        default:
            break
        }

        switch self.asOptional(false) {
        case .function(let parameters, let signature, let apiFlags, var attributes):
            let converted = "SwiftClosure\(parameters.count).closure(forJavaObject: \(value), options: \(options.jconvertibleOptions))"
            if let filtered = attributes?.attributes.filter({ $0.kind != .escaping }) {
                attributes = Attributes(attributes: filtered)
            }
            return "\(converted)\(isOptional ? "" : "!") as \(TypeSignature.function(parameters, signature, apiFlags, attributes))"
        case .int:
            if isOptional {
                return "Int?.fromJavaObject(\(value), options: \(options.jconvertibleOptions))"
            } else {
                return "Int(\(value))"
            }
        case .string:
            return description + ".fromJavaObject(\(value), options: \(options.jconvertibleOptions))"
        case .tuple:
            let converted = "SwiftTuple.tuple(forJavaObject: \(value), options: \(options.jconvertibleOptions))"
            return "\(converted)\(isOptional ? "" : "!") as \(self)"
        case .uint:
            if isOptional {
                return "UInt?.fromJavaObject(\(value), options: \(options.jconvertibleOptions))"
            } else {
                return "UInt(\(value))"
            }
        case .unwrappedOptional(let type):
            return type.convertFromCDecl(value: value, strategy: strategy, options: options)
        default:
            if strategy == .direct && !isOptional {
                return value
            } else {
                return description + ".fromJavaObject(\(value), options: \(options.jconvertibleOptions))"
            }
        }
    }

    private func castOptionalAny(_ value: String) -> String {
        switch self {
        case .optional(.any):
            return value
        case .any:
            return value + "!"
        default:
            if self.existentialMode == .some {
                return value + " as! \(self.withExistentialMode(.any))"
            } else {
                return value + " as! \(self)"
            }
        }
    }

    /// Return the Java equivalent of this type.
    func java(strategy: Bridgable.Strategy, options: KotlinBridgeOptions) -> TypeSignature {
        switch self {
        case .function:
            return .javaObjectPointer
        case .int:
            return .int32
        case .optional:
            return .optional(.javaObjectPointer)
        case .tuple:
            return .javaObjectPointer
        case .uint:
            return .uint32
        case .unwrappedOptional(let type):
            return type.java(strategy: strategy, options: options)
        default:
            return strategy == .direct ? self : .javaObjectPointer
        }
    }

    /// Return code that converts the given value of this type to its Java form.
    func convertToJava(value: String, strategy: Bridgable.Strategy, options: KotlinBridgeOptions) -> String {
        return convertToJava(value: value, strategy: strategy, optionsString: options.jconvertibleOptions)
    }

    /// Return code that converts the given value of this type to its Java form.
    func convertToJava(value: String, strategy: Bridgable.Strategy, optionsString: String) -> String {
        switch self.asOptional(false) {
        case .function(let parameters, _, _, _):
            let converted = "SwiftClosure\(parameters.count).javaObject(for: \(value), options: \(optionsString))"
            return isOptional ? converted : converted + "!"
        case .int:
            return isOptional ? value : "Int32(\(value))"
        case .tuple:
            let converted = "SwiftTuple.javaObject(for: \(value), options: \(optionsString))"
            return isOptional ? converted : converted + "!"
        case .uint:
            return isOptional ? value : "UInt32(\(value))"
        case .unwrappedOptional(let type):
            return type.convertToJava(value: value, strategy: strategy, optionsString: optionsString)
        default:
            if strategy == .direct {
                return value
            } else if strategy == .protocol || strategy == .unknown {
                let converted = "AnyBridging.toJavaObject(\(value), options: \(optionsString))"
                return isOptional ? converted : converted + "!"
            } else if strategy == .error {
                let converted = "JThrowable.toThrowable(\(value), options: \(optionsString))"
                return isOptional ? converted : converted + "!"
            } else if strategy == .view {
                let converted = "(\(value).Java_viewOrEmpty as! JConvertible).toJavaObject(options: \(optionsString))"
                return isOptional ? converted : converted + "!"
            } else {
                let converted = value + ".toJavaObject(options: \(optionsString))"
                return isOptional ? converted : converted + "!"
            }
        }
    }

    /// Return code that converts the given value of our Java type back to this type.
    func convertFromJava(value: String, strategy: Bridgable.Strategy, options: KotlinBridgeOptions) -> String {
        switch strategy {
        case .unknown:
            let converted = "AnyBridging.fromJavaObject(\(value), options: \(options.jconvertibleOptions))"
            return castOptionalAny(converted)
        case .polymorphic:
            let converted = "AnyBridging.fromJavaObject(\(value), toBaseType: \(self.asOptional(false)).self, options: \(options.jconvertibleOptions))"
            return converted + (isOptional ? "" : "!")
        case .protocol:
            let converted = "AnyBridging.fromJavaObject(\(value), options: \(options.jconvertibleOptions)) { \(self.protocolBridgeImpl.description).fromJavaObject(\(value), options: \(options.jconvertibleOptions)) as Any }"
            return castOptionalAny(converted)
        case .error:
            let converted = "JThrowable.toError(\(value), options: \(options.jconvertibleOptions))"
            return converted + (isOptional ? "" : "!")
        case .view:
            let converted = "JavaBackedView(\(value))"
            return converted + (isOptional ? "" : "!")
        default:
            break
        }

        switch self {
        case .function:
            return convertClosureFromJava(value: value, isOptional: false, options: options)
        case .int:
            return "Int(\(value))"
        case .optional(let type):
            switch type {
            case .function:
                return type.convertClosureFromJava(value: value, isOptional: true, options: options)
            case .tuple:
                return "SwiftTuple.tuple(forJavaObject: \(value), options: \(options.jconvertibleOptions))"
            default:
                return description + ".fromJavaObject(\(value), options: \(options.jconvertibleOptions))"
            }
        case .tuple:
            return "SwiftTuple.tuple(forJavaObject: \(value), options: \(options.jconvertibleOptions))!"
        case .uint:
            return "UInt(\(value))"
        case .unwrappedOptional(let type):
            return type.convertFromJava(value: value, strategy: strategy, options: options)
        default:
            if strategy == .direct {
                return value
            } else {
                return description + ".fromJavaObject(\(value), options: \(options.jconvertibleOptions))"
            }
        }
    }

    private func convertClosureFromJava(value: String, isOptional: Bool, options: KotlinBridgeOptions) -> String {
        let parametersString = (0..<parameters.count).map { "p\($0)" }.joined(separator: ", ")
        let parametersInString = parametersString.isEmpty ? parametersString : parametersString + " in "
        let handleNil = isOptional ? "\(value) == nil ? nil : " : ""
        return "\(handleNil){ let closure_swift = JavaBackedClosure<\(returnType)>(\(value)\(isOptional ? "!" : ""), options: \(options.jconvertibleOptions)); return { \(parametersInString)try! closure_swift.invoke(\(parametersString)) } }()"
    }

    /// Return the JNI signature of this type.
    func jni(options: KotlinBridgeOptions, isFunctionDeclaration: Bool = false, isPartialMember: Bool = false) -> String {
        switch self {
        case .any:
            return "Ljava/lang/Object;"
        case .anyObject:
            return "Ljava/lang/Object;"
        case .array:
            if options.contains(.kotlincompat) {
                return "Lkotlin/collections/List;"
            } else {
                return "Lskip/lib/Array;"
            }
        case .bool:
            return "Z"
        case .character:
            return "C"
        case .composition:
            return "Ljava/lang/Object;"
        case .dictionary:
            if options.contains(.kotlincompat) {
                return "Lkotlin/collections/Map;"
            } else {
                return "Lskip/lib/Dictionary;"
            }
        case .double:
            return "D"
        case .existential(_, let type):
            return type.jni(options: options)
        case .float:
            return "F"
        case .function(let parameters, let returnType, _, _):
            if isFunctionDeclaration {
                let parametersJNI = parameters.map { $0.type.jni(options: options) }.joined(separator: "")
                return "(" + parametersJNI + ")" + returnType.jni(options: options)
            } else {
                return "Lkotlin/jvm/functions/Function\(parameters.count);"
            }
        case .int, .uint:
            return "I"
        case .int8, .uint8:
            return "B"
        case .int16, .uint16:
            return "S"
        case .int32, .uint32:
            return "I"
        case .int64, .uint64:
            return "J"
        case .int128, .uint128:
            return "Ljava/math/BigInteger;"
        case .member(let parent, let type):
            var parentJNI = parent.jni(options: options, isPartialMember: true)
            if parentJNI.hasSuffix(";") {
                parentJNI = String(parentJNI.dropFirst().dropLast())
            }
            var typeJNI = type.jni(options: options, isPartialMember: true)
            if typeJNI.hasSuffix(";") {
                typeJNI = String(typeJNI.dropFirst().dropLast())
            }
            guard !isPartialMember else {
                return parentJNI + "$" + typeJNI
            }

            // Package-qualified Java types might end up modeled as members rather than modules
            // Detect members with lowercase paths and uppercase names
            let tokens = parentJNI.split(separator: "$") + typeJNI.split(separator: "$")
            var combined = tokens[0]
            var hasType = false
            for i in 1..<tokens.count {
                if !hasType && tokens[i - 1].first?.isLowercase == true && !tokens[i - 1].contains("/") {
                    combined.append("/")
                } else {
                    hasType = true
                    combined.append("$")
                }
                combined += tokens[i]
            }
            return translateSpecialCaseJNITypes("L\(combined);")
        case .metaType:
            return "Ljava/lang/Class;"
        case .module(let name, let type):
            let typeName = type.jni(options: options)
            if typeName.hasPrefix("L") && typeName.hasSuffix(";") {
                let packageName = KotlinTranslator.packageName(forModule: name).replacing(".", with: "/")
                return translateSpecialCaseJNITypes("L" + packageName + "/" + typeName.dropFirst())
            } else {
                return typeName
            }
        case .named(let name, _):
            if isNamed("AnyHashable", moduleName: "Swift", generics: []) {
                return "Ljava/lang/Object;"
            }
            return translateSpecialCaseJNITypes("L" + name.replacing(".", with: "/") + ";")
        case .none:
            return "Ljava/lang/Object;"
        case .optional(let type):
            switch type {
            case .bool:
                return "Ljava/lang/Boolean;"
            case .character:
                return "Ljava/lang/Character;"
            case .double:
                return "Ljava/lang/Double;"
            case .float:
                return "Ljava/lang/Float;"
            case .int:
                return "Ljava/lang/Integer;"
            case .int8:
                return "Ljava/lang/Byte;"
            case .int16:
                return "Ljava/lang/Short;"
            case .int32:
                return "Ljava/lang/Integer;"
            case .int64:
                return "Ljava/lang/Long;"
            case .uint:
                return "Lkotlin/UInt;"
            case .uint8:
                return "Lkotlin/UByte;"
            case .uint16:
                return "Lkotlin/UShort;"
            case .uint32:
                return "Lkotlin/UInt;"
            case .uint64:
                return "Lkotlin/ULong;"
            default:
                return type.jni(options: options)
            }
        case .range:
            return "Ljava/lang/Object;"
        case .set:
            if options.contains(.kotlincompat) {
                return "Lkotlin/collections/Set;"
            } else {
                return "Lskip/lib/Set;"
            }
        case .string:
            return "Ljava/lang/String;"
        case .tuple(_, let types):
            if options.contains(.kotlincompat) && types.count == 2 {
                return "Lkotlin/Pair;"
            } else if options.contains(.kotlincompat) && types.count == 3 {
                return "Lkotlin/Triple;"
            } else {
                return "Lskip/lib/Tuple" + types.count.description + ";"
            }
        case .typealiased(_, let type):
            return type.jni(options: options)
        case .unwrappedOptional(let type):
            return type.jni(options: options)
        case .void:
            return "V"
        }
    }

    private func translateSpecialCaseJNITypes(_ jni: String) -> String {
        // Some common Kotlin types map to different JNI types
        switch jni {
        case "Lkotlin/ByteArray;":
            return "[B"
        case "Lkotlin/collections/Collection;":
            return "Ljava/util/Collection;"
        case "Lkotlin/collections/Map;":
            return "Ljava/util/Map;"
        case "Lkotlin/collections/List;":
            return "Ljava/util/List;"
        case "Lkotlin/collections/Set;":
            return "Ljava/util/Set;"
        case "Lkotlin/Throwable;":
            return "Ljava/lang/Throwable;"
        case "Lkotlin/Error;":
            return "Ljava/lang/Error;"
        case "Lkotlin/Exception;":
            return "Ljava/lang/Exception;"
        case "Lkotlin/RuntimeException;":
            return "Ljava/lang/RuntimeException;"
        case "Lkotlin/Comparable;":
            return "Ljava/lang/Comparable;"
        case "Lkotlin/CharSequence;":
            return "Ljava/lang/CharSequence;"
        case "Lkotlin/Number;":
            return "Ljava/lang/Number;"
        case "Lkotlin/Cloneable;":
            return "Ljava/lang/Cloneable;"
        default:
            return jni
        }
    }
}

extension Modifiers {
    func swift(isNoOverride: Bool = false, suffix: String = "") -> String {
        var string = isNonisolated ? "nonisolated" : ""
        let visibilityString = visibility.swift()
        if !visibilityString.isEmpty {
            if !string.isEmpty {
                string += " "
            }
            string += visibilityString
        }
        if isStatic {
            if !string.isEmpty {
                string += " "
            }
            string += "static"
        } else if isMutating {
            if !string.isEmpty {
                string += " "
            }
            string += "mutating"
        }
        if !isNoOverride && isOverride {
            if !string.isEmpty {
                string += " "
            }
            string += "override"
        }
        return string.isEmpty ? "" : string + suffix
    }
}

extension Modifiers.Visibility {
    func swift(suffix: String = "") -> String {
        switch self {
        case .private:
            return "private" + suffix
        case .public:
            return "public" + suffix
        case .fileprivate:
            return "fileprivate" + suffix
        case .open:
            return "open" + suffix
        default:
            return ""
        }
    }
}

extension Generics {
    /// Remove generic constraints involving unbridged types and map to Kotlin types.
    func compactMapBridgable(direction: Bridgable.Direction, options: KotlinBridgeOptions, codebaseInfo: CodebaseInfo.Context) -> Generics {
        let entries = self.entries.map {
            let inherits = $0.inherits.compactMap { compactMapBridgable($0, direction: direction, options: options, codebaseInfo: codebaseInfo) }
            return Generic(name: $0.name, inherits: inherits, whereEqual: compactMapBridgable($0.whereEqual, direction: direction, options: options, codebaseInfo: codebaseInfo))
        }
        return Generics(entries: entries)
    }

    private func compactMapBridgable(_ type: TypeSignature?, direction: Bridgable.Direction, options: KotlinBridgeOptions, codebaseInfo: CodebaseInfo.Context) -> TypeSignature? {
        guard let type else {
            return nil
        }
        guard let typeInfo = codebaseInfo.primaryTypeInfo(forNamed: type) else {
            return nil
        }
        guard typeInfo.attributes.isBridgeToKotlin || typeInfo.attributes.isBridgeToSwift else {
            return nil
        }
        guard direction == .toKotlin else {
            return type
        }
        return type.checkBridgable(direction: direction, options: options, generics: self, codebaseInfo: codebaseInfo)?.kotlinType ?? type
    }

    /// The `<...>` list of used generics in a function or type.
    var swiftParametersString: String {
        let entries = self.entries.filter { $0.name != "Self" }
        if entries.isEmpty {
            return ""
        }
        return "<" + entries.map { $0.name }.joined(separator: ", ") + ">"
    }

    /// The `where ...` list of generic constraints on a function or type.
    var swiftWhereString: String {
        let conditions = entries.compactMap { entry in
            if let whereEqual = entry.whereEqual {
                return "\(entry.name) == \(whereEqual)"
            } else if !entry.inherits.isEmpty {
                return entry.inherits.map { "\(entry.name): \($0)" }.joined(separator: ", ")
            } else {
                return nil
            }
        }
        guard !conditions.isEmpty else {
            return ""
        }
        return " where " + conditions.joined(separator: ", ")
    }
}

extension Generic {
    /// The `where ...` list of generic constraints on an individual generic entry.
    var swiftWhereString: String {
        let whereString: String
        if let whereEqual {
            whereString = "\(name) == \(whereEqual)"
        } else if !inherits.isEmpty {
            whereString = inherits.map { "\(name): \($0)" }.joined(separator: ", ")
        } else {
            return ""
        }
        return " where \(whereString)"
    }
}

/// Information used to bridge values.
struct Bridgable {
    /// Strategies for bridging values.
    enum Strategy: Equatable {
        case direct
        case convertible
        case peer
        case polymorphic
        case `protocol`
        case error
        case view
        case unknown
    }

    /// Bridging direction.
    enum Direction {
        case any
        case toKotlin
        case toSwift
    }

    var type: TypeSignature
    var kotlinType: TypeSignature
    var genericType: TypeSignature? = nil
    var isGenericEntry = false
    var strategy: Strategy

    var constrainedType: TypeSignature {
        return genericType ?? type
    }

    var externalType: TypeSignature {
        return genericType == nil ? kotlinType : .any.asOptional(kotlinType.isOptional)
    }

    func jni(options: KotlinBridgeOptions) -> String {
        return (isGenericEntry ? TypeSignature.any : kotlinType).jni(options: options)
    }
}

/// Information used to bridge functions.
struct FunctionBridgable {
    var parameters: [Bridgable]
    var `return`: Bridgable
}

extension KotlinVariableDeclaration {
    /// Check that this variable is bridgable.
    ///
    /// This function will add messages about invalid modifiers or types to this variable.
    func checkBridgable(direction: Bridgable.Direction, options: KotlinBridgeOptions, translator: KotlinTranslator) -> Bridgable? {
        if direction == .toKotlin {
            guard checkNonStaticGenericTypeMember(self, in: parent, modifiers: modifiers, translator: translator) else {
                return nil
            }
        }
        guard checkNonStaticProtocolRequirement(self, in: parent, modifiers: modifiers, translator: translator) else {
            return nil
        }
        guard checkNonTypedThrows(self, apiFlags: apiFlags, source: translator.syntaxTree.source) else {
            return nil
        }
        guard !modifiers.isLazy else {
            messages.append(.kotlinBridgeUnsupportedFeature(self, feature: "lazy vars", source: translator.syntaxTree.source))
            return nil
        }
        guard let codebaseInfo = translator.codebaseInfo else {
            return nil
        }
        let type = declaredType.or(propertyType)
        let generics = (parent as? KotlinClassDeclaration)?.generics ?? (parent as? KotlinInterfaceDeclaration)?.generics ?? extends?.1
        return type.checkBridgable(direction: direction, options: options, generics: generics, codebaseInfo: codebaseInfo, sourceDerived: self, source: translator.syntaxTree.source)
    }

    /// Return the annotation necessary to prevent the Kotlin compiler from mangling the name of this variable.
    func preventJVMNameManglingAnnotation(name: String? = nil, isFunction: Bool = false) -> String? {
        // The Kotlin compiler appends a hash to the names of functions using unsigned parameters
        guard propertyType.isUnsigned, apiFlags.options.contains(.writeable) && (modifiers.setVisibility == .default || modifiers.setVisibility >= .public) else {
            return nil
        }
        // Interface members and their overrides need to suppress INAPPLICABLE_JVM_NAME, so do for all
        if isFunction {
            return "@Suppress(\"INAPPLICABLE_JVM_NAME\") @JvmName(\"\(name ?? propertyName.setterName)\")"
        } else {
            return "@Suppress(\"INAPPLICABLE_JVM_NAME\") @set:JvmName(\"\(name ?? propertyName.setterName)\")"
        }
    }
}

extension KotlinFunctionDeclaration {
    /// Whether this function declaration matches the Kotlin `equals()` function.
    var isKotlinEqualImplementation: Bool {
        return name == "equals" && !modifiers.isStatic && parameters.count == 1 && parameters[0].declaredType == .optional(.any)
    }

    /// Whether this function declaration matches the Kotlin `hashCode()` function.
    var isKotlinHashImplementation: Bool {
        return name == "hashCode" && !modifiers.isStatic && parameters.isEmpty && returnType == .int
    }

    /// Check that this function is bridgable.
    ///
    /// This function will add messages about invalid modifiers or types to this variable.
    func checkBridgable(direction: Bridgable.Direction, options: KotlinBridgeOptions, translator: KotlinTranslator) -> FunctionBridgable? {
        guard type != .finalizerDeclaration else {
            return nil
        }
        guard role != .operator else {
            messages.append(.kotlinBridgeUnsupportedFeature(self, feature: "custom subscripts and operators", source: translator.syntaxTree.source))
            return nil
        }
        guard !isOptionalInit else {
            messages.append(.kotlinBridgeUnsupportedFeature(self, feature: "optional inits", source: translator.syntaxTree.source))
            return nil
        }
        if direction == .toKotlin {
            guard isEqualImplementation || isLessThanImplementation || checkNonStaticGenericTypeMember(self, in: parent, modifiers: modifiers, translator: translator) else {
                return nil
            }
        }
        guard checkNonStaticProtocolRequirement(self, in: parent, modifiers: modifiers, translator: translator) else {
            return nil
        }
        guard checkNonTypedThrows(self, apiFlags: apiFlags, source: translator.syntaxTree.source) else {
            return nil
        }
        guard !parameters.contains(where: { $0.isVariadic }) else {
            messages.append(.kotlinBridgeUnsupportedFeature(self, feature: "variadic parameters", source: translator.syntaxTree.source))
            return nil
        }
        if direction == .toKotlin {
            guard name != "constructor" || (parent as? KotlinClassDeclaration)?.generics.isEmpty != false else {
                messages.append(.kotlinBridgeGenericMember(self, source: translator.syntaxTree.source))
                return nil
            }
        }
        guard let codebaseInfo = translator.codebaseInfo else {
            return nil
        }
        var generics = (parent as? KotlinClassDeclaration)?.generics ?? (parent as? KotlinInterfaceDeclaration)?.generics ?? extends?.1
        if generics != nil {
            generics = generics!.merge(overrides: self.generics, addNew: true)
        } else {
            generics = self.generics
        }
        return functionType.checkFunctionBridgable(direction: direction, isConstructor: type == .constructorDeclaration, options: options, generics: generics, codebaseInfo: codebaseInfo, sourceDerived: self, source: translator.syntaxTree.source)
    }

    /// Return the annotation necessary to prevent the Kotlin compiler from mangling the name of this function.
    func preventJVMNameManglingAnnotation(name: String? = nil) -> String? {
        // The Kotlin compiler appends a hash to the names of functions using unsigned parameters
        guard parameters.contains(where: { $0.declaredType.isUnsigned }) else {
            return nil
        }
        let name = name ?? self.name
        guard name != "constructor" else {
            return nil
        }
        // Interface members and their overrides need to suppress INAPPLICABLE_JVM_NAME, so do for all
        return "@Suppress(\"INAPPLICABLE_JVM_NAME\") @JvmName(\"\(name)\")"
    }
}

extension KotlinEnumCaseDeclaration {
    /// Check that the associated values of this case are bridgable.
    ///
    /// This function will add messages about invalid modifiers or types to this case.
    func checkBridgable(direction: Bridgable.Direction, options: KotlinBridgeOptions, translator: KotlinTranslator) -> [Bridgable]? {
        guard !associatedValues.isEmpty else {
            return []
        }
        guard let codebaseInfo = translator.codebaseInfo else {
            return nil
        }
        let generics = (parent as? KotlinClassDeclaration)?.generics ?? (parent as? KotlinInterfaceDeclaration)?.generics
        let bridgables = associatedValues.compactMap { $0.declaredType.checkBridgable(direction: direction, options: options, generics: generics, codebaseInfo: codebaseInfo, sourceDerived: self, source: translator.syntaxTree.source) }
        guard bridgables.count == associatedValues.count else {
            return nil
        }
        return bridgables
    }
}

extension KotlinClassDeclaration {
    /// Check that this class is bridgable.
    func checkBridgable(direction: Bridgable.Direction, options: KotlinBridgeOptions, translator: KotlinTranslator) -> Bool {
        guard checkParentBridgable(self, direction: direction, options: options, translator: translator) else {
            return false
        }
        return true
    }

    /// Return the info for this type's superclass, or `nil`.
    func superclassInfo(translator: KotlinTranslator) -> CodebaseInfo.TypeInfo? {
        guard declarationType == .classDeclaration, let codebaseInfo = translator.codebaseInfo, let inherit = inherits.first else {
            return nil
        }
        guard let primaryTypeInfo = codebaseInfo.primaryTypeInfo(forNamed: inherit) else {
            return nil
        }
        return primaryTypeInfo.declarationType == .classDeclaration ? primaryTypeInfo : nil
    }
}

extension KotlinInterfaceDeclaration {
    /// Check that this interface is bridgable.
    func checkBridgable(direction: Bridgable.Direction, options: KotlinBridgeOptions, translator: KotlinTranslator) -> Bool {
        guard checkParentBridgable(self, direction: direction, options: options, translator: translator) else {
            return false
        }
        return true
    }
}

extension KotlinSyntaxNode {
    final var isInIfNotSkipBridgeBlock: Bool {
        var node: KotlinSyntaxNode? = self
        while node != nil {
            if let directives = (node as? KotlinStatement)?.extras?.directives {
                for directive in directives {
                    if case .ifSkipBlock(let blockType) = directive, blockType == .ifNotSkipBridge {
                        return true
                    }
                }
            }
            node = node?.parent
        }
        return false
    }
}

extension TypeSignature {
    func callbackClosureType(apiFlags: APIFlags, kotlin: Bool) -> TypeSignature {
        let isThrows = apiFlags.throwsType != .none
        let throwsParameterType: TypeSignature = kotlin ? .named("Throwable", []).asOptional(true) : .javaObjectPointer.asOptional(true)
        if self == .void {
            if isThrows {
                return .function([TypeSignature.Parameter(type: throwsParameterType)], .void, APIFlags(), nil)
            } else {
                return .function([], .void, APIFlags(), nil)
            }
        } else {
            if isThrows {
                return .function([TypeSignature.Parameter(type: self.asOptional(true)), TypeSignature.Parameter(type: throwsParameterType)], .void, APIFlags(), nil)
            } else {
                return .function([TypeSignature.Parameter(type: self)], .void, APIFlags(), nil)
            }
        }
    }

    /// Check that this type is bridgable, adding any messages to the given source object.
    func checkBridgable(direction: Bridgable.Direction, options: KotlinBridgeOptions, generics: Generics?, codebaseInfo: CodebaseInfo.Context, sourceDerived: SourceDerived? = nil, source: Source? = nil) -> Bridgable? {
        switch self {
        case .any, .anyObject:
            return Bridgable(type: self, kotlinType: self, strategy: .unknown)
        case .array(let elementType):
            guard let elementBridgable = elementType?.checkBridgable(direction: direction, options: options, generics: generics, codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source) else {
                return nil
            }
            let arrayType: TypeSignature = .array(elementBridgable.type)
            let genericType: TypeSignature? = elementBridgable.genericType == nil ? nil : .array(elementBridgable.genericType!)
            if options.contains(.kotlincompat) {
                let listType: TypeSignature = .module("kotlin.collections", .named("List", [elementBridgable.kotlinType]))
                return Bridgable(type: arrayType, kotlinType: listType, genericType: genericType, strategy: .convertible)
            } else {
                return Bridgable(type: arrayType, kotlinType: .array(elementBridgable.kotlinType), genericType: genericType, strategy: .convertible)
            }
        case .bool:
            return Bridgable(type: self, kotlinType: self, strategy: .direct)
        case .character:
            // TODO
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnsupportedFeature(sourceDerived, feature: description, source: source))
            }
            return nil
        case .composition:
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnsupportedFeature(sourceDerived, feature: description, source: source))
            }
            return nil
        case .dictionary(let keyType, let valueType):
            guard let keyBridgable = keyType?.checkBridgable(direction: direction, options: options, generics: generics, codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source), let valueBridgable = valueType?.checkBridgable(direction: direction, options: options, generics: generics, codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source) else {
                return nil
            }
            let dictType: TypeSignature = .dictionary(keyBridgable.type, valueBridgable.type)
            let genericType: TypeSignature? = keyBridgable.genericType == nil && valueBridgable.genericType == nil ? nil : .dictionary(keyBridgable.genericType ?? keyBridgable.type, valueBridgable.genericType ?? valueBridgable.type)
            if options.contains(.kotlincompat) {
                let mapType: TypeSignature = .module("kotlin.collections", .named("Map", [keyBridgable.kotlinType, valueBridgable.kotlinType]))
                return Bridgable(type: dictType, kotlinType: mapType, genericType: genericType, strategy: .convertible)
            } else {
                return Bridgable(type: dictType, kotlinType: .dictionary(keyBridgable.kotlinType, valueBridgable.kotlinType), genericType: genericType, strategy: .convertible)
            }
        case .double, .float:
            return Bridgable(type: self, kotlinType: self, strategy: .direct)
        case .existential(let mode, let type):
            guard var bridgable = type.checkBridgable(direction: direction, options: options, generics: generics, codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source) else {
                return nil
            }
            bridgable.type = bridgable.type.withExistentialMode(mode)
            bridgable.genericType = bridgable.genericType?.withExistentialMode(mode)
            return bridgable
        case .function(let parameters, let returnType, let apiFlags, let attributes):
            guard checkNonTypedThrows(sourceDerived, apiFlags: apiFlags, source: source) else {
                return nil
            }
            let bridgeReturnType: TypeSignature
            let bridgeKotlinReturnType: TypeSignature
            let bridgeGenericReturnType: TypeSignature?
            if returnType == .void {
                bridgeReturnType = .void
                bridgeKotlinReturnType = .void
                bridgeGenericReturnType = nil
            } else {
                guard let bridge = returnType.checkBridgable(direction: direction, options: options, generics: generics, codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source) else {
                    return nil
                }
                bridgeReturnType = returnType
                bridgeKotlinReturnType = bridge.kotlinType
                bridgeGenericReturnType = bridge.genericType
            }
            var bridgeParameters: [TypeSignature.Parameter] = []
            var bridgeKotlinParameters: [TypeSignature.Parameter] = []
            var bridgeGenericParameters: [TypeSignature.Parameter?] = []
            for var parameter in parameters {
                guard let bridge = parameter.type.checkBridgable(direction: direction, options: options, generics: generics, codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source) else {
                    return nil
                }
                parameter.type = bridge.type
                bridgeParameters.append(parameter)
                parameter.type = bridge.kotlinType
                bridgeKotlinParameters.append(parameter)
                if let genericType = bridge.genericType {
                    parameter.type = genericType
                    bridgeGenericParameters.append(parameter)
                } else {
                    bridgeGenericParameters.append(nil)
                }
            }
            let bridgeType: TypeSignature = .function(bridgeParameters, bridgeReturnType, apiFlags, attributes)
            let bridgeKotlinType: TypeSignature = .function(bridgeKotlinParameters, bridgeKotlinReturnType, apiFlags, attributes)
            let bridgeGenericType: TypeSignature?
            if bridgeGenericReturnType != nil || bridgeGenericParameters.contains(where: { $0 != nil }) {
                let parameters = zip(bridgeGenericParameters, bridgeParameters).map { $0 ?? $1 }
                let returnType = bridgeGenericReturnType ?? bridgeReturnType
                bridgeGenericType = .function(parameters, returnType, apiFlags, attributes)
            } else {
                bridgeGenericType = nil
            }
            return Bridgable(type: bridgeType, kotlinType: bridgeKotlinType, genericType: bridgeGenericType, strategy: .direct)
        case .int, .int8, .int16, .int32, .int64:
            return Bridgable(type: self, kotlinType: self, strategy: .direct)
        case .int128:
            // TODO
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnsupportedFeature(sourceDerived, feature: description, source: source))
            }
            return nil
        case .member, .module, .named:
            if isNamed("AnyHashable", moduleName: "Swift", generics: []) {
                return Bridgable(type: self, kotlinType: self, strategy: .unknown)
            } else if isNamed("Nothing", moduleName: "Swift", generics: []) {
                return Bridgable(type: .none, kotlinType: .javaVoid(kotlin: true), strategy: .unknown)
            } else if isNamed("NSNumber", moduleName: "Foundation", generics: []) || description == "java.lang.Number" {
                // Special case NSNumber, which is just typealiased to java.lang.Number in SkipLib
                let kotlinType: TypeSignature = .module("java.lang", .named("Number", []))
                return Bridgable(type: .named("NSNumber", []), kotlinType: kotlinType, strategy: .convertible)
            } else {
                return checkNamedBridgable(direction: direction, options: options, generics: generics, codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source)
            }
        case .metaType:
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnsupportedFeature(sourceDerived, feature: description, source: source))
            }
            return nil
        case .none:
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnknownType(sourceDerived, type: description, source: source))
            }
            return nil
        case .optional(let type):
            guard let bridgable = type.checkBridgable(direction: direction, options: options, generics: generics, codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source) else {
                return nil
            }
            return Bridgable(type: bridgable.type.asOptional(true), kotlinType: bridgable.kotlinType.asOptional(true), genericType: bridgable.genericType?.asOptional(true), isGenericEntry: bridgable.isGenericEntry, strategy: bridgable.strategy)
        case .range:
            // TODO
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnsupportedFeature(sourceDerived, feature: description, source: source))
            }
            return nil
        case .set(let elementType):
            guard let elementBridgable = elementType?.checkBridgable(direction: direction, options: options, generics: generics, codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source) else {
                return nil
            }
            let setType: TypeSignature = .set(elementBridgable.type)
            let genericType: TypeSignature? = elementBridgable.genericType == nil ? nil : .set(elementBridgable.genericType!)
            if options.contains(.kotlincompat) {
                let kotlinSetType: TypeSignature = .module("kotlin.collections", .named("Set", [elementBridgable.kotlinType]))
                return Bridgable(type: setType, kotlinType: kotlinSetType, genericType: genericType, strategy: .convertible)
            } else {
                return Bridgable(type: setType, kotlinType: .set(elementBridgable.kotlinType), genericType: genericType, strategy: .convertible)
            }
        case .string:
            return Bridgable(type: self, kotlinType: self, strategy: .direct)
        case .tuple(let labels, let types):
            let typeBridgables: [Bridgable] = types.compactMap { type in
                guard let bridgable = type.checkBridgable(direction: direction, options: options, generics: generics, codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source) else {
                    return nil
                }
                return bridgable
            }
            guard typeBridgables.count == types.count else {
                return nil
            }
            let tupleType: TypeSignature = .tuple(labels, typeBridgables.map(\.type))
            let genericType: TypeSignature?
            if typeBridgables.contains(where: { $0.genericType != nil }) {
                let types = zip(typeBridgables.map(\.genericType), typeBridgables.map(\.type)).map { $0 ?? $1 }
                genericType = .tuple(labels, types)
            } else {
                genericType = nil
            }
            if types.count == 2 && options.contains(.kotlincompat) {
                let pairType: TypeSignature = .named("kotlin.Pair", typeBridgables.map(\.kotlinType))
                return Bridgable(type: tupleType, kotlinType: pairType, genericType: genericType, strategy: .direct)
            } else if types.count == 3 && options.contains(.kotlincompat) {
                let tripleType: TypeSignature = .named("kotlin.Triple", typeBridgables.map(\.kotlinType))
                return Bridgable(type: tupleType, kotlinType: tripleType, genericType: genericType, strategy: .direct)
            } else {
                return Bridgable(type: tupleType, kotlinType: .tuple(labels, typeBridgables.map(\.kotlinType)), genericType: genericType, strategy: .direct)
            }
        case .typealiased(_, let type):
            return type.checkBridgable(direction: direction, options: options, generics: generics, codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source)
        case .uint, .uint8, .uint16, .uint32, .uint64:
            return Bridgable(type: self, kotlinType: self, strategy: .direct)
        case .uint128:
            // TODO
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnsupportedFeature(sourceDerived, feature: description, source: source))
            }
            return nil
        case .unwrappedOptional:
            // TODO - force unwrapped properties compiled as Java fields not get/set methods
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnsupportedFeature(sourceDerived, feature: "force unwrapped types", source: source))
            }
            return nil
        case .void:
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnsupportedFeature(sourceDerived, feature: description, source: source))
            }
            return nil
        }
    }

    /// Check that this function is bridgable, adding any messages to the given source object.
    func checkFunctionBridgable(direction: Bridgable.Direction, isConstructor: Bool, options: KotlinBridgeOptions, generics: Generics?, codebaseInfo: CodebaseInfo.Context, sourceDerived: SourceDerived? = nil, source: Source? = nil) -> FunctionBridgable? {
        let returnBridgable: Bridgable
        if isConstructor || returnType == .void {
            returnBridgable = Bridgable(type: .void, kotlinType: .void, strategy: .direct)
        } else {
            guard let bridgable = returnType.checkBridgable(direction: direction, options: options, generics: generics, codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source) else {
                return nil
            }
            returnBridgable = bridgable
        }
        var parameterBridgables: [Bridgable] = []
        for parameter in parameters {
            guard let bridgable = parameter.type.checkBridgable(direction: direction, options: options, generics: generics, codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source) else {
                return nil
            }
            parameterBridgables.append(bridgable)
        }
        return FunctionBridgable(parameters: parameterBridgables, return: returnBridgable)
    }

    fileprivate func checkNamedBridgable(direction: Bridgable.Direction, options: KotlinBridgeOptions, generics: Generics?, codebaseInfo: CodebaseInfo.Context, sourceDerived: SourceDerived?, source: Source?) -> Bridgable? {
        let constrainedType = generics?.constrainedType(of: self.withoutOptionality(), fallback: .any) ?? .none
        if constrainedType != .none {
            let types: [TypeSignature]
            if case .composition(let composedTypes) = constrainedType {
                types = composedTypes
            } else if constrainedType != .any {
                types = [constrainedType]
            } else {
                types = []
            }
            var bridgable: Bridgable? = nil
            for type in types {
                if let typeInfo = codebaseInfo.primaryTypeInfo(forNamed: type), typeInfo.declarationType != .protocolDeclaration {
                    bridgable = type.asOptional(type.isOptional || isOptional).checkBridgable(direction: direction, options: options, generics: generics, codebaseInfo: codebaseInfo)
                    break
                }
            }
            return Bridgable(type: self, kotlinType: self, genericType: constrainedType, isGenericEntry: true, strategy: bridgable?.strategy ?? .unknown)
        }

        // Special case for e.g. `some View`
        if self.swiftUIType == .view && codebaseInfo.global.moduleName != "SkipUI" {
            return Bridgable(type: .skipSwiftUIView, kotlinType: .skipUIView, genericType: nil, strategy: .view)
        }

        let typeInfos = codebaseInfo.typeInfos(forNamed: self)
        guard let typeInfo = typeInfos.first(where: { $0.declarationType != .extensionDeclaration }) else {
            // Assume unknown qualified types bridged from Kotlin are Kotlin/Java types and access them as `AnyDynamicObject`
            if direction == .toSwift && appearsToBeQualifiedJavaType {
                // Convert .member to .named so that we don't think it's an inner class, e.g.
                // java/util/Date instead of java$util$Date
                let kotlinType: TypeSignature = .named(self.name, self.generics).asOptional(self.isOptional).asUnwrappedOptional(self.isUnwrappedOptional)
                return Bridgable(type: .anyDynamicObject, kotlinType: kotlinType, genericType: nil, strategy: .convertible)
            }
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnknownType(sourceDerived, type: description, source: source))
            }
            return nil
        }
        let strategy: Bridgable.Strategy
        var kotlinType: TypeSignature = .none
        if typeInfo.attributes.isBridgeToSwift || typeInfo.attributes.isBridgeToKotlin {
            if typeInfo.declarationType == .classDeclaration && !typeInfo.modifiers.isFinal {
                strategy = .polymorphic
            } else if typeInfo.declarationType == .protocolDeclaration {
                strategy = .protocol
            } else {
                strategy = .peer
            }
        } else if typeInfo.declarationType == .protocolDeclaration, let moduleName = typeInfo.moduleName, moduleName != "SkipUI" && isSkipModule(name: moduleName) {
            if moduleName == "SkipLib" && typeInfo.signature.name == "Error" {
                strategy = .error
                if options.contains(.kotlincompat) {
                    kotlinType = .named("kotlin.Throwable", [])
                }
            } else {
                // Any protocol in a built-in module will have a Kotlin representation
                strategy = .protocol
            }
        } else {
            if typeInfos.contains(where: { $0.inherits.contains(where: { $0.isNamed("SwiftCustomBridged", moduleName: "Swift") }) }) {
                strategy = .convertible
                if options.contains(.kotlincompat) {
                    for typeInfo in typeInfos {
                        if let kotlinConverting = typeInfo.inherits.first(where: { $0.isNamed("KotlinConverting", moduleName: "Swift") }), let kotlinConvertingType = kotlinConverting.generics.first, kotlinConvertingType != .any {
                            kotlinType = self.kotlinType(forKotlinConverting: kotlinConvertingType, info: typeInfo)
                            break
                        }
                    }
                }
            } else {
                if let sourceDerived, let source {
                    sourceDerived.messages.append(.kotlinBridgeUnbridgedType(sourceDerived, type: description, source: source))
                }
                return nil
            }
        }
        if kotlinType == .none {
            if case .module = self {
                kotlinType = self
            } else {
                kotlinType = self.withModuleName(typeInfo.moduleName)
            }
            let kotlinGenerics = kotlinType.generics.map {
                $0.checkBridgable(direction: direction, options: options, generics: generics, codebaseInfo: codebaseInfo)?.kotlinType ?? $0
            }
            kotlinType = kotlinType.withGenerics(kotlinGenerics)
        }
        var genericType: TypeSignature? = generics == nil ? nil : constrainedTypeWithGenerics(generics!)
        if genericType == self {
            genericType = nil
        }
        return Bridgable(type: self, kotlinType: kotlinType, genericType: genericType, strategy: strategy)
    }

    private func isSkipModule(name: String) -> Bool {
        guard name.hasPrefix("Skip") else {
            return false
        }
        return CodebaseInfo.moduleNameMap.values.contains { $0.contains(name) }
    }

    private func kotlinType(forKotlinConverting kotlinConvertingType: TypeSignature, info: CodebaseInfo.TypeInfo) -> TypeSignature {
        let generics = kotlinConvertingType.generics.map { generic in
            if let idx = info.generics.entries.firstIndex(where: { $0.name == generic.name }), self.generics.count > idx {
                let mapped = self.generics[idx]
                return mapped.asOptional(mapped.isOptional || generic.isOptional)
            } else {
                return generic
            }
        }
        return kotlinConvertingType.withGenerics(generics)
    }

    private var appearsToBeQualifiedJavaType: Bool {
        // Look for a qualified type whose first token is lower case
        switch self {
        case .member(let parent, _):
            return parent.name.first?.isLowercase == true
        case .module(let name, _):
            return name.first?.isLowercase == true
        case .named(let name, _):
            return name.contains { $0 == "." } && name.first?.isLowercase == true
        default:
            return false
        }
    }
}

private func checkParentBridgable(_ statement: KotlinStatement, direction: Bridgable.Direction, options: KotlinBridgeOptions, translator: KotlinTranslator) -> Bool {
    guard (statement.parent as? KotlinClassDeclaration)?.checkBridgable(direction: direction, options: options, translator: translator) != false else {
        // This is not an error - the children of an unbridged type are simply not bridged either
        return false
    }
    guard (statement.parent as? KotlinInterfaceDeclaration)?.checkBridgable(direction: direction, options: options, translator: translator) != false else {
        // This is not an error - the children of an unbridged type are simply not bridged either
        return false
    }
    return true
}

private func checkNonStaticGenericTypeMember(_ sourceDerived: SourceDerived, in parent: KotlinSyntaxNode?, modifiers: Modifiers, translator: KotlinTranslator) -> Bool {
    guard modifiers.isStatic, let classDeclaration = parent as? KotlinClassDeclaration, !classDeclaration.generics.isEmpty else {
        return true
    }
    sourceDerived.messages.append(.kotlinBridgeGenericMember(sourceDerived, source: translator.syntaxTree.source))
    return false
}

private func checkNonStaticProtocolRequirement(_ sourceDerived: SourceDerived, in parent: KotlinSyntaxNode?, modifiers: Modifiers, translator: KotlinTranslator) -> Bool {
    guard modifiers.isStatic, parent is KotlinInterfaceDeclaration else {
        return true
    }
    sourceDerived.messages.append(.kotlinBridgeUnsupportedFeature(sourceDerived, feature: "static protocol requirements", source: translator.syntaxTree.source))
    return false
}

private func checkNonTypedThrows(_ sourceDerived: SourceDerived?, apiFlags: APIFlags, source: Source?) -> Bool {
    guard apiFlags.throwsType != .none && apiFlags.throwsType != .any else {
        return true
    }
    if let sourceDerived, let source {
        sourceDerived.messages.append(.kotlinBridgeTypedThrows(sourceDerived, source: source))
    }
    return false
}

