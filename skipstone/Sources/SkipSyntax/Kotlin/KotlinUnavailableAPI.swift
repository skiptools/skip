/// Give warnings for common API that we know we do not support in Kotlin.
public class KotlinUnavailableAPI: UnavailableAPI {
    public override init() {
    }
    
    override func knownUnavailableIdentifier(_ name: String) -> (TypeSignature, String?)? {
        return nil
    }

    override func knownUnavailableMember(_ name: String, in type: TypeSignature) -> (TypeSignature, String?)? {
        return nil
    }

    override func knownUnavailableFunction(_ name: String, in type: TypeSignature?, parameters: [LabeledValue<TypeSignature>]) -> (TypeSignature, StatementType, String?)? {
        // String mutation
        if type == .string {
            if name == "append" || name == "insert" || name == "remove" || name == "removeAll" || name == "removeFirst" || name == "removeLast" || name == "removeSubrange" || name == "replaceSubrange" {
                let message = Message.kotlinStringMutation
                let arguments = parameters.map { TypeSignature.Parameter(label: $0.label, type: $0.value) }
                return (.function(arguments, .void), .functionDeclaration, message)
            }
        }
        return nil
    }
}
