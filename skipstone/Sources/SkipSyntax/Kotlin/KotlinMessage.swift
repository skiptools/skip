extension Message {
    static func kotlinUntranslatable(_ syntaxNode: SyntaxNode, source: Source) -> Message {
        let messageString = "Skip cannot translate this statement to Kotlin [\(syntaxNode.nodeName)]"
        return Message(kind: .error, message: messageString, sourceDerived: syntaxNode, source: source)
    }

    // List of specific untranslatable errors. This will be helpful in maintaining documentation

    // Idea: create our own actors for Kotlin
    static func kotlinActors(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin supports async functions, but it does not have actors", sourceDerived: sourceDerived, source: source)
    }

    // Idea: auto-translate to function?
    static func kotlinAsyncConstructors(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin does not support async constructors. Consider using a factory function", sourceDerived: sourceDerived, source: source)
    }

    // Idea: auto-translate to function?
    static func kotlinAsyncProperties(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin does not support async properties. Consider using a function", sourceDerived: sourceDerived, source: source)
    }

    // FIXME: should be (and was) an .error, but turned into a warning for async testing
    static func kotlinAsyncAwaitTypeInference(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .warning, message: "Skip is unable to match this API call to determine the correct actor on which to run it. Consider adding additional type information", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinAttributeUnsupported(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .warning, message: "Kotlin does not support this Swift attribute or property wrapper", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinAttributeOnParameterUnsupported(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .warning, message: "Kotlin does not support this Swift function parameter attribute", sourceDerived: sourceDerived, source: source)
    }

    // Idea: modify call sites to wrap argument in a closure
    static func kotlinAutoclosure(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin does not support @autoclosure parameters. Consider using a standard closure", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinCatchCaseCast(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin only supports catch clauses that use enum cases, 'is <type>', or 'let <e> as <type>' conditions", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinCodablePropertyForKey(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Unable to locate the property for this coding key", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinCodablePropertyType(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Skip is unable to determine the type of this property for use in decoding. Add an explicit type to the declaration", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinCodableDecodeRawValueEnumsOnly(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Skip is only able to synthesize Decodable conformance for enums with raw values. Implement the init(from: Decoder) constructor yourself to decode this enum", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinCodableEncodeRawValueEnumsOnly(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Skip is only able to synthesize Encodable for enums with raw values. Implement the encode(to: Encoder) function yourself to encode this enum", sourceDerived: sourceDerived, source: source)
    }

    // Idea: auto-create combined interface for composed protocols
    static func kotlinComposedTypes(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin does not support composed types. Consider creating a single type that conforms to these types", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinConstructorCannotInferPropertyType(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Cannot infer property type. Declare the property type explicitly to generate a valid Kotlin constructor for this struct", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinConstructorSingleDelegatingStatement(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "A Kotlin constructor can only include a single top-level call to another 'this' or 'super' constructor", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinConstructorDelegatingStatementArguments(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "In Kotlin, delegating calls to 'self' or 'super' constructors can not use local variables other than the parameters passed to this constructor", sourceDerived: sourceDerived, source: source)
    }

    // Idea: generate an internal ordinal member var and synthesize code to use it and associated values to conform
    static func kotlinEnumSealedClassComparableConformance(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Skip does not support automatic Comparable conformance for enums that translate into Kotlin sealed classes. Consider writing your own < operator function", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinErrorCannotExtendClass(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "An Error type cannot extend another class because it will be translated to extend Exception in Kotlin", sourceDerived: sourceDerived, source: source)
    }

    // Idea: factory function with class name?
    static func kotlinExtensionAddConstructorsToOutsideType(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Cannot use an extension to add additional constructors to a Kotlin type defined outside of this module", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinExtensionAddProtocolsToOutsideType(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Cannot use an extension to add additional protocols to a Kotlin type defined outside of this module", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinExtensionAddProtocolsToUnmovable(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "This extension cannot be merged into its extended Kotlin type definition. Therefore it cannot add additional protocols", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinExtensionImplementMember(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "This extension cannot be merged into its extended Kotlin type definition. Therefore it can add new properties and functions, but it cannot be used to override members or implement protocol requirements", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinExtensionSelfAssignment(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "This extension cannot be merged into its extended Kotlin type definition. Therefore you cannot assign a new value to self", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinExtensionUnsupportedMember(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "The declaring extension cannot be merged into its extended Kotlin type definition. Therefore the extension can only include properties and functions", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinFunctionDisambiguateImplementable(name: String, parameters: [TypeSignature], in type: TypeSignature?, sourceFile: Source.FilePath) -> Message {
        let function = "\(type?.description ?? "").\(name)(\(parameters.map(\.description).joined(separator: ", ")))"
        let message = "Function \(function) has the same name and parameter types as a conflicting function, but Skip is unable to change its signature because this function can be overridden by types in other modules. Kotlin does not disambiguate functions on parameter labels. Consider changing the name of this function"
        return Message(kind: .warning, message: message, sourceFile: sourceFile)
    }

    static func kotlinFunctionDisambiguateProtocol(name: String, parameters: [TypeSignature], in type: TypeSignature?, sourceFile: Source.FilePath) -> Message {
        let function = "\(type?.description ?? "").\(name)(\(parameters.map(\.description).joined(separator: ", ")))"
        let message = "Function \(function) has the same name and parameter types as a conflicting function, but Skip is unable to change its signature because it is part of a protocol that may be implemented by other types. Kotlin does not disambiguate functions on parameter labels. Consider changing the name of this function"
        return Message(kind: .warning, message: message, sourceFile: sourceFile)
    }

    static func kotlinGenericExtensionStaticMember(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin companion objects (static members) do not have access to their declaring type's generics. This prohibits extensions with generic constraints from adding static members apart from functions with parameters of the constrained type(s)", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinGenericStaticMember(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin companion objects (static members) do not have access to their declaring type's generics", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinGenericTypeNested(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Swift and Kotlin treat types nested within generic types in incompatible ways, and Skip cannot translate between the two. Consider moving this type out of its generic outer type", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinInOutParameterAssignment(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .warning, message: "Shadowing an inout parameter with a variable of the same name may produce incorrect Kotlin. Consider using a different variable name", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinLateinitPrimitive(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin does not support late initialization of properties with primitive types", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinMemberAccessUnknownBaseType(_ sourceDerived: SourceDerived, source: Source, member: String) -> Message {
        return Message(kind: .error, message: "Skip is unable to determine the owning type for member '\(member)'. Add the owning type (e.g. MyType.\(member))", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinNumericCast(_ sourceDerived: SourceDerived, source: Source, type: String) -> Message {
        return Message(kind: .error, message: "Cast required, e.g. \(type)(<value>). Kotlin requires specific type matching when dealing with Floats and unsigned types. We generally recommend avoiding them in favor of Double and signed types.", sourceDerived: sourceDerived, source: source)
    }

    // Idea: translate to equivalent Kotlin operator functions
    static func kotlinOperatorFunction(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Skip does not support custom operators. Consider using a standard function", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinOptionalChainUnwrap(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .warning, message: "In Kotlin, force unwrapping any part of an optional chain unwraps the entire chain up to that point. This is different than Swift's force unwrap operator, which only applies to the link of the chain on which it is applied. Consider breaking up this chain or using either ? or ! consistently through it", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinOptionalNoneSome(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin optionals are not enums. Use nil or a value rather than .none or .some. In switch statements, use the modern 'case nil', 'case <value>?', and 'case let <binding>?'", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinOptionSetRawValue(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Skip is unable to determine the rawValue type of this OptionSet. Make sure it contains a rawValue variable with a numeric type or an init(rawValue: <numeric type>) constructor", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinOptionSetStruct(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Skip only supports OptionSets that are structs. Change this type to a struct", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinProtocolConstructor(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin does not support constructors in protocols", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinProtocolStaticMember(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin does not support static members in protocols", sourceDerived: sourceDerived, source: source)
    }

    // Idea: convert string mutation to re-assigning the string value
    static let kotlinStringMutation = "Detected possible string mutation. This may cause errors when converting to Kotlin, which does not have mutable strings"

    // Idea: translate to equivalent Kotlin get/set functions
    static func kotlinSubscriptFunction(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Skip does not support custom subscripts. Consider using standard functions", sourceDerived: sourceDerived, source: source)
    }

    // Idea: duplicate body that we're falling through to (and the following if that too does a fallthrough, etc)
    static func kotlinSwitchFallthrough(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin does not support fallthrough. Consider restructuring your switch statement", sourceDerived: sourceDerived, source: source)
    }

    // Idea: generate custom Kotlin data classes for additional tuple arities
    static func kotlinTupleArity(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Skip does not support tuples of arity > \(KotlinTupleLiteral.maximumArity). Consider creating a struct instead", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinTupleConflictingLabel(label: String, arity: Int, sourceFile: Source.FilePath) -> Message {
        return Message(kind: .error, message: "This module uses tuple label '\(label)' at different positions in different \(arity)-tuples. Kotlin does not have native tuples, and Skip's solution requires that each label is only used in one position in any tuple arity. Consider changing your label names or using positional element access", sourceFile: sourceFile)
    }

    // Idea: for typealiases that are internal, create a new top-level alias or just replace use cases with original type
    static func kotlinTypeAliasNested(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin does not support typealias declarations within functions and types. Consider moving this to a top level declaration", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinTypeAliasConstrainedGenerics(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin typealias declarations do not support constrained generic types", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinViewBuilderUnsupportedStatement(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "This Swift construct is not supported within a @ViewBuilder when translating to Kotlin UI", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinWhenCasePartialBinding(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin does not support partial bindings in case matches. Match against a concrete value or bind all values", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinWhenCaseWhere(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin does not support where conditions in case and catch matches. Consider using an if statement within the case or catch body", sourceDerived: sourceDerived, source: source)
    }
}
