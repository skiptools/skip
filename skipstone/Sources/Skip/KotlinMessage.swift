extension Message {
    static func kotlinUntranslatable(_ syntaxNode: SyntaxNode, source: Source? = nil) -> Message {
        let messageString = "Skip cannot translate this statement to Kotlin [\(syntaxNode.nodeName)]"
        guard let source else {
            return Message(severity: .error, message: messageString, sourceDerived: syntaxNode)
        }
        return Message(severity: .error, message: messageString, source: source, sourceRange: syntaxNode.sourceRange)
    }

    // List of specific untranslatable errors. This will be helpful in maintaining documentation

    static func kotlinAsyncProperties(_ sourceDerived: SourceDerived) -> Message {
        return Message(severity: .error, message: "Kotlin does not support async properties. Consider using a function", sourceDerived: sourceDerived)
    }

    static func kotlinComposedTypes(_ sourceDerived: SourceDerived) -> Message {
        return Message(severity: .error, message: "Kotlin does not support composed types. Consider creating a single type that conforms to these types", sourceDerived: sourceDerived)
    }

    static func kotlinConstructorSingleDelegatingStatement(_ sourceDerived: SourceDerived) -> Message {
        return Message(severity: .error, message: "A Kotlin constructor can only include a single call to another 'this' or 'super' constructor", sourceDerived: sourceDerived)
    }

    static func kotlinConstructorNullReturn(_ sourceDerived: SourceDerived) -> Message {
        return Message(severity: .error, message: "Kotlin does not support constructors that return nil. Consider creating a factory function", sourceDerived: sourceDerived)
    }

    // TODO: Kotlin interfaces can have default implementations inline. Move inheritance and implementations into generated interface
    static func kotlinExtensionAddProtocolsToInterface(_ sourceDerived: SourceDerived) -> Message {
        return Message(severity: .error, message: "Cannot use an extension to add additional protocols to a Kotlin interface", sourceDerived: sourceDerived)
    }

    static func kotlinExtensionAddProtocolsToOutsideType(_ sourceDerived: SourceDerived) -> Message {
        return Message(severity: .error, message: "Cannot use an extension to add additional protocols to a Kotlin type defined outside of this module", sourceDerived: sourceDerived)
    }

    static func kotlinExtensionAddConstructorsToOutsideType(_ sourceDerived: SourceDerived) -> Message {
        return Message(severity: .error, message: "Cannot use an extension to add additional constructors to a Kotlin type defined outside of this module", sourceDerived: sourceDerived)
    }

    static func kotlinExtensionUnsupportedMember(_ sourceDerived: SourceDerived) -> Message {
        return Message(severity: .error, message: "This declaration is not supported in a Kotlin extension", sourceDerived: sourceDerived)
    }

    static func kotlinProtocolConstructor(_ sourceDerived: SourceDerived) -> Message {
        return Message(severity: .error, message: "Kotlin does not support constructors in protocols", sourceDerived: sourceDerived)
    }

    static func kotlinProtocolStaticFunction(_ sourceDerived: SourceDerived) -> Message {
        return Message(severity: .error, message: "Kotlin does not support static functions in protocols", sourceDerived: sourceDerived)
    }

    // TODO: Consider generating custom Kotlin data classes to work around these limitations of tuples
    static func kotlinTupleArity(_ sourceDerived: SourceDerived) -> Message {
        return Message(severity: .error, message: "Kotlin uses Pair for 2-tuples and Triple for 3-tuples. It does not support tuples of arity > 3. Consider creating a struct instead", sourceDerived: sourceDerived)
    }

    static func kotlinTupleLabels(_ sourceDerived: SourceDerived) -> Message {
        return Message(severity: .error, message: "Kotlin uses Pair for 2-tuples and Triple for 3-tuples. It does not support custom tuple element labels. Consider creating a struct instead", sourceDerived: sourceDerived)
    }

    static func kotlinViewBuilderUnsupportedStatement(_ sourceDerived: SourceDerived) -> Message {
        return Message(severity: .error, message: "This Swift construct is not supported within a @ViewBuilder when translating to Kotlin UI", sourceDerived: sourceDerived)
    }
}
