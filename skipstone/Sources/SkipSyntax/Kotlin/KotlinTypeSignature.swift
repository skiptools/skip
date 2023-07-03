extension TypeSignature {
    /// The types from the standard library that should be re-mapped to a joined form of the name.
    /// For example, Swift references to `String.Encoding.utf8` will be converted to `StringEncoding.utf8`.
    static let innerExtensions: [String: String] = [
        "Array.Index": "ArrayIndex",
        "Collection.Index": "CollectionIndex",
        "Dictionary.Index": "DictionaryIndex",
        "Set.Index": "SetIndex",
        "String.Encoding": "StringEncoding",
        "String.Index": "StringIndex",
    ]

    /// Kotlin description of this type.
    var kotlin: String {
        var signature = self
        switch self {
        case .member, .module, .named:
            for transformerType in builtinKotlinTransformerTypes {
                if let signatureTransformer = transformerType as? KotlinTypeSignatureOutputTransformer.Type {
                    signature = signatureTransformer.outputSignature(for: signature)
                }
            }
        default:
            break
        }

        switch signature {
        case .any:
            return "Any"
        case .anyObject:
            return "Any"
        case .array(let elementType):
            if elementType == .none {
                return "Array"
            }
            return "Array<\(elementType.kotlin)>"
        case .bool:
            return "Boolean"
        case .character:
            return "Char"
        case .composition:
            return "Any"
        case .dictionary(let keyType, let valueType):
            if keyType == .none && valueType == .none {
                return "Dictionary"
            }
            return "Dictionary<\(keyType.or(.any).kotlin), \(valueType.or(.any).kotlin)>"
        case .double:
            return "Double"
        case .float:
            return "Float"
        case .function(let parameters, let returnType):
            return "(\(parameters.map { $0.kotlin }.joined(separator: ", "))) -> \(returnType.kotlin)"
        case .int:
            return "Int"
        case .int8:
            return "Byte"
        case .int16:
            return "Short"
        case .int32:
            return "Int"
        case .int64:
            return "Long"
        case .member(let baseType, let type):
            let typeName = "\(baseType.kotlin).\(type.kotlin)"
            //~~~ No more need for innerExtensions
            return Self.innerExtensions[typeName] ?? typeName
        case .metaType(let baseType):
            return "KClass<\(baseType.kotlin)>"
        case .module(let module, let type):
            return "\(KotlinTranslator.packageName(forModule: module)).\(type.kotlin)"
        case .named(let name, let generics):
            guard !generics.isEmpty && generics.contains(where: { $0 != .none }) else {
                return name
            }
            return "\(name)<\(generics.map { $0.kotlin }.joined(separator: ", "))>"
        case .none:
            return description
        case .optional(let type):
            switch type {
            case .function:
                return "(\(type.kotlin))?"
            default:
                return "\(type.kotlin)?"
            }
        case .range(let elementType):
            switch elementType {
            case .character:
                return "CharRange"
            case .int64:
                return "LongRange"
            default:
                return "IntRange"
            }
        case .set(let elementType):
            if elementType == .none {
                return "Set"
            }
            return "Set<\(elementType.kotlin)>"
        case .string:
            return "String"
        case .tuple(_, let types):
            if types.isEmpty {
                return "Unit"
            }
            let generics = types.map { $0.kotlin }.joined(separator: ", ")
            if types.count <= KotlinTupleLiteral.maximumArity {
                return "Tuple\(types.count)<\(generics)>"
            } else {
                return "Any"
            }
        case .typealiased(_, let type):
            return type.kotlin
        case .uint:
            return "UInt"
        case .uint8:
            return "UByte"
        case .uint16:
            return "UShort"
        case .uint32:
            return "UInt"
        case .uint64:
            return "ULong"
        case .unwrappedOptional(let type):
            return type.kotlin
        case .void:
            return "Unit"
        }
    }

    static func kotlinComparable(for type: TypeSignature) -> TypeSignature {
        return .named("Comparable", [type])
    }

    /// Add appropriate messages if this type is not supported.
    func appendKotlinMessages(to node: KotlinSyntaxNode, source: Source) {
        var messages: [Message] = []
        visit {
            switch $0 {
            case .composition:
                messages.append(.kotlinComposedTypes(node, source: source))
            case .tuple(let labels, _):
                if labels.count > KotlinTupleLiteral.maximumArity {
                    messages.append(.kotlinTupleArity(node, source: source))
                }
            default:
                break
            }
            return .recurse(nil)
        }
        node.messages += messages
    }

    /// Whether this type might represent a shared mutable struct.
    func kotlinMayBeSharedMutableStruct(codebaseInfo: CodebaseInfo.Context?) -> Bool {
        switch self {
        case .any:
            return true
        case .anyObject:
            return false
        case .array:
            return true
        case .bool:
            return false
        case .character:
            return false
        case .composition(let types):
            return !types.contains { $0.kotlinMayBeSharedMutableStruct(codebaseInfo: codebaseInfo) == false }
        case .dictionary:
            return true
        case .double:
            return false
        case .float:
            return false
        case .function:
            return false
        case .int:
            return false
        case .int8:
            return false
        case .int16:
            return false
        case .int32:
            return false
        case .int64:
            return false
        case .member, .module, .named:
            guard let codebaseInfo else {
                return true
            }
            return codebaseInfo.mayBeMutableStruct(type: self)
        case .metaType:
            return false
        case .none:
            return true
        case .optional(let type):
            return type.kotlinMayBeSharedMutableStruct(codebaseInfo: codebaseInfo)
        case .range:
            return false
        case .set:
            return true
        case .string:
            return false
        case .tuple(_, let types):
            // We consider a tuple with a shared mutable type to itself be a shared mutable type because code may
            // use destructuring assignment to extract values without copying them, so we have to copy the whole tuple
            return types.contains { $0.kotlinMayBeSharedMutableStruct(codebaseInfo: codebaseInfo) }
        case .typealiased(_, let type):
            return type.kotlinMayBeSharedMutableStruct(codebaseInfo: codebaseInfo)
        case .uint:
            return false
        case .uint8:
            return false
        case .uint16:
            return false
        case .uint32:
            return false
        case .uint64:
            return false
        case .unwrappedOptional(let type):
            return type.kotlinMayBeSharedMutableStruct(codebaseInfo: codebaseInfo)
        case .void:
            return false
        }
    }

    /// Whether this type is a Kotlin primitive.
    func kotlinIsNative(primitive: Bool = false) -> Bool {
        switch self {
        case .any:
            return !primitive
        case .anyObject:
            return !primitive
        case .array:
            return false
        case .bool:
            return true
        case .character:
            return true
        case .composition:
            return false
        case .dictionary:
            return false
        case .double:
            return true
        case .float:
            return true
        case .function:
            return false
        case .int:
            return true
        case .int8:
            return true
        case .int16:
            return true
        case .int32:
            return true
        case .int64:
            return true
        case .named:
            return false
        case .none:
            return false
        case .optional(let type):
            return type.kotlinIsNative(primitive: primitive)
        case .member:
            return false
        case .metaType(let type):
            return !primitive && type.kotlinIsNative()
        case .module(_, let type):
            return type.kotlinIsNative(primitive: primitive)
        case .range:
            return !primitive
        case .set:
            return false
        case .string:
            return !primitive
        case .tuple:
            return false
        case .typealiased(_, let type):
            return type.kotlinIsNative(primitive: primitive)
        case .uint:
            return true
        case .uint8:
            return true
        case .uint16:
            return true
        case .uint32:
            return true
        case .uint64:
            return true
        case .unwrappedOptional(let type):
            return type.kotlinIsNative(primitive: primitive)
        case .void:
            return !primitive
        }
    }

    /// Whether this type represents an enum modeled with sealed classes.
    func kotlinIsSealedClassesEnum(codebaseInfo: CodebaseInfo.Context?) -> Bool {
        switch asOptional(false) {
        case .named, .member, .module:
            return codebaseInfo?.isSealedClassesEnum(type: self) == true
        case .typealiased(_, let type):
            return type.kotlinIsSealedClassesEnum(codebaseInfo: codebaseInfo)
        default:
            return false
        }
    }

    /// Whether this type uses `KClass`, which requires additional imports.
    var kotlinReferencesKClass: Bool {
        var references = false
        visit {
            if references {
                return .skip
            } else if case .metaType = $0 {
                references = true
                return .skip
            }
            return .recurse(nil)
        }
        return references
    }
}

extension TypeSignature.Parameter {
    /// Kotlin description of this parameter.
    var kotlin: String {
        return type.kotlin
    }
}
