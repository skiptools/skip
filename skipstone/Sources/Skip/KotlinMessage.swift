extension Message {
    static func kotlinUntranslatable(statement: Statement, source: Source? = nil, range: Source.Range? = nil) -> Message {
        return Message(severity: .error, message: "Skip cannot translate this statement to Kotlin [\(statement.type)]", source: source, range: range)
    }

    static func kotlinUntranslatable(statement: Statement) -> Message {
        return Message(severity: .error, message: "Skip cannot translate this statement to Kotlin [\(statement.type)]", file: statement.file, range: statement.range)
    }

    // List of specific untranslatable errors. This will be helpful in maintaining documentation

    static func kotlinAsyncProperties(statement: KotlinStatement) -> Message {
        return Message(severity: .error, message: "Kotlin does not support async properties. Consider using a function", file: statement.sourceFile, range: statement.sourceRange)
    }

    static func kotlinComposedTypes(statement: KotlinStatement) -> Message {
        Message(severity: .error, message: "Kotlin does not support composed types. Consider creating a single type that conforms to these types", file: statement.sourceFile, range: statement.sourceRange)
    }

    static func kotlinExtensionAddProtocolsToInterface(statement: Statement) -> Message {
        return Message(severity: .error, message: "Cannot use an extension to add additional protocols to a Kotlin interface", file: statement.file, range: statement.range)
    }

    static func kotlinExtensionAddProtocolsToOutsideType(statement: Statement) -> Message {
        return Message(severity: .error, message: "Cannot use an extension to add additional protocols to a Kotlin type defined outside of this module", file: statement.file, range: statement.range)
    }

    static func kotlinExtensionUnsupportedMember(statement: KotlinStatement) -> Message {
        return Message(severity: .error, message: "This declaration is not supported in a Kotlin extension [\(statement.type)]", file: statement.sourceFile, range: statement.sourceRange)
    }

    static func kotlinTupleArity(statement: KotlinStatement) -> Message {
        return Message(severity: .error, message: "Kotlin uses Pair for 2-tuples and Triple for 3-tuples. It does not support tuples of arity > 3. Consider creating a struct instead", file: statement.sourceFile, range: statement.sourceRange)
    }
}
