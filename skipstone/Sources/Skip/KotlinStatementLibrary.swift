extension IfDefined: KotlinTranslatable {
    func kotlinStatements(context: KotlinStatement.Context) -> [KotlinStatement] {
        return statements.flatMap { context.translator.translateStatement($0, context: context) }
    }
}

extension ImportDeclaration: KotlinTranslatable {
    func kotlinStatements(context: KotlinStatement.Context) -> [KotlinStatement] {
        let statement = PopulatedKotlinStatement(statement: self, context: context) { output, indentation, _ in
            output.append(indentation)
            output.append("import ")
            output.append(modulePath.joined(separator: "."))
            output.append("\n")
        }
        return [statement]
    }
}

extension MessageStatement: KotlinTranslatable {
    func kotlinStatements(context: KotlinStatement.Context) -> [KotlinStatement] {
        let statement = PopulatedKotlinStatement(statement: self, context: context)
        return [statement]
    }
}

extension ProtocolDeclaration: KotlinTranslatable {
    func kotlinStatements(context: KotlinStatement.Context) -> [KotlinStatement] {
        let statement = PopulatedKotlinStatement(statement: self, context: context) { output, indentation, children in
            output.append(indentation)
            if let declaration = extras?.declaration {
                output.append(declaration)
            } else {
                // TODO: Visibility, generics, inheritance, children
                output.append("interface ")
                output.append(name)
            }
            output.append(" {\n")
            children.forEach { output.append($0, indentation: indentation.inc()) }
            output.append(indentation)
            output.append("}\n")
        }
        return [statement]
    }
}

extension RawStatement: KotlinTranslatable {
    func kotlinStatements(context: KotlinStatement.Context) -> [KotlinStatement] {
        let sourceCode = sourceCode
        let statement = PopulatedKotlinStatement(statement: self, context: context) {  output, indentation, _ in
            output.append(indentation)
            output.append(sourceCode)
            output.append("\n")
        }
        return [statement]
    }
}
