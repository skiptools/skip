extension Message {
    static func kotlinUntranslatable(_ syntaxNode: SyntaxNode, source: Source? = nil) -> Message {
        let messageString = "Skip cannot translate this statement to Kotlin [\(syntaxNode.nodeName)]"
        guard let source else {
            return Message(kind: .error, message: messageString, sourceDerived: syntaxNode)
        }
        return Message(kind: .error, message: messageString, source: source, sourceRange: syntaxNode.sourceRange)
    }

    // List of specific untranslatable errors. This will be helpful in maintaining documentation

    // Idea: auto-translate to function?
    static func kotlinAsyncProperties(_ sourceDerived: SourceDerived) -> Message {
        return Message(kind: .error, message: "Kotlin does not support async properties. Consider using a function", sourceDerived: sourceDerived)
    }

    static func kotlinAttributeUnsupported(_ sourceDerived: SourceDerived) -> Message {
        return Message(kind: .warning, message: "Kotlin does not support this Swift attribute or property wrapper", sourceDerived: sourceDerived)
    }

    // Idea: auto-create combined interface for composed protocols
    static func kotlinComposedTypes(_ sourceDerived: SourceDerived) -> Message {
        return Message(kind: .error, message: "Kotlin does not support composed types. Consider creating a single type that conforms to these types", sourceDerived: sourceDerived)
    }

    static func kotlinConstructorCannotInferPropertyType(_ sourceDerived: SourceDerived) -> Message {
        return Message(kind: .error, message: "Cannot infer property type. Declare the property type explicitly to generate a valid Kotlin constructor for this struct", sourceDerived: sourceDerived)
    }

    static func kotlinConstructorSingleDelegatingStatement(_ sourceDerived: SourceDerived) -> Message {
        return Message(kind: .error, message: "A Kotlin constructor can only include a single call to another 'this' or 'super' constructor", sourceDerived: sourceDerived)
    }

    // Idea: factory callable on companion object? Factory function with class name?
    static func kotlinConstructorNullReturn(_ sourceDerived: SourceDerived) -> Message {
        return Message(kind: .error, message: "Kotlin does not support constructors that return nil. Consider creating a factory function", sourceDerived: sourceDerived)
    }

    static func kotlinEnumModifierUnsupported(_ sourceDerived: SourceDerived) -> Message {
        return Message(kind: .warning, message: "Kotlin enum cases do not support modifiers", sourceDerived: sourceDerived)
    }

    // Idea: factory function with class name?
    static func kotlinExtensionAddConstructorsToOutsideType(_ sourceDerived: SourceDerived) -> Message {
        return Message(kind: .error, message: "Cannot use an extension to add additional constructors to a Kotlin type defined outside of this module", sourceDerived: sourceDerived)
    }

    // TODO: Kotlin interfaces can have default implementations inline. Move inheritance and implementations into generated interface
    static func kotlinExtensionAddProtocolsToInterface(_ sourceDerived: SourceDerived) -> Message {
        return Message(kind: .error, message: "Cannot use an extension to add additional protocols to a Kotlin interface", sourceDerived: sourceDerived)
    }

    static func kotlinExtensionAddProtocolsToOutsideType(_ sourceDerived: SourceDerived) -> Message {
        return Message(kind: .error, message: "Cannot use an extension to add additional protocols to a Kotlin type defined outside of this module", sourceDerived: sourceDerived)
    }

    static func kotlinExtensionUnsupportedMember(_ sourceDerived: SourceDerived) -> Message {
        return Message(kind: .error, message: "This declaration is not supported in a Kotlin extension", sourceDerived: sourceDerived)
    }

    static func kotlinInOutParameterAssignment(_ sourceDerived: SourceDerived) -> Message {
        return Message(kind: .warning, message: "Shadowing an inout parameter with a variable of the same name may produce incorrect Kotlin. Consider using a different variable name", sourceDerived: sourceDerived)
    }

    static func kotlinLoopCaseValue(_ sourceDerived: SourceDerived) -> Message {
        return Message(kind: .error, message: "Kotlin does not support case bindings to complex expressions in loop conditions. Consider assigning the expression to a local variable before the loop - e.g. let x = ...; while case let .a(...) = x", sourceDerived: sourceDerived)
    }

    static func kotlinLoopOptionalBinding(_ sourceDerived: SourceDerived) -> Message {
        return Message(kind: .error, message: "Kotlin does not support optional bindings in loop conditions. Consider using an if statement before or within your loop", sourceDerived: sourceDerived)
    }

    static func kotlinMemberAccessUnknownBaseType(_ sourceDerived: SourceDerived, member: String) -> Message {
        return Message(kind: .error, message: "Skip is unable to determine the owning type for member '\(member)'. Add the owning type (e.g. MyType.\(member))", sourceDerived: sourceDerived)
    }

    static func kotlinProtocolConstructor(_ sourceDerived: SourceDerived) -> Message {
        return Message(kind: .error, message: "Kotlin does not support constructors in protocols", sourceDerived: sourceDerived)
    }

    static func kotlinProtocolStaticFunction(_ sourceDerived: SourceDerived) -> Message {
        return Message(kind: .error, message: "Kotlin does not support static functions in protocols", sourceDerived: sourceDerived)
    }

    // Idea: duplicate body that we're falling through to (and the following if that too does a fallthrough, etc)
    static func kotlinSwitchFallthrough(_ sourceDerived: SourceDerived) -> Message {
        return Message(kind: .error, message: "Kotlin does not support fallthrough. Consider restructuring your switch statement", sourceDerived: sourceDerived)
    }

    // Idea: generate custom Kotlin data classes for additional tuple arities
    static func kotlinTupleArity(_ sourceDerived: SourceDerived) -> Message {
        return Message(kind: .error, message: "Kotlin uses Pair for 2-tuples and Triple for 3-tuples. It does not support tuples of arity > 3. Consider creating a struct instead", sourceDerived: sourceDerived)
    }

    // Idea: generate extensions on Pair and Triple for custom labels
    // Problem: where to define extensions and how to avoid duplicate definitions
    static func kotlinTupleLabels(_ sourceDerived: SourceDerived) -> Message {
        return Message(kind: .error, message: "Kotlin uses Pair for 2-tuples and Triple for 3-tuples. It does not support custom tuple element labels. Consider creating a struct instead", sourceDerived: sourceDerived)
    }

    // Idea: for typealiases that are internal, create a new top-level alias or just replace use cases with original type
    static func kotlinTypeAliasNested(_ sourceDerived: SourceDerived) -> Message {
        return Message(kind: .error, message: "Kotlin does not support typealias declarations within types. Consider moving this to a top level declaration", sourceDerived: sourceDerived)
    }

    static func kotlinViewBuilderUnsupportedStatement(_ sourceDerived: SourceDerived) -> Message {
        return Message(kind: .error, message: "This Swift construct is not supported within a @ViewBuilder when translating to Kotlin UI", sourceDerived: sourceDerived)
    }

    static func kotlinWhenCasePartialBinding(_ sourceDerived: SourceDerived) -> Message {
        return Message(kind: .error, message: "Kotlin does not support partial bindings in case matches. Match against a concrete value or all bindings", sourceDerived: sourceDerived)
    }

    static func kotlinWhenCaseWhere(_ sourceDerived: SourceDerived) -> Message {
        return Message(kind: .error, message: "Kotlin does not support where conditions in case matches. Consider using an if statement within the case body", sourceDerived: sourceDerived)
    }
}
