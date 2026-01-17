// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

/// Give warnings for common API that we know we do not support in Kotlin.
public final class KotlinUnavailableAPI: UnavailableAPI {
    public override init() {
    }
    
    override func knownUnavailableIdentifier(_ name: String) -> APIMatch? {
        return nil
    }

    override func knownUnavailableMember(_ name: String, in type: TypeSignature) -> APIMatch? {
        return nil
    }

    override func knownUnavailableFunction(_ name: String, in type: TypeSignature?, arguments: [LabeledValue<ArgumentValue>]) -> APIMatch? {
        // String mutation
        if type == .string {
            if name == "append" || name == "insert" || name == "remove" || name == "removeAll" || name == "removeFirst" || name == "removeLast" || name == "removeSubrange" || name == "replaceSubrange" {
                let message = Message.kotlinStringMutation
                let parameters = arguments.map { TypeSignature.Parameter(label: $0.label, type: $0.value.type) }
                return APIMatch(signature: .function(parameters, .void, APIFlags(), nil), declarationType: .functionDeclaration, memberOf: (.string, nil), availability: .unavailable(message))
            }
        }
        return nil
    }
}
