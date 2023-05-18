/// Disambiguate Kotlin functions translated from Swift functions that are only differentkated on their parameter labels.
final class KotlinDisambiguateFunctionsTransformer: KotlinTransformer {
    func prepareForUse(codebaseInfo: CodebaseInfo?) {
        guard let codebaseInfo else {
            return
        }
        for functionInfo in codebaseInfo.rootFunctions {
            initializeDisambiguatingParameterCounts(for: functionInfo, codebaseInfo: codebaseInfo)
        }
        for typeInfo in codebaseInfo.rootTypes {
            initializeDisambiguatingParameterCounts(for: typeInfo, codebaseInfo: codebaseInfo)
        }
        for extensionInfo in codebaseInfo.rootExtensions {
            for functionInfo in extensionInfo.members.compactMap({ $0 as? CodebaseInfo.FunctionInfo }) {
                initializeDisambiguatingParameterCounts(for: functionInfo, codebaseInfo: codebaseInfo)
            }
        }
    }

    private func initializeDisambiguatingParameterCounts(for typeInfo: CodebaseInfo.TypeInfo, codebaseInfo: CodebaseInfo) {
        for memberInfo in typeInfo.members {
            if let typeInfo = memberInfo as? CodebaseInfo.TypeInfo {
                initializeDisambiguatingParameterCounts(for: typeInfo, codebaseInfo: codebaseInfo)
            } else if let functionInfo = memberInfo as? CodebaseInfo.FunctionInfo {
                initializeDisambiguatingParameterCounts(for: functionInfo, codebaseInfo: codebaseInfo)
            }
        }
    }

    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        if let codebaseInfo = translator.codebaseInfo {
            syntaxTree.root.visit { visit($0, codebaseInfo: codebaseInfo) }
        }
    }

    func messages(for sourceFile: Source.FilePath) -> [Message] {
        return messages[sourceFile] ?? []
    }

    private func visit(_ node: KotlinSyntaxNode, codebaseInfo: CodebaseInfo.Context) -> VisitResult<KotlinSyntaxNode> {
        if let classDeclaration = node as? KotlinClassDeclaration {
            let functionDeclarations = classDeclaration.members.compactMap { $0 as? KotlinFunctionDeclaration }
            functionDeclarations.forEach { disambiguateFunctionDeclaration($0, in: classDeclaration.signature, codebaseInfo: codebaseInfo) }
        } else if let interfaceDeclaration = node as? KotlinInterfaceDeclaration {
            let functionDeclarations = interfaceDeclaration.members.compactMap { $0 as? KotlinFunctionDeclaration }
            functionDeclarations.forEach { disambiguateFunctionDeclaration($0, in: interfaceDeclaration.signature, codebaseInfo: codebaseInfo) }
        } else if let functionDeclaration = node as? KotlinFunctionDeclaration {
            if functionDeclaration.isGlobal || functionDeclaration.extends != nil {
                disambiguateFunctionDeclaration(functionDeclaration, in: functionDeclaration.extends?.0, codebaseInfo: codebaseInfo)
            }
        }
        return .recurse(nil)
    }

    private func disambiguateFunctionDeclaration(_ functionDeclaration: KotlinFunctionDeclaration, in type: TypeSignature?, codebaseInfo: CodebaseInfo.Context) {
        // We disambiguate functions that have the same name and parameter types but different parameter labels by appending extra
        // unused parameters to satisfy the Kotlin compiler. Because labels are not part of the function signature, we have to
        // append different numbers of extra parameters for each conflicting version
        functionDeclaration.disambiguatingParameterCount = disambiguatingParameterCount(for: functionDeclaration, in: type, codebaseInfo: codebaseInfo)
    }

    private var disambiguatingParameterCounts: [Key: [ParameterCount]] = [:]
    private var messages: [Source.FilePath: [Message]] = [:]

    private func disambiguatingParameterCount(for functionDeclaration: KotlinFunctionDeclaration, in type: TypeSignature?, codebaseInfo: CodebaseInfo.Context) -> Int {
        guard !functionDeclaration.parameters.isEmpty else {
            return 0
        }
        let key = Key(for: functionDeclaration, in: type)
        guard let counts = disambiguatingParameterCounts[key] else {
            return 0
        }
        guard let count = counts.first(where: { $0.isMatch(for: functionDeclaration, in: type, codebaseInfo: codebaseInfo) }) else {
            return 0
        }
        return count.count
    }

    private func initializeDisambiguatingParameterCounts(for functionInfo: CodebaseInfo.FunctionInfo, codebaseInfo: CodebaseInfo) {
        let key = Key(for: functionInfo)
        guard !disambiguatingParameterCounts.keys.contains(key) else {
            return
        }
        let counts = initializeDisambiguatingParameterCounts(for: key, in: functionInfo.declaringType, codebaseInfo: codebaseInfo)
        disambiguatingParameterCounts[key] = counts
    }

    private func initializeDisambiguatingParameterCounts(for key: Key, in type: TypeSignature?, codebaseInfo: CodebaseInfo) -> [ParameterCount] {
        // First group same-param-type function infos on labels, and only process cases that have potential conflicts
        let infos = nonOverrideFunctionInfos(for: key, in: type, codebaseInfo: codebaseInfo)
        guard infos.count > 1 else {
            return []
        }
        let labelGroups = infos.reduce(into: [String: [CodebaseInfo.FunctionInfo]]()) { result, info in
            let parameters = info.signature.parameters
            guard !parameters.isEmpty else {
                return
            }
            let labels = parameters.map { $0.label ?? "" }.joined(separator: ", ")
            var infos = result[labels, default: []]
            infos.append(info)
            result[labels] = infos
        }
        guard labelGroups.count > 1 else {
            return []
        }
        // Sort to give more deterministic output
        let labelDeclarers = labelGroups.sorted {
            $0.key < $1.key
        }.flatMap {
            return $0.value.map { LabelDeclarer(for: $0, codebaseInfo: codebaseInfo) }
        }

        // Resolve conflicts in protocols, then resolve concrete types so that implementing functions use protocol counts
        let protocolDeclarers = labelDeclarers.filter { $0.inheritanceChain.isEmpty && !$0.protocols.isEmpty }
        let concreteDeclarers = labelDeclarers.filter { !$0.inheritanceChain.isEmpty || $0.protocols.isEmpty }
        var labelCounts: [LabelKey: Int] = [:]
        var nextCount = 1
        initializeLabelCounts(key: key, labelDeclarers: protocolDeclarers, labelCounts: &labelCounts, nextCount: &nextCount)
        initializeLabelCounts(key: key, labelDeclarers: concreteDeclarers, labelCounts: &labelCounts, nextCount: &nextCount)

        return labelCounts.compactMap { (labelKey, count) -> ParameterCount? in
            guard count > 0 else {
                return nil
            }
            return ParameterCount(labels: labelKey.parameters.map(\.label), declaringType: labelKey.declaringType, isInit: key.isInit, count: count)
        }
    }

    private func initializeLabelCounts(key: Key, labelDeclarers: [LabelDeclarer], labelCounts: inout [LabelKey: Int], nextCount: inout Int) {
        // Brute force comparison to see if a given declarer is in the inheritance or protocol chains of any other label group, causing a conflict.
        // Assign each conflict a unique count, which means that we may be adding higher counts than needed but simplifies things a little
        for i in 0..<labelDeclarers.count {
            // Have we already mapped this?
            let labelKey = LabelKey(parameters: labelDeclarers[i].parameters, declaringType: labelDeclarers[i].type)
            if labelCounts.keys.contains(labelKey) {
                continue
            }
            // Or have we mapped this for a protocol of ours? We shouldn't have to check superclasses because we filter function overrides out
            let (iProtocolMatch, iProtocolCount) = protocolLabelCount(of: labelDeclarers[i], in: labelCounts)
            // Any positive count is unique because we always increment
            if let iProtocolCount, iProtocolCount > 0 {
                continue
            }
            var count = 0
            for j in 0..<labelDeclarers.count {
                // Compare to every other with a different label group
                if i == j || labelDeclarers[i].parameters == labelDeclarers[j].parameters {
                    continue
                }
                // If neither is in this module, we can't do anything
                if !labelDeclarers[i].isInModule && !labelDeclarers[j].isInModule {
                    continue
                }
                // If not related, there is no conflict
                if !labelDeclarers[i].isKind(of: labelDeclarers[j]) {
                    continue
                }
                // If the other side is already mapped, no need to map this side
                if let jCount = labelCounts[LabelKey(parameters: labelDeclarers[j].parameters, declaringType: labelDeclarers[j].type)] {
                    if jCount > 0 {
                        continue
                    }
                }
                let (jProtocolMatch, jProtocolCount) = protocolLabelCount(of: labelDeclarers[j], in: labelCounts)
                if let jProtocolCount, jProtocolCount > 0 {
                    continue
                }
                // Should we map the other side?
                if !labelDeclarers[i].isInModule || (iProtocolMatch != nil && jProtocolMatch == nil) || (jProtocolMatch == nil && !labelDeclarers[j].isImplementable && labelDeclarers[i].isImplementable) {
                    if !warn(key: key, for: labelDeclarers[j], protocolMatch: jProtocolMatch) {
                        labelCounts[LabelKey(parameters: labelDeclarers[j].parameters, declaringType: labelDeclarers[j].type)] = nextCount
                        nextCount += 1
                    }
                    continue
                } else {
                    if !warn(key: key, for: labelDeclarers[i], protocolMatch: iProtocolMatch) {
                        count = nextCount
                        nextCount += 1
                    }
                    break
                }
            }
            labelCounts[labelKey] = count
        }
    }

    private func protocolLabelCount(of declarer: LabelDeclarer, in labelCounts: [LabelKey: Int]) -> (TypeSignature?, Int?) {
        for p in declarer.protocols {
            if let count = labelCounts[LabelKey(parameters: declarer.parameters, declaringType: p)] {
                return (p, count)
            }
        }
        return (nil, nil)
    }

    private func warn(key: Key, for declarer: LabelDeclarer, protocolMatch: TypeSignature?) -> Bool {
        if declarer.isImplementable {
            if let sourceFile = declarer.sourceFile {
                var fileMessages = messages[sourceFile, default: []]
                fileMessages.append(.kotlinFunctionDisambiguateImplementable(name: key.name, parameters: key.parameterTypes, in: declarer.type, sourceFile: sourceFile))
                messages[sourceFile] = fileMessages
            }
            return true
        } else if protocolMatch != nil {
            if let sourceFile = declarer.sourceFile {
                var fileMessages = messages[sourceFile, default: []]
                fileMessages.append(.kotlinFunctionDisambiguateProtocol(name: key.name, parameters: key.parameterTypes, in: declarer.type, sourceFile: sourceFile))
                messages[sourceFile] = fileMessages
            }
            return true
        } else {
            return false
        }
    }

    /// - Note: This function includes `private` members that may not be visible to this context. It does **not** include override members.
    private func nonOverrideFunctionInfos(for key: Key, in type: TypeSignature?, codebaseInfo: CodebaseInfo) -> [CodebaseInfo.FunctionInfo] {
        let candidates: [CodebaseInfoItem]
        if let type, key.isInit {
            candidates = codebaseInfo.typeInfos(forNamed: type).flatMap {
                $0.functions.filter { $0.declarationType == .initDeclaration }
            }
        } else {
            candidates = codebaseInfo.lookup(name: key.name).filter { $0.declarationType == .functionDeclaration && !$0.modifiers.isOverride }
        }
        return candidates.compactMap { info in
            guard let functionInfo = info as? CodebaseInfo.FunctionInfo else {
                return nil
            }
            return key.parameterTypes == functionInfo.signature.parameters.map(\.type) ? functionInfo: nil
        }
    }
}

private struct Key: Hashable {
    let name: String
    let isInit: Bool
    let parameterTypes: [TypeSignature]

    init(for functionInfo: CodebaseInfo.FunctionInfo) {
        self.isInit = functionInfo.declarationType == .initDeclaration
        self.name = self.isInit ? (functionInfo.declaringType?.name ?? "") : functionInfo.name
        self.parameterTypes = functionInfo.signature.parameters.map(\.type)
    }

    init(for functionDeclaration: KotlinFunctionDeclaration, in type: TypeSignature?) {
        self.isInit = functionDeclaration.type == .constructorDeclaration
        self.name = self.isInit ? (type?.name ?? "") : functionDeclaration.name
        self.parameterTypes = functionDeclaration.functionType.parameters.map(\.type)
    }
}

private struct ParameterCount {
    let labels: [String?]
    let declaringType: TypeSignature?
    let isInit: Bool
    let count: Int

    func isMatch(for functionDeclaration: KotlinFunctionDeclaration, in type: TypeSignature?, codebaseInfo: CodebaseInfo.Context) -> Bool {
        return isInit == (functionDeclaration.type == .constructorDeclaration) && isTypeMatch(type, codebaseInfo: codebaseInfo) && labels == functionDeclaration.parameters.map(\.externalLabel)
    }

    private func isTypeMatch(_ type: TypeSignature?, codebaseInfo: CodebaseInfo.Context) -> Bool {
        guard let type else {
            return declaringType == nil
        }
        guard let declaringType else {
            return false
        }
        if type == declaringType {
            return true
        }
        return !isInit && (codebaseInfo.global.inheritanceChainSignatures(forNamed: type).contains(declaringType) || codebaseInfo.global.protocolSignatures(forNamed: type).contains(declaringType))
    }
}

private struct LabelKey: Hashable {
    let parameters: [TypeSignature.Parameter]
    let declaringType: TypeSignature?
}

private struct LabelDeclarer {
    let parameters: [TypeSignature.Parameter]
    let type: TypeSignature?
    let inheritanceChain: [TypeSignature]
    let protocols: [TypeSignature]
    let isInModule: Bool
    let visibility: Modifiers.Visibility
    let sourceFile: Source.FilePath?

    init(for functionInfo: CodebaseInfo.FunctionInfo, codebaseInfo: CodebaseInfo) {
        self.parameters = functionInfo.signature.parameters
        self.type = functionInfo.declaringType
        if let type {
            if functionInfo.declarationType == .initDeclaration {
                self.inheritanceChain = [type]
                self.protocols = []
            } else {
                self.inheritanceChain = codebaseInfo.inheritanceChainSignatures(forNamed: type)
                self.protocols = codebaseInfo.protocolSignatures(forNamed: type)
            }
        } else {
            self.inheritanceChain = []
            self.protocols = []
        }
        self.isInModule = functionInfo.moduleName == codebaseInfo.moduleName
        self.visibility = functionInfo.modifiers.visibility
        self.sourceFile = functionInfo.sourceFile
    }

    func isKind(of labelDeclarer: LabelDeclarer) -> Bool {
        guard let ldtype = labelDeclarer.type else {
            return type == nil
        }
        return inheritanceChain.contains(ldtype) || protocols.contains(ldtype)
    }

    var isImplementable: Bool {
        return visibility == .open || (visibility == .public && inheritanceChain.isEmpty && !protocols.isEmpty)
    }
}
