// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

extension KotlinClassDeclaration {
    /// `RawRepresentable` raw value type.
    var rawValueType: TypeSignature {
        let (constructor, property) = rawValueMembers
        if let constructor {
            return constructor.parameters[0].declaredType
        } else if let property {
            return property.propertyType
        } else {
            return enumInheritedRawValueType
        }
    }

    /// `RawRepresentable` constructor and value property.
    var rawValueMembers: (KotlinFunctionDeclaration?, KotlinVariableDeclaration?) {
        let constructors = members.compactMap { (member: KotlinStatement) -> KotlinFunctionDeclaration? in
            guard member.type == .constructorDeclaration else {
                return nil
            }
            return member as? KotlinFunctionDeclaration
        }
        let rawValueConstructor = constructors.first { $0.parameters.count == 1 && $0.parameters[0].externalLabel == "rawValue" }
        let variables = members.compactMap { (member: KotlinStatement) -> KotlinVariableDeclaration? in
            guard member.type == .variableDeclaration else {
                return nil
            }
            return member as? KotlinVariableDeclaration
        }
        let rawValueVariable = variables.first { $0.propertyName == "rawValue" }
        return (rawValueConstructor, rawValueVariable)
    }
}

extension TypeSignature {
    /// Lookup the raw value type of this `RawRepresentable` type.
    func rawValueType(codebaseInfo: CodebaseInfo.Context) -> TypeSignature {
        guard isNamedType else {
            return .none
        }
        guard let rawValue = codebaseInfo.matchIdentifier(name: "rawValue", inConstrained: self), rawValue.declarationType == .variableDeclaration else {
            return .none
        }
        return rawValue.signature
    }
}
