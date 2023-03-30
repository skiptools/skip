/// Uniquify Kotlin functions translated from Swift functions that are only differentkated on their parameter labels.
class KotlinUniquifyFunctionSignaturesPlugin: KotlinPlugin {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        if let codebaseInfo = translator.codebaseInfo {
            syntaxTree.root.visit { visit($0, codebaseInfo: codebaseInfo) }
        }
    }

    private func visit(_ node: KotlinSyntaxNode, codebaseInfo: KotlinCodebaseInfo.Context) -> VisitResult<KotlinSyntaxNode> {
        if let classDeclaration = node as? KotlinClassDeclaration {
            let functionDeclarations = classDeclaration.members.compactMap { $0 as? KotlinFunctionDeclaration }
            functionDeclarations.forEach { uniquifyFunctionDeclaration($0, in: classDeclaration.signature, codebaseInfo: codebaseInfo) }
        } else if let functionDeclaration = node as? KotlinFunctionDeclaration {
            if functionDeclaration.isGlobal || functionDeclaration.extends != nil {
                uniquifyFunctionDeclaration(functionDeclaration, in: functionDeclaration.extends, codebaseInfo: codebaseInfo)
            }
        }
        return .recurse(nil)
    }

    private func uniquifyFunctionDeclaration(_ functionDeclaration: KotlinFunctionDeclaration, in type: TypeSignature?, codebaseInfo: KotlinCodebaseInfo.Context) {
        // We uniquify functions that have the same name and parameter types but different parameter labels by appending extra
        // unused parameters to satisfy the Kotlin compiler. Because labels are not part of the function signature, we have to
        // append different numbers of extra parameters for each conflicting version
        functionDeclaration.uniquifyingParameterCount = uniquifyingParameterCount(for: functionDeclaration, in: type, codebaseInfo: codebaseInfo)
    }

    private var uniquifyingParameterCounts: [Key: [ParameterCount]] = [:]

    private func uniquifyingParameterCount(for functionDeclaration: KotlinFunctionDeclaration, in type: TypeSignature?, codebaseInfo: KotlinCodebaseInfo.Context) -> Int {
        guard !functionDeclaration.parameters.isEmpty else {
            return 0
        }
        let key = Key(for: functionDeclaration)
        let counts: [ParameterCount]
        if let cachedCounts = uniquifyingParameterCounts[key] {
            counts = cachedCounts
        } else {
            counts = initializeUniquifyingParameterCounts(for: key, codebaseInfo: codebaseInfo)
            uniquifyingParameterCounts[key] = counts
        }
        if let count = counts.first(where: { $0.isMatch(for: functionDeclaration, in: type, codebaseInfo: codebaseInfo) }) {
            return count.count
        } else {
            return 0
        }
    }

    private func initializeUniquifyingParameterCounts(for key: Key, codebaseInfo: KotlinCodebaseInfo.Context) -> [ParameterCount] {
        // First group same-param-type function infos on labels, and only process cases that have potential conflicts
        let infos = nonOverrideFunctionInfos(for: key.name, parameterTypes: key.parameterTypes, codebaseInfo: codebaseInfo)
        guard infos.count > 1 else {
            return []
        }
        let labelGroups = infos.reduce(into: [String: [CodebaseInfo.FunctionInfo]]()) { result, info in
            guard case .function(let parameters, _) = info.signature, parameters.count > 0 else {
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

        // First resolve conflicts in protocols, then resolve concrete types so that implementing functions use protocol counts
        let protocolDeclarers = labelDeclarers.filter { $0.inheritanceChain.isEmpty && !$0.protocols.isEmpty }
        let concreteDeclarers = labelDeclarers.filter { !$0.inheritanceChain.isEmpty || $0.protocols.isEmpty }
        var labelCounts: [LabelKey: Int] = [:]
        var nextCount = 1
        initializeLabelCounts(for: protocolDeclarers, labelCounts: &labelCounts, nextCount: &nextCount)
        initializeLabelCounts(for: concreteDeclarers, labelCounts: &labelCounts, nextCount: &nextCount)

        return labelCounts.compactMap { (labelKey, count) -> ParameterCount? in
            guard count > 0 else {
                return nil
            }
            return ParameterCount(labels: labelKey.parameters.map(\.label), declaringType: labelKey.declaringType, isInit: key.name == "init", count: count)
        }
    }

    private func initializeLabelCounts(for labelDeclarers: [LabelDeclarer], labelCounts: inout [LabelKey: Int], nextCount: inout Int) {
        // Brute force comparison to see if a given declarer is in the inheritance or protocol chains of any other label group, causing a conflict.
        // Assign each conflict a unique count, which means that we may be adding higher counts than needed but simplifies things a little
        for i in 0..<labelDeclarers.count {
            // Have we already mapped this?
            let key = LabelKey(parameters: labelDeclarers[i].parameters, declaringType: labelDeclarers[i].type)
            if labelCounts.keys.contains(key) {
                continue
            }
            // Or have we mapped this for a protocol of ours? We shouldn't have to check superclasses because we filter function overrides out
            let (pMatch, pCount) = protocolLabelCount(of: labelDeclarers[i], in: labelCounts)
            // Any positive count is unique because we always increment
            if let pCount, pCount > 0 {
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
                let (pjMatch, pjCount) = protocolLabelCount(of: labelDeclarers[j], in: labelCounts)
                if let pjCount, pjCount > 0 {
                    continue
                }
                // Should we map the other side?
                if !labelDeclarers[i].isInModule || (pCount != nil && pjCount == nil) || (pjCount == nil && !labelDeclarers[j].isImplementable && labelDeclarers[i].isImplementable) {
                    if !warn(for: labelDeclarers[j], protocolMatch: pjMatch) {
                        labelCounts[LabelKey(parameters: labelDeclarers[j].parameters, declaringType: labelDeclarers[j].type)] = nextCount
                        nextCount += 1
                    }
                    continue
                } else {
                    if !warn(for: labelDeclarers[i], protocolMatch: pMatch) {
                        count = nextCount
                        nextCount += 1
                    }
                    break
                }
            }
            labelCounts[key] = count
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

    private func warn(for declarer: LabelDeclarer, protocolMatch: TypeSignature?) -> Bool {
        if declarer.isImplementable {
            //~~~ warn
            return true
        } else if protocolMatch != nil {
            //~~~ warn
            return true
        } else {
            return false
        }
    }

    /// - Note: This function includes `private` members that may not be visible to this context. It does **not** include override members.
    private func nonOverrideFunctionInfos(for name: String, parameterTypes: [TypeSignature], codebaseInfo: KotlinCodebaseInfo.Context) -> [CodebaseInfo.FunctionInfo] {
        return codebaseInfo.context.lookup(name: name).compactMap { info in
            guard let functionInfo = info as? CodebaseInfo.FunctionInfo, case .function(let parameters, _) = functionInfo.signature else {
                return nil
            }
            return (functionInfo.declarationType == .initDeclaration || !functionInfo.modifiers.isOverride) && parameterTypes == parameters.map(\.type) ? functionInfo: nil
        }
    }
}

private struct Key: Hashable {
    let name: String
    let parameterTypes: [TypeSignature]

    init(for functionDeclaration: KotlinFunctionDeclaration) {
        self.name = functionDeclaration.name
        self.parameterTypes = functionDeclaration.parameters.map(\.declaredType)
    }
}

private struct ParameterCount {
    let labels: [String?]
    let declaringType: TypeSignature?
    let isInit: Bool
    let count: Int

    func isMatch(for functionDeclaration: KotlinFunctionDeclaration, in type: TypeSignature?, codebaseInfo: KotlinCodebaseInfo.Context) -> Bool {
        return isTypeMatch(type, codebaseInfo: codebaseInfo) && labels == functionDeclaration.parameters.map(\.externalLabel)
    }

    private func isTypeMatch(_ type: TypeSignature?, codebaseInfo: KotlinCodebaseInfo.Context) -> Bool {
        guard let type else {
            return declaringType == nil
        }
        guard let declaringType else {
            return false
        }
        if type == declaringType {
            return true
        }
        return !isInit && codebaseInfo.context.inheritanceChainSignatures(for: type).contains(declaringType) || codebaseInfo.context.protocolSignatures(for: type).contains(declaringType)
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

    init(for functionInfo: CodebaseInfo.FunctionInfo, codebaseInfo: KotlinCodebaseInfo.Context) {
        if case .function(let parameters, _) = functionInfo.signature {
            self.parameters = parameters
        } else {
            self.parameters = [] // Shouldn't happen
        }
        self.type = functionInfo.declaringType
        if let type = functionInfo.declaringType {
            if functionInfo.declarationType == .initDeclaration {
                self.inheritanceChain = [type]
                self.protocols = []
            } else {
                self.inheritanceChain = codebaseInfo.context.inheritanceChainSignatures(for: type)
                self.protocols = codebaseInfo.context.protocolSignatures(for: type)
            }
        } else {
            self.inheritanceChain = []
            self.protocols = []
        }
        self.isInModule = functionInfo.moduleName == codebaseInfo.context.codebaseInfo.moduleName
        self.visibility = functionInfo.modifiers.visibility
    }

    func isKind(of labelDeclarer: LabelDeclarer) -> Bool {
        if type == labelDeclarer.type {
            return true
        }
        guard let ldtype = labelDeclarer.type else {
            return false
        }
        return inheritanceChain.contains(ldtype) || protocols.contains(ldtype)
    }

    var isImplementable: Bool {
        return visibility == .open || (visibility == .public && inheritanceChain.isEmpty && !protocols.isEmpty)
    }
}
