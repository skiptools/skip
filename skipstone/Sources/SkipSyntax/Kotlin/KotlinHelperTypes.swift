/// Kotlin 2 uninitialized variable error types.
struct Kotlin2UninitializedTypes: OptionSet {
    static let mustBeInitialized = Kotlin2UninitializedTypes(rawValue: 1)
    static let mustBeInitializedOrFinalOrAbstract = Kotlin2UninitializedTypes(rawValue: 2)

    let rawValue: Int

    /// The annotation to add to suppress these uninitialized types.
    var suppressAnnotation: String? {
        var values: String?
        if self.contains(.mustBeInitialized) {
            values = "\"MUST_BE_INITIALIZED\""
        }
        if self.contains(.mustBeInitializedOrFinalOrAbstract) {
            let value = "\"MUST_BE_INITIALIZED_OR_FINAL_OR_ABSTRACT\""
            if values == nil {
                values = value
            } else {
                values! += ", " + value
            }
        }
        guard let values else {
            return nil
        }
        return "@Suppress(\(values))"
    }
}

/// A variable we declare to mirror a Swift binding pattern.
struct KotlinBindingVariable {
    var names: [String?]
    var value: KotlinExpression
    var isLet: Bool

    /// - Note: Appends without leading indentation or trailing newline.
    func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(isLet ? "val " : "var ")
        if names.count > 1 {
            output.append("(")
        }
        output.append(names.map { $0 ?? "_" }.joined(separator: ", "))
        if names.count > 1 {
            output.append(")")
        }
        output.append(" = ").append(value, indentation: indentation)
    }
}

enum KotlinCompanionType {
    case none
    case object
    case `class`(TypeSignature)
    case interface(TypeSignature)

    var isClass: Bool {
        if case .class = self {
            return true
        } else {
            return false
        }
    }

    var isInterface: Bool {
        if case .interface = self {
            return true
        } else {
            return false
        }
    }

    var isObject: Bool {
        if case .object = self {
            return true
        } else {
            return false
        }
    }

    var isNone: Bool {
        if case .none = self {
            return true
        } else {
            return false
        }
    }

    var signature: TypeSignature? {
        switch self {
        case .class(let signature):
            return signature
        case .interface(let signature):
            return signature
        default:
            return nil
        }
    }
}

enum KotlinDirective: String {
    case nocopy
    case nodispatch
}

/// The type of return statement expected from a code block.
enum KotlinExpectedReturn {
    /// No return is expected.
    case no
    /// A return is required.
    case yes
    /// Convert any assignment to self to a return.
    case assignToSelf
    /// If any returns are present, given them the given label.
    case labelIfPresent(String)
    /// Call `sref` on returned values with the given `onUpdate` code.
    case sref((() -> String)?)
    /// Convert any null return to our Kotlin `NullReturnException`.
    case throwIfNull
    /// Return the given value if there isn't already an explicit value being returned.
    case value(KotlinExpression, asReturn: Bool, label: String?)
}

/// Metadata about the placement of a Kotlin extension.
struct KotlinExtensionPlacement {
    var canMove = true
    var visibilityAllowsMove = true
    var isInModule: Bool?
}

extension KotlinFunctionDeclaration {
    /// Whether this declaration can act as our `MutableStruct` copy constructor.
    var isMutableStructCopyConstructor: Bool {
        guard type == .constructorDeclaration else {
            return false
        }
        return parameters.count == 1 && parameters[0].declaredType.isNamed("MutableStruct", moduleName: "Swift", generics: [])
    }

    /// Whether this declaration is the `Decodable` protocol constructor.
    var isDecodableConstructor: Bool {
        guard type == .constructorDeclaration else {
            return false
        }
        return parameters.count == 1 && parameters[0].externalLabel == "from" && parameters[0].declaredType.isNamed("Decoder", moduleName: "Swift", generics: [])
    }
}

extension KotlinStatement {
    /// Return supported attributes and add warnings for unsupported attributes.
    func processAttributes(_ attributes: Attributes, from statement: Statement, translator: KotlinTranslator) -> Attributes {
        // Keep Kotlin attributes that devs may use within SKIP blocks
        guard !statement.isInSkipBlock else {
            return attributes
        }
        let supported: [Attribute] = attributes.attributes.filter { $0.kind != .unknown }
        if supported.count == attributes.attributes.count {
            return attributes
        } else {
            messages.append(.kotlinAttributeUnsupported(self, source: translator.syntaxTree.source))
            return Attributes(attributes: supported)
        }
    }
}

/// A variable we decoare to hold the expression we're matching on for repeated evaluation without side effects.
struct KotlinTargetVariable {
    var identifier: KotlinIdentifier
    var value: KotlinExpression

    init(value: KotlinExpression) {
        self.identifier = KotlinIdentifier(name: "matchtarget")
        self.identifier.isLocalOrSelfIdentifier = true
        self.value = value
    }

    func append(to output: OutputGenerator, indentation: Indentation) {
        output.append("val ").append(identifier, indentation: indentation)
        output.append(" = ").append(value, indentation: indentation)
    }
}

/// Customize the way a variable gets and sets its value, including delegating to a storage variable.
struct KotlinVariableStorage {
    /// Append the code to retrieve this value.
    ///
    /// Use the given block to  append any needed `sref` on the value, and use the given `Bool` to determine single-statement formatting.
    var appendGet: (KotlinVariableDeclaration, () -> Void, Bool, OutputGenerator, Indentation) -> Void = { _, _, _, _, _ in }

    /// Append the code to set this value equal to the code appended by the given block.
    var appendSet: (KotlinVariableDeclaration, () -> Void, OutputGenerator, Indentation) -> Void = { _, _, _, _ in }

    /// Append the code to declare any required storage members.
    var appendStorage: (KotlinVariableDeclaration, OutputGenerator, Indentation) -> Void = { _, _, _ in }

    /// Whether this storage getter can be appended as a single statement.
    var isSingleStatementAppendable: (KotlinVariableDeclaration) -> Bool = { _ in false }

    init() {
    }

    /// Create storage with default behavior.
    ///
    /// - Parameter access: Code to access the value from storage.
    init(access: String, isUnwrappedOptional: Bool = false, appendStorage: @escaping (KotlinVariableDeclaration, OutputGenerator, Indentation) -> Void) {
        self.isSingleStatementAppendable = { !$0.modifiers.isLazy || $0.value == nil }
        self.appendGet = { variable, sref, isSingleStatement, output, indentation in
            if variable.modifiers.isLazy && variable.value != nil {
                output.append(indentation).append("if (!\(Self.isLazyInitialized(variable))) {\n")
                let initializeIndentation = indentation.inc()
                output.append(initializeIndentation).append(access)
                variable.appendInitialValue(to: output, indentation: initializeIndentation)
                output.append("\n")
                if !variable.isLateInit {
                    output.append(initializeIndentation).append("\(Self.isLazyInitialized(variable)) = true\n")
                }
                output.append(indentation).append("}\n")
            }
            if isSingleStatement {
                output.append(access)
            } else {
                output.append(indentation).append("return ").append(access)
            }
            if isUnwrappedOptional {
                output.append("!!")
            }
            sref()
            output.append("\n")
        }
        self.appendSet = { variable, value, output, indentation in
            output.append(indentation).append(access).append(" = ")
            value()
            output.append("\n")
            if variable.modifiers.isLazy && !variable.isLateInit {
                output.append(indentation).append("\(Self.isLazyInitialized(variable)) = true\n")
            }
        }
        self.appendStorage = appendStorage
    }

    /// The name to use for lazy storage of the given variable.
    static func lazyStorageName(_ variable: KotlinVariableDeclaration) -> String {
        return variable.propertyName + "storage"
    }

    /// Code to check whether the given lazy variable is initialized.
    static func isLazyInitialized(_ variable: KotlinVariableDeclaration, instance: String? = nil) -> String {
        if variable.isLateInit {
            let name = "::" + lazyStorageName(variable) + ".isInitialized"
            if let instance {
                return instance + name
            } else {
                return name
            }
        } else {
            let name = variable.propertyName + "initialized"
            if let instance {
                return instance + "." + name
            } else {
                return name
            }
        }
    }
}

extension Accessor where B: CodeBlock {
    /// Translate to an equivalent Kotlin accessor.
    func translate(translator: KotlinTranslator, expectedReturn: KotlinExpectedReturn) -> Accessor<KotlinCodeBlock> {
        if let body {
            let kbody = KotlinCodeBlock.translate(statement: body, translator: translator)
            kbody.updateWithExpectedReturn(expectedReturn)
            return Accessor<KotlinCodeBlock>(parameterName: parameterName, body: kbody)
        }
        return Accessor<KotlinCodeBlock>(parameterName: parameterName)
    }
}

extension Attributes {
    func append(to output: OutputGenerator, indentation: Indentation) {
        attributes.forEach { $0.append(to: output, indentation: indentation) }
    }
}

extension Attribute {
    func append(to output: OutputGenerator, indentation: Indentation) {
        switch kind {
        case .deprecated:
            let message = self.message ?? Message.deprecatedLabel
            output.append(indentation).append("@Deprecated(\"\(message)\")\n")
        case .unavailable:
            let message = self.message ?? Message.unavailableLabel
            output.append(indentation).append("@Deprecated(\"\(message)\", level = DeprecationLevel.ERROR)\n")
        case .unknown:
            if case .named(let name, let generics) = signature {
                output.append(indentation).append("@").append(name)
                if !generics.isEmpty {
                    output.append("<")
                    output.append(generics.map(\.kotlin).joined(separator: ", "))
                    output.append(">")
                }
                if !tokens.isEmpty {
                    output.append("(")
                    output.append(tokens.joined(separator: ", "))
                    output.append(")")
                }
                output.append("\n")
            }
        default:
            break
        }
    }
}

extension ExtensionDeclaration {
    /// Whether this extension's members can be moved into the extended type definition.
    var canMoveIntoExtendedType: Bool {
        guard generics.selfType == nil else {
            return true
        }
        return extends.generics.isEmpty && !generics.entries.contains { $0.whereEqual != nil || !$0.inherits.isEmpty }
    }

    /// Whether this extension's visibility allows it to be moved into its extended type definition.
    ///
    /// We do not move extensions marked `private` or `fileprivate` as a way for the user to veto movement.
    var visibilityAllowsMoveIntoExtendedType: Bool {
        return modifiers.visibility != .private && modifiers.visibility != .fileprivate
    }

    /// Whether this extension is in the same file as its extended type.
    var isInSameFileAsExtendedType: Bool {
        var root = parent
        while let next = root?.parent {
            root = next
        }
        guard let codeBlock = root as? CodeBlock else {
            return false
        }
        return codeBlock.statements.containsDeclaration(of: generics.selfType ?? extends)
    }
}

extension Generics {
    func insertDependencies(into dependencies: inout KotlinDependencies) {
        for entry in entries {
            entry.inherits.forEach { $0.insertDependencies(into: &dependencies) }
            entry.whereEqual?.insertDependencies(into: &dependencies)
        }
    }

    func append(to output: OutputGenerator, indentation: Indentation, modifier: String? = nil) {
        let entries = self.entries.filter { $0.name != "Self" } // Can't append Self constraints
        if entries.isEmpty {
            return
        }
        output.append("<")
        output.append(entries.map { $0.whereEqual?.kotlin ?? (modifier != nil ? "\(modifier!) \($0.name)" : $0.name) }.joined(separator: ", "))
        output.append(">")
    }

    func appendWhere(to output: OutputGenerator, indentation: Indentation) {
        let constraints = entries.flatMap { (entry: Generic) -> [(String, TypeSignature)] in
            if entry.whereEqual != nil {
                return []
            } else {
                return entry.inherits.map { (entry.name, $0) }
            }
        }
        guard !constraints.isEmpty else {
            return
        }
        output.append(" where ")
        for (index, (name, type)) in constraints.enumerated() {
            output.append("\(name): \(type.kotlin)")
            if index != constraints.count - 1 {
                output.append(", ")
            }
        }
    }
}

extension Modifiers {
    /// Kotlin modifier string for a member.
    func kotlinMemberString(isGlobal: Bool, isOpen: Bool, suffix: String) -> String {
        var string: String
        switch visibility {
        case .default, .internal:
            string = "internal"
        case .open, .public:
            string = ""
        case .private:
            string = "private"
        case .fileprivate:
            string = isGlobal ? "private" : "internal"
        }
        if isOverride {
            string = string.isEmpty ? "override" : "\(string) override"
        } else if isOpen {
            string = string.isEmpty ? "open" : "\(string) open"
        }
        return string.isEmpty || suffix.isEmpty ? string : "\(string)\(suffix)"
    }

    /// Kotlin modifier for a setter.
    func kotlinSetVisibilityString(isGlobal: Bool, suffix: String) -> String {
        guard setVisibility != .default && setVisibility != visibility else {
            return ""
        }
        var string: String
        switch setVisibility {
        case .default, .internal:
            string = "internal"
        case .open, .public:
            string = "public"
        case .private:
            string = "private"
        case .fileprivate:
            string = isGlobal ? "private" : "internal"
        }
        return string.isEmpty || suffix.isEmpty ? string : "\(string)\(suffix)"
    }
}

extension Operator {
    /// Kotlin version of this operator's symbol.
    var kotlinSymbol: String {
        switch symbol {
        case "??":
            return "?:"
        case "as!":
            return "as"
        case "...":
            return ".."
        case "|":
            return "or"
        case "&":
            return "and"
        case "^":
            return "xor"
        case "<<":
            return "shl"
        case ">>":
            return "shr"
        case "&+":
            return "+"
        case "&-":
            return "-"
        case "&*":
            return "*"
        default:
            // Note that we construct operators with non-Swift symbols like 'in'
            return symbol
        }
    }
}

extension Parameter where V: Expression {
    /// Translate to an equivalent Kotlin parameter.
    func translate(translator: KotlinTranslator) -> Parameter<KotlinExpression> {
        var kdefaultValue: KotlinExpression? = nil
        if let defaultValue {
            kdefaultValue = translator.translateExpression(defaultValue)
        }
        return Parameter<KotlinExpression>(externalLabel: externalLabel, internalLabel: internalLabel, declaredType: declaredType, isInOut: isInOut, isVariadic: isVariadic, attributes: attributes, defaultValue: kdefaultValue)
    }
}

extension Parameter {
    /// - Seealso: ``KotlinSyntaxNode/insertDependencies(into:)``
    func insertDependencies(into dependencies: inout KotlinDependencies) {
        declaredType.insertDependencies(into: &dependencies)
    }

    /// Add messages about unsupported aspects of this parameter.
    func appendKotlinMessages(to node: KotlinSyntaxNode, source: Source) {
        declaredType.appendKotlinMessages(to: node, source: source)
        if attributes.contains(.unknown) {
            node.messages.append(.kotlinAttributeOnParameterUnsupported(node, source: source))
        }
    }
}

extension Source.FilePath {
    /// Synthetic source that will be translated to a file appropriate for package-level support code.
    /// 
    /// - Parameter tests: whether this is for a test package, in which case the generated file will be "PackageSupportTest.swift" in order to not clash with the primary module's "PackageSupport.swift" (which turns into a `PackageSupportKt` class).
    func kotlinPackageSupport(tests: Bool) -> Source.FilePath {
        var filePath = self
        filePath.name = "PackageSupport\(tests ? "Test" : "").swift"
        return filePath
    }
}

extension Array where Element == KotlinExpression {
    /// Append this expression array as combined logical conditions, e.g. for an `if`.
    func appendAsLogicalConditions(to output: OutputGenerator, op: Operator = .with(symbol: "&&"), indentation: Indentation) {
        guard count > 1 else {
            if let condition = first {
                output.append(condition, indentation: indentation)
            }
            return
        }

        for (index, condition) in enumerated() {
            // Special case the common !x compound expression to avoid unnecessary parentheses
            let isCompound = condition.isCompoundExpression && !(condition is KotlinPrefixOperator && (condition as! KotlinPrefixOperator).operatorSymbol == "!")
            if isCompound {
                output.append("(")
            }
            output.append(condition, indentation: indentation)
            if isCompound {
                output.append(")")
            }
            if index < count - 1 {
                output.append(" ").append(op.symbol).append(" ")
            }
        }
    }

    /// Create a single logical expression out of these expressions.
    func asLogicalExpression() -> KotlinExpression {
        if isEmpty {
            return KotlinBooleanLiteral(literal: true)
        }
        if count == 1 {
            return self[0]
        }
        return KotlinBinaryOperator(op: .with(symbol: "&&"), lhs: Array(self[0..<(count - 1)]).asLogicalExpression(), rhs: self[count - 1])
    }
}
