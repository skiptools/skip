extension IfDefined: KotlinTranslatable {
    func kotlinStatements(translator: KotlinTranslator) -> [KotlinStatement] {
        return statements.flatMap { translator.translateStatement($0) }
    }
}

extension MessageStatement: KotlinTranslatable {
    func kotlinStatements(translator: KotlinTranslator) -> [KotlinStatement] {
        let statement = PopulatedKotlinStatement(statement: self, translator: translator)
        return [statement]
    }
}

extension RawStatement: KotlinTranslatable {
    func kotlinStatements(translator: KotlinTranslator) -> [KotlinStatement] {
        let sourceCode = self.sourceCode
        let statement = PopulatedKotlinStatement(statement: self, translator: translator) { output, indentation, _ in
            output.append(indentation)
            output.append(sourceCode)
            output.append("\n")
        }
        return [statement]
    }
}

// MARK: - Declarations

extension ClassDeclaration: KotlinTranslatable {
    func kotlinStatements(translator: KotlinTranslator) -> [KotlinStatement] {
        let name = self.name
        let extras = self.extras
        let statement = PopulatedKotlinStatement(statement: self, translator: translator) { output, indentation, children in
            output.append(indentation)
            if let declaration = extras?.declaration {
                output.append(declaration)
            } else {
                // TODO: Visibility, generics, inheritance, children
                output.append("class ")
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

extension ExtensionDeclaration: KotlinTranslatable {
    func kotlinStatements(translator: KotlinTranslator) -> [KotlinStatement] {
        let extends = self.extends.description
        let statement = PopulatedKotlinStatement(statement: self, translator: translator) { output, indentation, children in
            output.append(indentation)
            if let declaration = extras?.declaration {
                output.append(declaration)
            } else {
                // TODO: Visibility, generics, inheritance, children
                output.append(" ")
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

extension FunctionDeclaration: KotlinTranslatable {
    
}

extension ImportDeclaration: KotlinTranslatable {
    func kotlinStatements(translator: KotlinTranslator) -> [KotlinStatement] {
        let modulePath = self.modulePath
        let statement = PopulatedKotlinStatement(statement: self, translator: translator) { output, indentation, _ in
            output.append(indentation)
            output.append("import ")
            output.append(modulePath.joined(separator: "."))
            output.append("\n")
        }
        return [statement]
    }
}

extension ProtocolDeclaration: KotlinTranslatable {
    func kotlinStatements(translator: KotlinTranslator) -> [KotlinStatement] {
        let name = self.name
        let extras = self.extras
        let statement = PopulatedKotlinStatement(statement: self, translator: translator) { output, indentation, children in
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
