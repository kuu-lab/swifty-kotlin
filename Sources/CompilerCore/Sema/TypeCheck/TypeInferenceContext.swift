struct LambdaReturnLocalState {
    var locals: LocalBindings
    var finallyInitializedSymbols: Set<SymbolID> = []
}

final class LambdaReturnInferenceScope {
    let exprID: ExprID
    let label: InternedString?
    let expectedReturnType: TypeID?
    var returnValueTypes: [ExprID: TypeID] = [:]
    var returnLocalStates: [LambdaReturnLocalState] = []
    var pendingFinallyReturnStates: [LambdaReturnLocalState] = []
    var openFinallyRegionCount = 0

    init(exprID: ExprID, label: InternedString?, expectedReturnType: TypeID?) {
        self.exprID = exprID
        self.label = label
        self.expectedReturnType = expectedReturnType
    }
}

final class LoopControlFlowInferenceScope {
    let label: InternedString?
    var breakLocalStates: [LocalBindings] = []
    var continueLocalStates: [LocalBindings] = []
    var recordsJumps = true

    init(label: InternedString?) {
        self.label = label
    }
}

struct SuspensionContext {
    var function: SymbolID?
    var lambdas: [ExprID] = []
}

struct TypeInferenceContext: CustomStringConvertible {
    let ast: ASTModule
    let sema: SemaModule
    let resolver: OverloadResolver
    let dataFlow: DataFlowAnalyzer
    let interner: StringInterner
    var scope: Scope
    var isElvisBranchExpectedTypeHint = false
    var elvisRhsCallResultTypeHint: TypeID?
    var elvisRhsCallResultTypeHintExpr: ExprID?
    var allowsLiftedCallExpectedTypeHints = true
    var validatesLiftedHintCollectionArguments = false
    var collectionFactoryInferenceRequiredForEqualityOperand: ExprID?
    var isCallResultDiscarded = false
    var isUnitCoercionContext = false
    var isConditionallyEvaluated = false
    var receiverConditionallyEvaluated = false
    var whenSubjectTypes: [ExprID: TypeID] = [:]
    /// The subject ExprID of the enclosing `when` while one of its branch
    /// conditions is being inferred. The parser reuses that exact ExprID as
    /// the operand of a synthesized `is` condition, so consumer recording on
    /// the operand must not erase the claim the subject still owes its
    /// synthetic typed local (KUU-3893).
    var whenConditionSubject: ExprID?
    var implicitReceiverType: TypeID?
    var implicitReceiverStack: [(type: TypeID, symbol: SymbolID)] = []
    var builderInference: BuilderInferenceSession?
    var callableReferenceInferenceParameters: Set<SymbolID> = []
    var isCallableReferenceArgument = false
    /// The argument expression currently being inferred in a call's argument
    /// position. A bare collection factory (`emptyList()`) *at that exact
    /// expression* keeps its `Nothing`-shaped result when the propagated
    /// expected type carries no concrete evidence, so the enclosing call's
    /// chosen parameter can still pin it — the same joint inference kotlinc
    /// performs for `this(emptyList())` or `xs.addAll(emptyList())`. The id
    /// (not a boolean) is recorded so the deferral cannot leak into receiver
    /// positions or deeper sub-expressions: `listOf().size` still reports
    /// (KUU-4002).
    var callArgumentExprBeingInferred: ExprID?
    var loopDepth: Int
    var loopLabelStack: [InternedString]
    var loopFlowScopes: [LoopControlFlowInferenceScope] = []
    var lambdaLoopScopes: [(exprID: ExprID, loopDepth: Int, labels: [InternedString])] = []
    var lambdaLabelStack: [(label: InternedString, denotesFunction: Bool)]
    var lambdaReturnScopes: [LambdaReturnInferenceScope] = []
    var lambdaDepth: Int = 0
    var suspensionContext = SuspensionContext()
    var defaultArgumentComposableFunction: SymbolID?
    var enclosingFunctionReturnType: TypeID?
    var enclosingFunctionSymbol: SymbolID?
    var enclosingFunctionProhibitsExpressionBodyReturn: Bool = false
    var returnTargetIsInitBlock: Bool = false
    var isPropertyGetterReturn: Bool {
        guard let function = enclosingFunctionSymbol else { return false }
        if SyntheticSymbolScheme.decodedPropertyAccessor(function)?.kind == .getter { return true }
        guard let property = sema.symbols.parentSymbol(for: function) else { return false }
        return sema.symbols.extensionPropertyGetterAccessor(for: property) == function
    }
    var enclosingLambdaExprIDs: [ExprID] = []
    var exportBlockLocalsForExpr: ExprID?
    var flowState: DataFlowState
    let currentFileID: FileID
    var currentDeclSymbol: SymbolID?
    var enumEntrySuperContext: (ownerSymbol: SymbolID, type: TypeID)?
    var initializingPropertySymbol: SymbolID?
    var isInPropertyInitializer: Bool {
        initializingPropertySymbol != nil && initializingPropertySymbol == currentDeclSymbol
    }
    var enclosingClassSymbol: SymbolID?
    let visibilityChecker: VisibilityChecker
    var outerReceiverTypes: [(label: InternedString, type: TypeID, symbol: SymbolID?)]
    var contextReceiverTypes: [TypeID] = []
    var lambdaContextReceiverTypes: [ExprID: [TypeID]] = [:]
    var excludesEnclosingClassReceiver = false
    /// Receivers kept for capture in supertype constructor arguments that
    /// delegate to their own class. When `inner class Inner : Outer({ ok })`
    /// delegates to `Outer`, kotlinc resolves a bare `ok` to the companion
    /// scope before the captured outer instance's members — but the receiver
    /// still resolves as a fallback when no class-scope member matches
    /// (`val ok = "x"` alone still binds `this@Outer.ok`), and stays
    /// capturable for explicit `this@Outer.x`. Marking the matching receiver
    /// demotes it below its companion block in the lookup tower.
    var companionDemotedReceiverSymbols: Set<SymbolID> = []
    var isBuilderLambdaScope: Bool = false
    var suppressPlatformReturnWarning: Bool = false
    var builderKind: BuilderDSLKind?
    var isFlowBuilderLambdaScope: Bool = false
    var flowBuilderInference: FlowBuilderInferenceSession?
    var isCoroutineBuilderLambdaScope: Bool = false
    var allowsValPropertyInitialization: Bool = false
    let semaCacheContext: SemaCacheContext?
    let useNewInference: Bool
    let useUnrestrictedBuilderInference: Bool
    let useProperTypeInferenceConstraintsProcessing: Bool
    let globalOptInMarkerNames: [String]
    var accessorOptInMarkers: Set<SymbolID> = []
    var annotationOptInValidation: (owner: SymbolID, range: SourceRange?, markers: Set<SymbolID>)?
    var annotationConstructionTarget: (call: ExprID, annotationClass: SymbolID)?
    var inheritedOptInMarkers: Set<SymbolID> = []
    var activeDslMarkerAnnotations: Set<String> = []
    func with(implicitReceiverType newType: TypeID?) -> TypeInferenceContext {
        var copy = self
        copy.implicitReceiverType = newType
        if let newType {
            copy.activeDslMarkerAnnotations = copy.collectDslMarkerAnnotations(for: newType)
        } else {
            copy.activeDslMarkerAnnotations = []
        }
        return copy
    }

    var currentASTFile: ASTFile? {
        ast.file(for: currentFileID)
    }

    func withLambdaLabel(_ label: InternedString, denotesFunction: Bool = true) -> TypeInferenceContext {
        var copy = self
        copy.lambdaLabelStack = lambdaLabelStack + [(label: label, denotesFunction: denotesFunction)]
        return copy
    }

    func enteringLambdaBody(_ exprID: ExprID) -> TypeInferenceContext {
        var copy = self
        copy.lambdaDepth += 1
        copy.enclosingLambdaExprIDs.append(exprID)
        copy.suspensionContext.lambdas.append(exprID)
        copy.lambdaLoopScopes.append((exprID: exprID, loopDepth: loopDepth, labels: loopLabelStack))
        copy.loopDepth = 0
        copy.loopLabelStack = []
        copy.loopFlowScopes = []
        return copy
    }

    func recordLoopJump(_ locals: LocalBindings, label: InternedString?, isBreak: Bool) {
        guard loopDepth > 0 else { return }
        let target: LoopControlFlowInferenceScope?
        if let label {
            target = loopFlowScopes.last { $0.label == label }
        } else {
            target = loopFlowScopes.last
        }
        guard let target, target.recordsJumps else { return }
        if isBreak {
            target.breakLocalStates.append(locals)
        } else {
            target.continueLocalStates.append(locals)
        }
    }

    func lambdaPathForEnclosingLoopJump(label: InternedString?) -> [ExprID]? {
        for index in lambdaLoopScopes.indices.reversed() {
            let loopScope = lambdaLoopScopes[index]
            let hasTarget = if let label {
                loopScope.labels.contains(label)
            } else {
                loopScope.loopDepth > 0
            }
            if hasTarget {
                return lambdaLoopScopes[index...].map(\.exprID)
            }
        }
        return nil
    }

    func lambdaLabelDenotesFunction(_ label: InternedString) -> Bool? {
        for entry in lambdaLabelStack.reversed() where entry.label == label {
            return entry.denotesFunction
        }
        return nil
    }

    func excludingEnclosingClassReceiver() -> TypeInferenceContext {
        var copy = self
        copy.excludesEnclosingClassReceiver = true
        return copy
    }

    func demotingReceiverBelowCompanion(_ classSymbol: SymbolID) -> TypeInferenceContext {
        var copy = self
        copy.companionDemotedReceiverSymbols.insert(classSymbol)
        return copy
    }

    func withoutSuspensionContext() -> TypeInferenceContext {
        var copy = self
        copy.suspensionContext = SuspensionContext()
        return copy
    }

    func hasLambdaLabel(_ label: InternedString) -> Bool {
        lambdaLabelDenotesFunction(label) == true
    }

    func hasNonFunctionLambdaLabel(_ label: InternedString) -> Bool {
        lambdaLabelDenotesFunction(label) == false
    }

    func syncingImplicitReceiver(from locals: LocalBindings) -> TypeInferenceContext {
        guard let receiverType = implicitReceiverType,
              let thisLocal = locals[interner.intern("this")],
              !thisLocal.isMutable, thisLocal.isInitialized,
              thisLocal.type != receiverType, thisLocal.type != sema.types.errorType,
              sema.types.isSubtype(thisLocal.type, receiverType)
        else { return self }
        let receiverOwner = SyntheticSymbolScheme.receiverParameterOwner(for: thisLocal.symbol)
        let isDeclarationReceiver = receiverOwner != nil
            && (receiverOwner == currentDeclSymbol || receiverOwner == enclosingFunctionSymbol)
        guard isDeclarationReceiver || implicitReceiverStack.last?.symbol == thisLocal.symbol else {
            return self
        }
        return copying(implicitReceiverType: thisLocal.type)
    }

    func with(currentDeclSymbol newSymbol: SymbolID?) -> TypeInferenceContext {
        var copy = self; copy.currentDeclSymbol = newSymbol; return copy
    }

    func withEnumEntrySuperContext(ownerSymbol: SymbolID, type: TypeID) -> TypeInferenceContext {
        var copy = self
        copy.enumEntrySuperContext = (ownerSymbol: ownerSymbol, type: type)
        return copy
    }

    func with(initializingPropertySymbol newSymbol: SymbolID?) -> TypeInferenceContext {
        var copy = self; copy.initializingPropertySymbol = newSymbol; return copy
    }

    func copying(
        scope: Scope? = nil,
        implicitReceiverType: TypeID?? = nil,
        loopDepth: Int? = nil,
        loopLabelStack: [InternedString]? = nil,
        loopFlowScopes: [LoopControlFlowInferenceScope]? = nil,
        lambdaLabelStack: [(label: InternedString, denotesFunction: Bool)]? = nil,
        lambdaReturnScopes: [LambdaReturnInferenceScope]? = nil,
        lambdaDepth: Int? = nil,
        lambdaLoopScopes: [(exprID: ExprID, loopDepth: Int, labels: [InternedString])]? = nil,
        enclosingFunctionReturnType: TypeID?? = nil,
        enclosingFunctionSymbol: SymbolID?? = nil,
        enclosingFunctionProhibitsExpressionBodyReturn: Bool? = nil,
        returnTargetIsInitBlock: Bool? = nil,
        enclosingLambdaExprIDs: [ExprID]? = nil,
        exportBlockLocalsForExpr: ExprID?? = nil,
        flowState: DataFlowState? = nil,
        currentDeclSymbol: SymbolID?? = nil,
        enclosingClassSymbol: SymbolID?? = nil,
        outerReceiverTypes: [(label: InternedString, type: TypeID, symbol: SymbolID?)]? = nil,
        contextReceiverTypes: [TypeID]? = nil
    ) -> TypeInferenceContext {
        var copy = self
        if let scope { copy.scope = scope }
        if let implicitReceiverType {
            copy.implicitReceiverType = implicitReceiverType
            if let newType = implicitReceiverType {
                copy.activeDslMarkerAnnotations = copy.collectDslMarkerAnnotations(for: newType)
            } else {
                copy.activeDslMarkerAnnotations = []
            }
        }
        if let loopDepth { copy.loopDepth = loopDepth }
        if let loopLabelStack { copy.loopLabelStack = loopLabelStack }
        if let loopFlowScopes { copy.loopFlowScopes = loopFlowScopes }
        if let lambdaLabelStack { copy.lambdaLabelStack = lambdaLabelStack }
        if let lambdaReturnScopes { copy.lambdaReturnScopes = lambdaReturnScopes }
        if let lambdaDepth { copy.lambdaDepth = lambdaDepth }
        if let lambdaLoopScopes {
            copy.lambdaLoopScopes = lambdaLoopScopes
        } else if let enclosingLambdaExprIDs, enclosingLambdaExprIDs.isEmpty {
            copy.lambdaLoopScopes = []
        }
        if let enclosingFunctionReturnType {
            copy.enclosingFunctionReturnType = enclosingFunctionReturnType
        }
        if let enclosingFunctionSymbol { copy.enclosingFunctionSymbol = enclosingFunctionSymbol }
        if let enclosingFunctionProhibitsExpressionBodyReturn {
            copy.enclosingFunctionProhibitsExpressionBodyReturn = enclosingFunctionProhibitsExpressionBodyReturn
        }
        if let returnTargetIsInitBlock {
            copy.returnTargetIsInitBlock = returnTargetIsInitBlock
        }
        if let enclosingLambdaExprIDs { copy.enclosingLambdaExprIDs = enclosingLambdaExprIDs }
        if let exportBlockLocalsForExpr { copy.exportBlockLocalsForExpr = exportBlockLocalsForExpr }
        if let flowState { copy.flowState = flowState }
        if let currentDeclSymbol { copy.currentDeclSymbol = currentDeclSymbol }
        if let enclosingClassSymbol { copy.enclosingClassSymbol = enclosingClassSymbol }
        if let outerReceiverTypes { copy.outerReceiverTypes = outerReceiverTypes }
        if let contextReceiverTypes { copy.contextReceiverTypes = contextReceiverTypes }
        return copy
    }

    func with(contextReceiverTypes newTypes: [TypeID]) -> TypeInferenceContext {
        var copy = self
        copy.contextReceiverTypes = newTypes
        return copy
    }

    func withOuterReceiver(label: InternedString, type: TypeID, symbol: SymbolID? = nil) -> TypeInferenceContext {
        var copy = self
        copy.outerReceiverTypes = outerReceiverTypes + [(label: label, type: type, symbol: symbol)]
        return copy
    }

    func nestedClassContext(isInner: Bool) -> TypeInferenceContext {
        guard !isInner else { return self }
        return copying(outerReceiverTypes: singletonObjectOuterReceivers)
    }

    var singletonObjectOuterReceivers: [(label: InternedString, type: TypeID, symbol: SymbolID?)] {
        outerReceiverTypes.filter { receiver in
            guard receiver.symbol == nil,
                  case let .classType(classType) = sema.types.kind(of: receiver.type)
            else {
                return false
            }
            return sema.symbols.symbol(classType.classSymbol)?.kind == .object
        }
    }

    func resolveQualifiedThis(label: InternedString) -> TypeID? {
        for entry in outerReceiverTypes.reversed() where entry.label == label {
            return entry.type
        }
        return nil
    }

    func resolveQualifiedThisReceiverSymbol(label: InternedString) -> SymbolID? {
        for entry in outerReceiverTypes.reversed() where entry.label == label {
            return entry.symbol
        }
        return nil
    }

    func enumEntryReceiverSymbol(forQualifiedThisLabel label: InternedString) -> SymbolID? {
        guard resolveQualifiedThis(label: label) != nil,
              let enumSymbol = resolveQualifiedThisReceiverSymbol(label: label),
              let enumInfo = sema.symbols.symbol(enumSymbol),
              enumInfo.kind == .enumClass
        else {
            return nil
        }
        return sema.symbols.lookupAll(fqName: enumInfo.fqName + [label]).first { candidate in
            sema.symbols.symbol(candidate)?.kind == .field
                && sema.symbols.parentSymbol(for: candidate) == enumSymbol
        }
    }

    func implicitReceiverMemberLookupEntries() -> [(type: TypeID, symbol: SymbolID?)] {
        var entries: [(type: TypeID, symbol: SymbolID?)] = []
        var seen: Set<TypeID> = []
        func appendUnique(_ type: TypeID, symbol: SymbolID?) {
            if seen.insert(type).inserted {
                entries.append((type, symbol))
            }
        }
        func appendCompanionBlockChain(for owner: SymbolID, skipping skippedBlock: SymbolID? = nil) {
            var queue = [owner]
            var visited: Set<SymbolID> = []
            while !queue.isEmpty {
                let current = queue.removeFirst()
                guard visited.insert(current).inserted,
                      let ownerSymbol = sema.symbols.symbol(current)
                else {
                    continue
                }
                if let companionBlock = sema.symbols.companionBlockObjectSymbol(for: current, interner: interner),
                   companionBlock != skippedBlock
                {
                    appendUnique(
                        sema.types.make(.classType(ClassType(
                            classSymbol: companionBlock,
                            args: [],
                            nullability: .nonNull
                        ))),
                        symbol: companionBlock
                    )
                }
                guard ownerSymbol.kind == .class else { continue }
                queue.append(contentsOf: sema.symbols.directSupertypes(for: current).filter {
                    sema.symbols.symbol($0)?.kind == .class
                })
            }
        }
        func appendCompanionChain(forReceiverType type: TypeID) {
            guard case let .classType(classType) = sema.types.kind(of: type),
                  let receiverSymbol = sema.symbols.symbol(classType.classSymbol)
            else {
                return
            }
            if receiverSymbol.name == interner.intern("$CompanionBlocks"),
               let owner = sema.symbols.parentSymbol(for: classType.classSymbol)
            {
                appendCompanionBlockChain(for: owner, skipping: classType.classSymbol)
            } else {
                appendCompanionBlockChain(for: classType.classSymbol)
            }
        }
        func appendReceiverAndCompanionBlock(_ type: TypeID, symbol: SymbolID?) {
            appendUnique(type, symbol: symbol)
            appendCompanionChain(forReceiverType: type)
        }
        if let implicitReceiverType {
            appendReceiverAndCompanionBlock(implicitReceiverType, symbol: nil)
        }
        for entry in implicitReceiverStack.reversed() {
            appendReceiverAndCompanionBlock(entry.type, symbol: entry.symbol)
        }
        for entry in outerReceiverTypes.reversed() {
            if case let .classType(classType) = sema.types.kind(of: entry.type),
               companionDemotedReceiverSymbols.contains(classType.classSymbol)
            {
                appendCompanionChain(forReceiverType: entry.type)
                if let companion = sema.symbols.companionObjectSymbol(for: classType.classSymbol) {
                    appendUnique(
                        sema.types.make(.classType(ClassType(
                            classSymbol: companion,
                            args: [],
                            nullability: .nonNull
                        ))),
                        symbol: companion
                    )
                }
                appendUnique(entry.type, symbol: entry.symbol)
            } else {
                appendReceiverAndCompanionBlock(entry.type, symbol: entry.symbol)
            }
        }
        if let enclosingClassSymbol, !excludesEnclosingClassReceiver {
            let ownerArgs = sema.types.nominalTypeParameterSymbols(for: enclosingClassSymbol).map {
                TypeArg.invariant(sema.types.make(.typeParam(TypeParamType(symbol: $0))))
            }
            appendReceiverAndCompanionBlock(
                sema.types.make(.classType(ClassType(
                    classSymbol: enclosingClassSymbol,
                    args: ownerArgs,
                    nullability: .nonNull
                ))),
                symbol: enclosingClassSymbol
            )
        }
        return entries
    }

    func implicitReceiverMemberLookupTypes() -> [TypeID] {
        var types: [TypeID] = []
        var seen: Set<TypeID> = []
        func appendUnique(_ type: TypeID) {
            if seen.insert(type).inserted {
                types.append(type)
            }
        }
        if let implicitReceiverType {
            appendUnique(implicitReceiverType)
        }
        for entry in implicitReceiverStack.reversed() {
            appendUnique(entry.type)
        }
        var demoted: [TypeID] = []
        for entry in outerReceiverTypes.reversed() {
            if case let .classType(classType) = sema.types.kind(of: entry.type),
               companionDemotedReceiverSymbols.contains(classType.classSymbol)
            {
                if let companion = sema.symbols.companionObjectSymbol(for: classType.classSymbol) {
                    demoted.append(
                        sema.types.make(.classType(ClassType(
                            classSymbol: companion,
                            args: [],
                            nullability: .nonNull
                        )))
                    )
                }
                demoted.append(entry.type)
            } else {
                appendUnique(entry.type)
            }
        }
        for type in demoted {
            appendUnique(type)
        }
        if let enclosingClassSymbol, !excludesEnclosingClassReceiver {
            let ownerArgs = sema.types.nominalTypeParameterSymbols(for: enclosingClassSymbol).map {
                TypeArg.invariant(sema.types.make(.typeParam(TypeParamType(symbol: $0))))
            }
            appendUnique(
                sema.types.make(.classType(ClassType(
                    classSymbol: enclosingClassSymbol,
                    args: ownerArgs,
                    nullability: .nonNull
                )))
            )
        }
        return types
    }

    func inheritedCompanionReceiver(for candidate: SymbolID) -> SymbolID? {
        guard let candidateSymbol = cachedSymbol(candidate),
              candidateSymbol.kind == .function,
              sema.symbols.memberExtensionOwnerSymbol(for: candidate) == nil,
              sema.symbols.functionSignature(for: candidate)?.receiverType != nil,
              let declaringOwner = sema.symbols.parentSymbol(for: candidate),
              let enclosingClassSymbol
        else {
            return nil
        }

        var classQueue = [enclosingClassSymbol]
        var visitedClasses: Set<SymbolID> = []
        while !classQueue.isEmpty {
            let classSymbol = classQueue.removeFirst()
            guard visitedClasses.insert(classSymbol).inserted else { continue }
            if let companion = sema.symbols.companionObjectSymbol(for: classSymbol),
               companion != declaringOwner,
               sema.types.isNominalSubtypeSymbol(companion, of: declaringOwner) {
                return companion
            }
            classQueue.append(contentsOf: sema.symbols.directSupertypes(for: classSymbol).filter {
                sema.symbols.symbol($0)?.kind == .class
            })
        }
        return nil
    }

    func filterByVisibility(
        _ candidates: [SymbolID],
        protectedAccessReceiverType: TypeID? = nil,
        usageRange: SourceRange? = nil
    ) -> (visible: [SymbolID], invisible: [SemanticSymbol]) {
        var visible: [SymbolID] = []
        var invisible: [SemanticSymbol] = []
        // A hidden compatibility factory must not shadow a usable constructor
        // or overload. When it is the only candidate, keep it long enough for
        // the normal deprecation path to emit KSWIFTK-SEMA-DEPRECATED rather
        // than degrading the diagnostic to an unresolved reference.
        let hasNonHiddenCandidate = candidates.contains {
            !isHiddenByDeprecationOrVersionAnnotation($0, symbols: sema.symbols)
        }
        for candidate in candidates {
            guard let symbol = cachedSymbol(candidate) else { continue }
            if isHiddenByDeprecationOrVersionAnnotation(candidate, symbols: sema.symbols) {
                if symbol.flags.contains(.synthetic) || hasNonHiddenCandidate {
                    continue
                }
            }
            let accessibleInEnclosingClass = visibilityChecker.isAccessible(
                symbol, fromFile: currentFileID, enclosingClass: enclosingClassSymbol, usageRange: usageRange
            )
            let accessibleThroughEnclosingCompanion: Bool = {
                guard !accessibleInEnclosingClass,
                      symbol.visibility == .protected,
                      let protectedAccessReceiverType,
                      case let .classType(receiverClass) = sema.types.kind(
                          of: sema.types.makeNonNullable(protectedAccessReceiverType)
                      ),
                      let companion = inheritedCompanionReceiver(for: candidate),
                      sema.types.isNominalSubtypeSymbol(receiverClass.classSymbol, of: companion)
                else {
                    return false
                }
                return visibilityChecker.isAccessible(
                    symbol, fromFile: currentFileID, enclosingClass: companion, usageRange: usageRange
                )
            }()
            if accessibleInEnclosingClass || accessibleThroughEnclosingCompanion {
                visible.append(candidate)
            } else {
                invisible.append(symbol)
            }
        }
        return (visible, invisible)
    }

    func cachedSymbol(_ id: SymbolID) -> SemanticSymbol? {
        if let cache = semaCacheContext {
            return cache.symbol(id, in: sema.symbols)
        }
        return sema.symbols.symbol(id)
    }

    func isScopeMemberVisibleFromReceivers(_ symbolID: SymbolID) -> Bool {
        guard let symbol = cachedSymbol(symbolID) else { return true }
        switch symbol.kind {
        case .property, .field, .backingField:
            break
        default:
            return true
        }
        guard let ownerID = sema.symbols.parentSymbol(for: symbolID),
              let owner = sema.symbols.symbol(ownerID)
        else {
            return true
        }
        switch owner.kind {
        case .object, .package:
            return true
        case .class, .interface, .enumClass, .annotationClass:
            break
        default:
            return true
        }
        if sema.symbols.enumOwnerSymbol(for: symbol) != nil {
            return true
        }
        // Constructor-delegation and supertype-constructor argument scopes
        // drop the not-yet-constructed receiver from the tower, but its
        // members must still bind so the pre-instance checker can reject
        // them with KSWIFTK-SEMA-0058 — an unresolved binding degrades the
        // diagnostic to SEMA-0022 and wrongly rejects deferred-lambda reads
        // that run after construction (KUU-4520).
        if excludesEnclosingClassReceiver, ownerID == enclosingClassSymbol {
            return true
        }
        var companionSeeds: Set<SymbolID> = []
        for entry in implicitReceiverMemberLookupEntries() {
            guard case let .classType(classType) = sema.types.kind(of: entry.type) else {
                continue
            }
            if sema.types.isNominalSubtypeSymbol(classType.classSymbol, of: ownerID) {
                return true
            }
            companionSeeds.insert(classType.classSymbol)
        }
        var lexical: SymbolID? = enclosingClassSymbol
        while let current = lexical {
            companionSeeds.insert(current)
            guard let parent = sema.symbols.parentSymbol(for: current),
                  let parentKind = sema.symbols.symbol(parent)?.kind,
                  parentKind == .class || parentKind == .object
                      || parentKind == .enumClass || parentKind == .interface
            else {
                break
            }
            lexical = parent
        }
        var visitedCompanionOwners: Set<SymbolID> = []
        var queue = Array(companionSeeds)
        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard visitedCompanionOwners.insert(current).inserted,
                  sema.symbols.symbol(current)?.kind == .class
            else {
                continue
            }
            for companion in [
                sema.symbols.companionObjectSymbol(for: current),
                sema.symbols.companionBlockObjectSymbol(for: current, interner: interner),
            ].compactMap({ $0 }) where sema.types.isNominalSubtypeSymbol(companion, of: ownerID) {
                return true
            }
            queue.append(contentsOf: sema.symbols.directSupertypes(for: current).filter {
                sema.symbols.symbol($0)?.kind == .class
            })
        }
        return false
    }

    /// `expect`/`actual` pairs are intentionally allowed to coexist in the same
    /// scope (KSwiftK has no separate common/platform module compilation), so a
    /// linked `expect` declaration is filtered out here once its `actual` is
    /// known. Without this, every expression-level reference to the pair would
    /// see two candidates with an identical shape: call resolution reports a
    /// false ambiguous-overload, and name resolution binds arbitrarily to
    /// whichever declaration happens to come first.
    ///
    /// An expect declaration is only superseded by an actual that the same
    /// lookup can see: members of an expect class resolve inside the expect
    /// class's scope, where the actual member lives under the actual class and
    /// never appears among the candidates — dropping the expect symbol there
    /// leaves no candidates at all (KUU-3934).
    func cachedScopeLookup(_ name: InternedString) -> [SymbolID] {
        let results: [SymbolID] = if let cache = semaCacheContext {
            cache.lookupInScope(name, scope: scope)
        } else {
            scope.lookup(name)
        }
        return results.filter {
            !isExpectDeclarationSupersededByActual($0, among: results)
                && !isImportedSymbolShadowedBySource($0)
                && isScopeMemberVisibleFromReceivers($0)
        }
    }

    func cachedScopeLookup(
        _ name: InternedString,
        matching predicate: (SymbolID) -> Bool
    ) -> [SymbolID] {
        let results = scope.lookup(name, matching: predicate)
        return results.filter {
            !isExpectDeclarationSupersededByActual($0, among: results)
                && !isImportedSymbolShadowedBySource($0)
                && isScopeMemberVisibleFromReceivers($0)
        }
    }

    /// Merging-chain variant of `cachedScopeLookup`: collects candidates from
    /// every lexical scope instead of stopping at the first scope that binds
    /// the name. Callers must only consult it after the nearest scope's
    /// candidates all proved inapplicable — Kotlin shadows an outer
    /// declaration only while the inner one remains a viable candidate
    /// (KUU-4462).
    func cachedScopeLookupMergingChain(_ name: InternedString) -> [SymbolID] {
        let results = scope.lookupMergingChain(name)
        return results.filter {
            !isExpectDeclarationSupersededByActual($0, among: results)
                && !isImportedSymbolShadowedBySource($0)
                && isScopeMemberVisibleFromReceivers($0)
        }
    }

    func valueScopeLookup(_ name: InternedString) -> (matches: [SymbolID], inheritedInterfaces: Set<SymbolID>) {
        valueScopeLookup(name) { symbolID in
            guard let symbol = cachedSymbol(symbolID) else { return false }
            return symbol.kind != .function && symbol.kind != .constructor
        }
    }

    func valueScopeLookup(
        _ name: InternedString,
        matching predicate: (SymbolID) -> Bool
    ) -> (matches: [SymbolID], inheritedInterfaces: Set<SymbolID>) {
        var inheritedInterfaces: Set<SymbolID> = []
        func matchingCandidates(in currentScope: BaseScope) -> [SymbolID] {
            let bound = currentScope.candidates(for: name)
            return bound.filter { symbolID in
                guard let symbol = cachedSymbol(symbolID),
                      !isExpectDeclarationSupersededByActual(symbolID, among: bound),
                      !isImportedSymbolShadowedBySource(symbolID),
                      isScopeMemberVisibleFromReceivers(symbolID)
                else { return false }
                let isClassifier = switch symbol.kind {
                case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias: true
                default: false
                }
                if isClassifier, let classScope = currentScope as? ClassMemberScope,
                   let owner = sema.symbols.parentSymbol(for: symbolID),
                   owner != classScope.owner,
                   sema.symbols.symbol(owner)?.kind == .interface {
                    inheritedInterfaces.insert(symbolID)
                    return false
                }
                return predicate(symbolID)
            }
        }
        // Kotlin ranks an explicit single-name or alias import above
        // same-package declarations for values as well as classifiers
        // (KUU-4192). The physical chain places the package scope above the
        // explicit-import scope, so once the walk reaches file level the
        // explicit-import tier is promoted ahead of the file/package tiers —
        // the same ordering `Scope.lookupClassifier` implements for type
        // positions. Wildcard and default imports still rank below
        // same-package declarations, and scopes nested inside the file scope
        // (locals, member scopes) keep innermost priority.
        var current: Scope? = scope
        var reachedFileScope = false
        var fileLevelMatches: [SymbolID] = []
        while let currentScope = current as? BaseScope {
            let candidates = matchingCandidates(in: currentScope)
            if !reachedFileScope && !(currentScope is FileScope) {
                if !candidates.isEmpty { return (candidates, inheritedInterfaces) }
            } else {
                reachedFileScope = true
                if currentScope is ExplicitImportScope {
                    if !candidates.isEmpty { return (candidates, inheritedInterfaces) }
                    if !fileLevelMatches.isEmpty { break }
                } else if fileLevelMatches.isEmpty {
                    fileLevelMatches = candidates
                }
            }
            current = currentScope.parent
        }
        return (fileLevelMatches, inheritedInterfaces)
    }

    /// A source declaration shadows a bundled declaration at the same FQ
    /// name — an imported-library twin (e.g. upstream `kotlinx.io`/
    /// `kotlinx.coroutines` sources vendored over the bundled stdlib copy) or
    /// a synthetic stand-in such as the coroutine launcher stubs. Callables
    /// shadow when their erased signatures match; nominal classifiers shadow
    /// on a same-kind, same-FQ-name pair. Keeping both as candidates merges
    /// two declarations that must behave as one: type references already
    /// prefer the source nominal (`sourceFirstThenID` in Helpers.swift), so
    /// a bundled twin left in expression position binds enum entries and
    /// qualifier members of the library-side type while signatures expect
    /// the source type — the split surfaces as initializer mismatches and
    /// "no viable overload" errors (KUU-4274).
    func isImportedSymbolShadowedBySource(_ id: SymbolID) -> Bool {
        guard let symbol = cachedSymbol(id) else {
            return false
        }
        let isSyntheticStandIn = symbol.flags.contains(.synthetic)
            && !symbol.flags.contains(.importedLibrary)
        guard symbol.flags.contains(.importedLibrary) || isSyntheticStandIn else {
            return false
        }
        func isSourceShadower(_ otherSymbol: SemanticSymbol) -> Bool {
            !otherSymbol.flags.contains(.importedLibrary)
                && !(isSyntheticStandIn && otherSymbol.flags.contains(.synthetic))
        }
        switch symbol.kind {
        case .function, .constructor:
            guard let signature = sema.symbols.functionSignature(for: id) else {
                return false
            }
            return sema.symbols.lookupAll(fqName: symbol.fqName).contains { other in
                guard other != id,
                      let otherSymbol = cachedSymbol(other),
                      isSourceShadower(otherSymbol),
                      otherSymbol.kind == symbol.kind,
                      let otherSignature = sema.symbols.functionSignature(for: other)
                else {
                    return false
                }
                return hasSameSourceErasedSignature(signature, otherSignature)
            }
        case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
            return sema.symbols.lookupAll(fqName: symbol.fqName).contains { other in
                guard other != id,
                      let otherSymbol = cachedSymbol(other),
                      isSourceShadower(otherSymbol),
                      otherSymbol.kind == symbol.kind
                else {
                    return false
                }
                return true
            }
        default:
            return false
        }
    }

    private func hasSameSourceErasedSignature(
        _ lhs: FunctionSignature,
        _ rhs: FunctionSignature
    ) -> Bool {
        guard lhs.parameterTypes.count == rhs.parameterTypes.count,
              lhs.typeParameterSymbols.count == rhs.typeParameterSymbols.count,
              lhs.isSuspend == rhs.isSuspend
        else {
            return false
        }
        switch (lhs.receiverType, rhs.receiverType) {
        case (nil, nil):
            break
        case let (lhsReceiver?, rhsReceiver?):
            guard erasedTypeEqual(lhsReceiver, in: lhs, rhsReceiver, in: rhs) else {
                return false
            }
        default:
            return false
        }
        return zip(lhs.parameterTypes, rhs.parameterTypes).allSatisfy { lhsType, rhsType in
            erasedTypeEqual(lhsType, in: lhs, rhsType, in: rhs)
        }
    }

    private func expectClassMatchesTypeAliasTarget(
        expectSymbol: SemanticSymbol?,
        otherClassSymbol: SymbolID
    ) -> Bool {
        guard let expectSymbol,
              expectSymbol.flags.contains(.expectDeclaration),
              expectSymbol.kind == .class || expectSymbol.kind == .interface
        else {
            return false
        }
        return sema.symbols.lookupAll(fqName: expectSymbol.fqName).contains { candidate in
            guard sema.symbols.symbol(candidate)?.kind == .typeAlias,
                  let underlying = sema.symbols.typeAliasUnderlyingType(for: candidate),
                  case let .classType(underlyingType) = sema.types.kind(
                      of: sema.types.makeNonNullable(underlying)
                  )
            else {
                return false
            }
            return underlyingType.classSymbol == otherClassSymbol
        }
    }

    private func erasedTypeEqual(
        _ lhs: TypeID,
        in lhsSignature: FunctionSignature,
        _ rhs: TypeID,
        in rhsSignature: FunctionSignature
    ) -> Bool {
        switch (sema.types.kind(of: sema.types.makeNonNullable(lhs)),
                sema.types.kind(of: sema.types.makeNonNullable(rhs))) {
        case let (.classType(lhsType), .classType(rhsType)):
            let lhsSymbol = sema.symbols.symbol(lhsType.classSymbol)
            let rhsSymbol = sema.symbols.symbol(rhsType.classSymbol)
            if lhsSymbol?.fqName == rhsSymbol?.fqName {
                return true
            }
            return expectClassMatchesTypeAliasTarget(
                expectSymbol: lhsSymbol, otherClassSymbol: rhsType.classSymbol
            ) || expectClassMatchesTypeAliasTarget(
                expectSymbol: rhsSymbol, otherClassSymbol: lhsType.classSymbol
            )
        case let (.typeParam(lhsParam), .typeParam(rhsParam)):
            guard let lhsIndex = lhsSignature.typeParameterSymbols.firstIndex(of: lhsParam.symbol),
                  let rhsIndex = rhsSignature.typeParameterSymbols.firstIndex(of: rhsParam.symbol)
            else {
                return false
            }
            return lhsIndex == rhsIndex
        case let (.functionType(lhsType), .functionType(rhsType)):
            guard lhsType.params.count == rhsType.params.count else {
                return false
            }
            let receiverEqual = switch (lhsType.receiver, rhsType.receiver) {
            case (nil, nil):
                true
            case let (lhsReceiver?, rhsReceiver?):
                erasedTypeEqual(lhsReceiver, in: lhsSignature, rhsReceiver, in: rhsSignature)
            default:
                false
            }
            return receiverEqual
                && zip(lhsType.params, rhsType.params).allSatisfy {
                    erasedTypeEqual($0, in: lhsSignature, $1, in: rhsSignature)
                }
                && erasedTypeEqual(lhsType.returnType, in: lhsSignature, rhsType.returnType, in: rhsSignature)
        case let (.primitive(lhsPrimitive, _), .primitive(rhsPrimitive, _)):
            return lhsPrimitive == rhsPrimitive
        case let (.kClassType(lhsClass), .kClassType(rhsClass)):
            return erasedTypeEqual(lhsClass.argument, in: lhsSignature, rhsClass.argument, in: rhsSignature)
        case (.unit, .unit), (.nullableUnit, .nullableUnit), (.platformUnit, .platformUnit),
             (.nothing, .nothing), (.any, .any), (.stringStruct, .stringStruct):
            return true
        default:
            return false
        }
    }

    func isExpectDeclarationSupersededByActual(_ id: SymbolID) -> Bool {
        guard let symbol = cachedSymbol(id), symbol.flags.contains(.expectDeclaration) else {
            return false
        }
        return sema.symbols.actualSymbol(for: id) != nil
    }

    /// `expect`/`actual` dedup is only valid when the actual counterpart is
    /// part of the same candidate set. Nested members of an `expect` class
    /// resolve inside the expect class's scope chain, where the actual member
    /// — bound under the `actual` class — never appears; treating the expect
    /// member as superseded there erases the only candidate and produces a
    /// spurious unresolved-reference error (KUU-3934).
    func isExpectDeclarationSupersededByActual(_ id: SymbolID, among candidates: [SymbolID]) -> Bool {
        guard isExpectDeclarationSupersededByActual(id),
              let actual = sema.symbols.actualSymbol(for: id)
        else {
            return false
        }
        return candidates.contains(actual)
    }

    func collectDslMarkerAnnotations(for typeID: TypeID) -> Set<String> {
        let nonNull = sema.types.makeNonNullable(typeID)
        guard let classType = resolveClassType(nonNull, sema: sema) else {
            return []
        }
        let classSymbol = classType.classSymbol
        let annotations = sema.symbols.annotations(for: classSymbol)
        var dslMarkers: Set<String> = []
        for annotation in annotations {
            let annotationFQName = annotation.annotationFQName
            if isDslMarkerAnnotation(annotationFQName) {
                dslMarkers.insert(annotationFQName)
            }
        }
        return dslMarkers
    }

    private func isDslMarkerAnnotation(_ annotationFQName: String) -> Bool {
        let parts = annotationFQName.split(separator: ".").map { String($0) }
        let internedParts = parts.map { interner.intern($0) }

        if let annotationSymbol = sema.symbols.lookup(fqName: internedParts) {
            let metaAnnotations = sema.symbols.annotations(for: annotationSymbol)
            for meta in metaAnnotations {
                // swiftlint:disable:next for_where
                if KnownCompilerAnnotation.dslMarker.matches(meta.annotationFQName) {
                    return true
                }
            }
        }
        if parts.count == 1 {
            let simpleName = interner.intern(parts[0])
            let candidates = scope.lookup(simpleName)
            for candidateID in candidates {
                guard let candidateSymbol = sema.symbols.symbol(candidateID),
                      candidateSymbol.kind == .annotationClass else {
                    continue
                }
                let metaAnnotations = sema.symbols.annotations(for: candidateID)
                for meta in metaAnnotations {
                    // swiftlint:disable:next for_where
                    if KnownCompilerAnnotation.dslMarker.matches(meta.annotationFQName) {
                        return true
                    }
                }
            }
        }
        return false
    }

    func isCandidateBlockedByDslMarker(_ candidateID: SymbolID) -> Bool {
        guard !activeDslMarkerAnnotations.isEmpty else {
            return false
        }
        guard let parentID = sema.symbols.parentSymbol(for: candidateID) else {
            return false
        }
        guard let parentSymbol = sema.symbols.symbol(parentID),
              parentSymbol.kind == .class || parentSymbol.kind == .interface || parentSymbol.kind == .object
        else {
            return false
        }
        if let receiverType = implicitReceiverType {
            let nonNull = sema.types.makeNonNullable(receiverType)
            if case let .classType(classType) = sema.types.kind(of: nonNull),
               classType.classSymbol == parentID
            {
                return false
            }
        }
        let parentType = sema.types.make(.classType(ClassType(
            classSymbol: parentID, args: [], nullability: .nonNull
        )))
        let parentDslMarkers = collectDslMarkerAnnotations(for: parentType)
        return !activeDslMarkerAnnotations.isDisjoint(with: parentDslMarkers)
    }

    func dslHiddenImplicitReceiverTypes() -> Set<TypeID> {
        var hidden: Set<TypeID> = []
        var nearerMarkers: Set<String> = []
        for entry in implicitReceiverMemberLookupEntries() {
            let markers = collectDslMarkerAnnotations(for: entry.type)
            if !nearerMarkers.isDisjoint(with: markers) {
                hidden.insert(entry.type)
            }
            nearerMarkers.formUnion(markers)
        }
        return hidden
    }

    var description: String {
        return "\(useNewInference) \(useUnrestrictedBuilderInference) \(useProperTypeInferenceConstraintsProcessing)"
    }
}
