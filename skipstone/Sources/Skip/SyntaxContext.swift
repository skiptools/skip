/// Contextual information available from the syntax tree.
struct SyntaxContext {
    //~~~ Add codebase info
    var typeDeclarationPath: [TypeDeclaration] = []
    var localVariableDeclarations: [VariableDeclaration] = []
    var localParameters: [Parameter<Expression>] = []
}

/* ~~~
/// Find the nearest type declaration by traversing up the syntax tree.
final var owningTypeDeclaration: TypeDeclaration? {
    var current: SyntaxNode? = self
    while current != nil {
        if let typeDeclaration = current as? TypeDeclaration {
            return typeDeclaration
        }
        current = current?.parent
    }
    return nil
}

/// Traverse up the syntax tree to fully qualify a type name.
final func qualifyReferencedTypeName(_ typeName: String) -> String {
    // Look for a qualified name whose last token(s) are the given type name
    let suffix = ".\(typeName)"
    var current: SyntaxNode? = self
    while current != nil {
        // Find the next declared type up the statement chain
        guard let owningType = current?.owningTypeDeclaration else {
            break
        }
        // Look for any direct child of that type with a matching qualified name
        if let referencedType = owningType.children.first(where: { ($0 as? TypeDeclaration)?.qualifiedName.hasSuffix(suffix) == true }) {
            return (referencedType as! TypeDeclaration).qualifiedName
        }
        // Move up to the next owning type and repeat
        current = owningType.parent
    }
    return typeName
}

/// Traverse up the syntax tree to fully qualify a type name declared by a class, struct, etc.
final func qualifyDeclaredTypeName(_ typeName: String) -> String {
    if let typeDeclaration = parent?.owningTypeDeclaration {
        return "\(typeDeclaration.qualifiedName).\(typeName)"
    }
    return typeName
}





 override func resolve() {
     if let declaredType {
         self.declaredType = declaredType.qualified(in: self)
     }
     // Variables in protocols or extensions inherit the visibility of the protocol or extension
     if modifiers.visibility == .default, let owningTypeDeclaration, owningTypeDeclaration === parent, (owningTypeDeclaration.type == .protocolDeclaration || owningTypeDeclaration.type == .extensionDeclaration) {
         modifiers.visibility = owningTypeDeclaration.modifiers.visibility
     }
 }



 override func resolve() {
     if let returnType {
         self.returnType = returnType.qualified(in: self)
     }
     parameters = parameters.map { $0.qualifiedType(in: self) }
     // Functions in protocols or extensions inherit the visibility of the protocol or extension
     if modifiers.visibility == .default, let owningTypeDeclaration, (owningTypeDeclaration.type == .protocolDeclaration || owningTypeDeclaration.type == .extensionDeclaration) {
         modifiers.visibility = owningTypeDeclaration.modifiers.visibility
     }
 }


 override func resolve() {
     if _qualifiedName == nil {
         _qualifiedName = qualifyDeclaredTypeName(name)
     }
     inherits = inherits.map { $0.qualified(in: self) }
 }
*/
