extension Message {
    static func kotlinUntranslatable(_ syntaxNode: SyntaxNode, source: Source) -> Message {
        let messageString = "Skip cannot translate this statement to Kotlin [\(syntaxNode.nodeName)]"
        return Message(kind: .error, message: messageString, sourceDerived: syntaxNode, source: source)
    }

    // List of specific untranslatable errors. This will be helpful in maintaining documentation

    // Idea: translate variable assignments to set calls
    static func kotlinActorMutableProperty(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Non-private mutable actor properties are not supported. Consider making this private and using non-private functions to access it", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinAsyncAwaitTypeInference(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .warning, message: "Skip is unable to match this API call to determine the correct actor on which to run it. Consider adding additional type information", sourceDerived: sourceDerived, source: source)
    }

    // Idea: auto-translate to function?
    static func kotlinAsyncConstructor(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin does not support async constructors. Consider using a factory function", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinAsyncLetAssignment(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .warning, message: "Shadowing an async let variable with a variable of the same name may produce incorrect Kotlin. Consider using a different variable name", sourceDerived: sourceDerived, source: source)
    }

    // Idea: call as get()?
    static func kotlinAsyncSubscript(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin does not support async subscripts. Consider using a standard get function", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinAsyncTaskClosureInline(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .warning, message: "Skip requires that you pass Task and MainActor operations as inline closures, e.g. Task { ... }. Failure to do so may result in the code running on the wrong thread", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinAttributeUnsupported(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .warning, message: "Kotlin does not support this Swift attribute, macro, or property wrapper", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinAttributeOnParameterUnsupported(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .warning, message: "Kotlin does not support this Swift function parameter attribute", sourceDerived: sourceDerived, source: source)
    }

    // Idea: modify call sites to wrap argument in a closure
    static func kotlinAutoclosure(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin does not support @autoclosure parameters. Consider using a standard closure", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinBindingParameterAssignment(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .warning, message: "Shadowing a SwiftUI Binding parameter with a variable of the same name may produce incorrect Kotlin. Consider using a different variable name", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinCatchCaseCast(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin only supports catch clauses that use enum cases, 'is <type>', or 'let <e> as <type>' conditions", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinClosureSelfAssignment(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin does not allow you to re-bind 'self'. Consider using a different identifier", sourceDerived: sourceDerived, source: source)
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

    static func kotlinConstructorCastStaticInitResult(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .warning, message: "The Kotlin translation of this static init may not evaluate to the expected type. Consider casting the result, as in 'T.init(...) as T'", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinConstructorDelegatingStatementArguments(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "In Kotlin, delegating calls to 'self' or 'super' constructors can not use local variables other than the parameters passed to this constructor", sourceDerived: sourceDerived, source: source)
    }

    // Idea: convert to factory function
    static func kotlinConstructorGenerics(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin constructors cannot introduce additional generics. Only use generics from the owning type declaration", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinConstructorMatchProtocolInit(_ sourceDerived: SourceDerived, protocolSignature: TypeSignature, source: Source) -> Message {
        return Message(kind: .error, message: "Skip is unable to match an init requirement from protocol \(protocolSignature) to a constructor", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinConstructorSingleDelegatingStatement(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "A Kotlin constructor can only include a single top-level call to another 'this' or 'super' constructor", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinConstructorStaticInitGenerics(_ sourceDerived: SourceDerived, protocolSignature: TypeSignature, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin cannot satisfy a protocol init requirement with a generic constructor", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinDiscard(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin does not support discarding non-copyable types", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinEnumNameProperty(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "The Kotlin enum base type has a 'name' property which cannot be overridden. Consider changing the name of this property", sourceDerived: sourceDerived, source: source)
    }

    // Idea: generate an internal ordinal member var and synthesize code to use it and associated values to conform
    static func kotlinEnumSealedClassComparableConformance(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Skip does not support automatic Comparable conformance for enums that translate into Kotlin sealed classes. Consider writing your own < operator function", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinEnumSelfAssignment(_ sourceDervied: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin enums do not support reassignment", sourceDerived: sourceDervied, source: source)
    }

    static func kotlinEnvironmentDeclaredType(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin cannot infer the type of this @Environment variable. Consider adding a type declaration", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinEnvironmentKeyType(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Skip does not recognize this environment property specification. For an @Environment property, supply the key as '\\.keyPath', '\\EnvironmentValues.keyPath' or 'ObservableType.self'. For an @EnvironmentObject property, make sure the property has a declared type", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinEnvironmentValuesKeyDefault(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .warning, message: "Skip is unable to determine the default value of this EnvironmentValues key type. Make sure it declares a static 'defaultValue' property with an explicitly declared type", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinErrorCannotExtendClass(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "An Error type cannot extend another class because it will be translated to extend Exception in Kotlin", sourceDerived: sourceDerived, source: source)
    }

    // Idea: factory function with class name?
    static func kotlinExtensionAddConstructors(_ sourceDerived: SourceDerived, extensionPlacement: KotlinExtensionPlacement?, source: Source) -> Message? {
        guard let extensionPlacement else {
            return Message(kind: .error, message: "Kotlin does not support constructors with additional type constraints", sourceDerived: sourceDerived, source: source)
        }
        guard let unmovableExplanation = extensionUnmovableExplanation(placement: extensionPlacement) else {
            return nil
        }
        return Message(kind: .error, message: "\(unmovableExplanation) Therefore it cannot add additional constructors", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinExtensionAddConstructorProtocolMember(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "You cannot add constructors to a protocol extension", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinExtensionAddStaticProtocolMember(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "You cannot add static extension members to a protocol declared outside of this module, unless that protocol already has static members", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinExtensionAddProtocols(_ sourceDerived: SourceDerived, extensionPlacement: KotlinExtensionPlacement, source: Source) -> Message? {
        guard let unmovableExplanation = extensionUnmovableExplanation(placement: extensionPlacement) else {
            return nil
        }
        return Message(kind: .error, message: "\(unmovableExplanation) Therefore it cannot add additional protocols", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinExtensionUsingFileprivateAPI(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .warning, message: "This extension will be moved into its extended type definition when translated to Kotlin. It will not be able to access this file's private types or fileprivate members", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinExtensionImplementMember(_ sourceDerived: SourceDerived, extensionPlacement: KotlinExtensionPlacement, source: Source) -> Message? {
        guard let unmovableExplanation = extensionUnmovableExplanation(placement: extensionPlacement) else {
            return nil
        }
        return Message(kind: .error, message: "\(unmovableExplanation) Therefore it can add new properties and functions, but it cannot be used to override members or implement protocol requirements", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinExtensionSelfAssignment(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "This function must be translated to a Kotlin extension function, which lives outside the Kotlin class definition. Therefore you cannot assign a new value to self", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinExtensionUnsupportedMember(_ sourceDerived: SourceDerived, extensionPlacement: KotlinExtensionPlacement?, source: Source) -> Message? {
        guard let extensionPlacement else {
            // This shouldn't be possible
            return Message.internalError(sourceDerived, source: source)
        }
        guard let unmovableExplanation = extensionUnmovableExplanation(placement: extensionPlacement) else {
            return nil
        }
        return Message(kind: .error, message: "\(unmovableExplanation) Therefore the extension can only include properties and functions", sourceDerived: sourceDerived, source: source)
    }

    private static func extensionUnmovableExplanation(placement: KotlinExtensionPlacement) -> String? {
        if placement.isInModule == false {
            return "This extension cannot be merged into its extended Kotlin type, because its type is defined outside of this module."
        } else if !placement.canMove {
            return "This extension cannot be merged into its extended Kotlin type definition because it has generic constraints."
        } else if !placement.visibilityAllowsMove {
            return "This extension will not be merged into its extended Kotlin type definition because it is declared as private or fileprivate."
        } else {
            return nil
        }
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

    static func kotlinGenericCast(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .warning, message: "Kotlin does not preserve generics at runtime. The generic portion of this cast will act as a force cast, which may not be your desired behavior", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinGenericCheck(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .warning, message: "Kotlin does not preserve generics at runtime. The generic types will be ignored in this comparison, which may not be your desired behavior", sourceDerived: sourceDerived, source: source)
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

    static func kotlinKeyPath(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin does not support key paths. Skip offers limited support by translating key path literals to closures, but this use case is not supported", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinLateinitPrimitive(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin does not support late initialization of properties with primitive types", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinLocalVariableCustomLogic(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin does not support custom get and set logic for local variables", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinLocalVariableLazy(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin does not support lazy local variables. Consider using a closure to delay the variable value's creation", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinMemberAccessUnknownBaseType(_ sourceDerived: SourceDerived, source: Source, member: String) -> Message {
        return Message(kind: .error, message: "Skip is unable to determine the owning type for member '\(member)'. This often occurs when other issues prevent Skip from matching the surrounding API call, and it may resolve when those issues are fixed. Or add the owning type explicitly (e.g. MyType.\(member))", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinNumericCast(_ sourceDerived: SourceDerived, source: Source, type: String) -> Message {
        return Message(kind: .error, message: "Cast required, e.g. \(type)(<value>). Kotlin requires specific type matching when dealing with Floats, Int128, and unsigned types. We generally recommend avoiding Float in favor of Double and unsigned types in favor of signed types", sourceDerived: sourceDerived, source: source)
    }

    // Idea: read/mutate synthetic mutableState values
    static func kotlinObservationManualTrigger(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Skip does not support calls to the generated access(keyPath:) and withMutation(keyPath:_:) functions. Consider adding a synthetic observed property that you read or increment to trigger access and mutation effects", sourceDerived: sourceDerived, source: source)
    }

    // Idea: translate to equivalent Kotlin operator functions
    static func kotlinOperatorFunction(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Skip does not support custom operators. Consider using a standard function", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinOperatorUnsupported(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin does not support this operator", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinOperatorUnsupportedAssignment(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin does not support this as a compound assignment operator. Turn this into a standard x = x + y format", sourceDerived: sourceDerived, source: source)
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

    static func kotlinProtocolMemberVisibility(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .warning, message: "Kotlin does not support protocol members with lower visibility than their declaring protocol. Skip will elevate the visibility of this member, which may cause problems if it exposes internal types", sourceDerived: sourceDerived, source: source)
    }

    // Idea: convert string mutation to re-assigning the string value
    static let kotlinStringMutation = "Detected possible string mutation. This may cause errors when converting to Kotlin, which does not have mutable strings"

    static func kotlinSwiftUIAppStorageOptional(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .warning, message: "Skip does not support nil @AppStorage values. Consider making this property non-optional", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinSwiftUITypeInference(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .warning, message: "Skip is unable to match this API call to determine whether it results in a View. Consider adding additional type information", sourceDerived: sourceDerived, source: source)
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
        return Message(kind: .error, message: "This module uses tuple label '\(label)' at different positions in different \(arity)-tuples. Kotlin does not have native tuples, and Skip's solution requires that each label is only used in one position in any tuple arity. Consider changing your label names or using positional element access (i.e. tuple.0, tuple.1, etc)", sourceFile: sourceFile)
    }

    static func kotlinTypeAliasConstrainedGenerics(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin typealias declarations do not support constrained generic types", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinVariableShadowInternalParameter(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Declaring a variable that shadows an internal parameter label of its enclosing function will cause an error in Kotlin. Consider renaming this variable", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinVariableNeedsTypeDeclaration(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Skip is unable to determine the type of this variable. Consider declaring its type explicitly", sourceDerived: sourceDerived, source: source)
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
