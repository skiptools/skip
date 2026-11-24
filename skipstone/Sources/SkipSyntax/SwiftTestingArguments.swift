import SwiftParser
import SwiftSyntax

/// Lowers argument collections to a Swift provider so normal type inference and
/// expression translation also apply to expressions inside `@Test(arguments:)`.
enum SwiftTestingArguments {
    static func provider(
        for declaration: FunctionDeclaration,
        syntax: FunctionDeclSyntax,
        context: DecodeContext,
        in syntaxTree: SyntaxTree
    ) -> FunctionDeclaration? {
        guard !syntaxTree.isBridgeFile, declaration.attributes.contains(.test),
              let attribute = syntax.attributes.compactMap({ $0.as(AttributeSyntax.self) }).first(where: {
                  $0.attributeName.description.trimmingCharacters(in: .whitespacesAndNewlines) == "Test"
              }), case .argumentList(let arguments) = attribute.arguments,
              let first = arguments.firstIndex(where: { $0.label?.text == "arguments" }) else {
            return nil
        }

        let collections = Array(arguments[first...])
        let parameters = Array(syntax.signature.parameterClause.parameters)
        guard !parameters.isEmpty, collections.count <= 2,
              collections.count == 1 || parameters.count == 2,
              syntax.genericParameterClause == nil,
              !declaration.parameters.contains(where: { $0.isInOut || $0.isVariadic }) else {
            declaration.messages.append(Message(
                kind: .error,
                message: "Skip supports @Test(arguments:) with one collection (including tuples), " +
                    "or two collections and two parameters; generic, inout and variadic test parameters are not supported.",
                sourceDerived: declaration
            ))
            return nil
        }

        let position = declaration.sourceRange?.start
        let name = "__skipArguments_\(declaration.name)_\(position?.line ?? 0)_\(position?.column ?? 0)"
        let types = parameters.map { $0.type.description.trimmingCharacters(in: .whitespacesAndNewlines) }

        var body: String
        if collections.count == 1 {
            let elementType = types.count == 1 ? types[0] : "(" + types.joined(separator: ", ") + ")"
            let values = types.count == 1 ? "argument" : types.indices.map { "argument.\($0)" }.joined(separator: ", ")
            body = """
            for argument in Array<\(elementType)>(\(collections[0].expression)) {
                cases.append([\(values)])
            }
            """
        } else {
            body = """
            let firstArguments = Array<\(types[0])>(\(collections[0].expression))
            let secondArguments = Array<\(types[1])>(\(collections[1].expression))
            for first in firstArguments {
                for second in secondArguments {
                    cases.append([first, second])
                }
            }
            """
        }

        let source = """
        \(context.memberOf == nil ? "" : "static ")func \(name)() -> [[Any?]] {
            var cases: [[Any?]] = []
            \(body)
            return cases
        }
        """

        let parsed = Parser.parse(source: source)
        guard let function = parsed.statements.first?.item.as(FunctionDeclSyntax.self),
              let provider = FunctionDeclaration.decode(
                  syntax: function,
                  extras: nil,
                  context: context,
                  in: syntaxTree
              )?.first as? FunctionDeclaration else {
            return nil
        }

        declaration.testArgumentsProviderName = name
        return provider
    }
}
