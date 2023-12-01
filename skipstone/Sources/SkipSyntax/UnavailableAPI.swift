/// A transpiler plugin to be able to warn the developer about potential uses of unavailable API when we don't have complete codebase info.
///
/// These functions are used in preflight checks where we do not have codebase info and type information is sparse.
/// Use only to warn about common API that we know we do not support. It is likely rare that we'll be able to even
/// supply enough type information to match these functions, but we have a chance of catching obvious types like
/// string and array literals, etc.
///
/// We implement this as an extendable class rather than a protocol to avoid making the types used in its API public.
public class UnavailableAPI {
    /// Check if this is an identifier that is known to be unavailable.
    func knownUnavailableIdentifier(_ name: String) -> APIMatch? {
        return nil
    }

    /// Check if this is a member that is known to be unavailable.
    func knownUnavailableMember(_ name: String, in type: TypeSignature) -> APIMatch? {
        return nil
    }

    /// Check if this is a function that is known to be unavailable.
    func knownUnavailableFunction(_ name: String, in type: TypeSignature?, arguments: [LabeledValue<ArgumentValue>]) -> APIMatch? {
        return nil
    }
}
