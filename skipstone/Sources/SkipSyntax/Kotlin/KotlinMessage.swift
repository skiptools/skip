extension Message {
    static func kotlinUntranslatable(_ syntaxNode: SyntaxNode, source: Source) -> Message {
        let messageString = "Skip cannot translate this statement to Kotlin [\(syntaxNode.nodeName)]"
        return Message(kind: .error, message: messageString, sourceDerived: syntaxNode, source: source)
    }

    // List of specific untranslatable errors. This will be helpful in maintaining documentation

    // Idea: auto-translate to function?
    static func kotlinAsyncProperties(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin does not support async properties. Consider using a function", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinAttributeUnsupported(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .warning, message: "Kotlin does not support this Swift attribute or property wrapper", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinCatchCaseCast(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin only supports catch clauses that use enum cases, 'is <type>', or 'let <e> as <type>' conditions", sourceDerived: sourceDerived, source: source)
    }

    // Idea: auto-create combined interface for composed protocols
    static func kotlinComposedTypes(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin does not support composed types. Consider creating a single type that conforms to these types", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinConstructorCannotInferPropertyType(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Cannot infer property type. Declare the property type explicitly to generate a valid Kotlin constructor for this struct", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinConstructorSingleDelegatingStatement(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "A Kotlin constructor can only include a single call to another 'this' or 'super' constructor", sourceDerived: sourceDerived, source: source)
    }

    // Idea: factory callable on companion object? Factory function with class name?
    // Or constructor that throws exception and we catch at call site
    static func kotlinConstructorNullReturn(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin does not support constructors that return nil. Consider creating a factory function", sourceDerived: sourceDerived, source: source)
    }

    // Idea: generate an internal ordinal member var and synthesize code to use it and associated values to conform
    static func kotlinEnumSealedClassComparableConformance(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Skip does not support automatic Comparable conformance for enums that translate into Kotlin sealed classes. Consider writing your own < operator function", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinErrorCannotExtendClass(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "An Error type cannot extend another class because it will be translated to extend Throwable in Kotlin", sourceDerived: sourceDerived, source: source)
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

    static func kotlinExtensionUnsupportedMember(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "This declaration is not supported in a Kotlin extension", sourceDerived: sourceDerived, source: source)
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

    static func kotlinLoopCaseValue(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin does not support case bindings to complex expressions in loop conditions. Consider assigning the expression to a local variable before the loop - e.g. let x = ...; while case let .a(...) = x", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinLoopOptionalBinding(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin does not support optional bindings in loop conditions. Consider using an if statement before or within your loop", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinMemberAccessUnknownBaseType(_ sourceDerived: SourceDerived, source: Source, member: String) -> Message {
        return Message(kind: .error, message: "Skip is unable to determine the owning type for member '\(member)'. Add the owning type (e.g. MyType.\(member))", sourceDerived: sourceDerived, source: source)
    }

    // Idea: translate to equivalent Kotlin operator functions
    static func kotlinOperatorFunction(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Skip does not support custom operators. Consider using a standard function", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinOptionalNoneSome(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin optionals are not enums. Use nil or a value rather than .none or .some. In switch statements, use the moden 'case nil', 'case <value>?', and 'case let <binding>?'", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinProtocolConstructor(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin does not support constructors in protocols", sourceDerived: sourceDerived, source: source)
    }

    static func kotlinProtocolStaticMember(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin does not support static members in protocols", sourceDerived: sourceDerived, source: source)
    }

    // Idea: expand self assignment to merging all state from the given instance
    static func kotlinSelfAssignment(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin does not support assigning a new value to self", sourceDerived: sourceDerived, source: source)
    }

    // Idea: duplicate body that we're falling through to (and the following if that too does a fallthrough, etc)
    static func kotlinSwitchFallthrough(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Kotlin does not support fallthrough. Consider restructuring your switch statement", sourceDerived: sourceDerived, source: source)
    }

    // Idea: generate custom Kotlin data classes for additional tuple arities
    static func kotlinTupleArity(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Skip does not support tuples of arity > 5. Consider creating a struct instead", sourceDerived: sourceDerived, source: source)
    }

    // Idea: generate extensions on Pair and Triple for custom labels
    // Problem: where to define extensions and how to avoid duplicate definitions
    static func kotlinTupleLabels(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Skip does not support custom tuple element labels. Consider creating a struct instead", sourceDerived: sourceDerived, source: source)
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
