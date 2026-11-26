
final class KIRLoweringContext {
    struct ExceptionHandler {
        let exceptionSlot: KIRExprID
        let exceptionTypeSlot: KIRExprID
        var thrownTarget: Int32
    }

    struct ContextReceiverValue {
        let type: TypeID
        let exprID: KIRExprID
    }

    struct ObjectLazyInit {
        let ensureInitSymbol: SymbolID
        let ensureInitName: InternedString
    }

    struct SuperConstructorArgumentReceiverOverride {
        let constructorSymbol: SymbolID
        let receiverSymbol: SymbolID
        let receiverExprID: KIRExprID
    }


    var localValuesBySymbol: [SymbolID: KIRExprID] = [:]
    var localDeclaredTypesBySymbol: [SymbolID: TypeID] = [:]
    var mutableCaptureCellsBySymbol: [SymbolID: KIRExprID] = [:]
    var localDelegateStorageBySymbol: [SymbolID: KIRExprID] = [:]
    var lambdaParamNameToSymbol: [InternedString: SymbolID] = [:]
    var lambdaEnclosingClassNamesByFileID: [FileID: String] = [:]
    var currentImplicitReceiverExprID: KIRExprID?
    var currentImplicitReceiverSymbol: SymbolID?
    var superConstructorArgumentReceiverOverride: SuperConstructorArgumentReceiverOverride?
    private var qualifiedThisReceiverExprsByLabel: [InternedString: KIRExprID] = [:]
    private var capturedOuterReceiverExprsByOwner: [SymbolID: KIRExprID] = [:]
    private var contextReceiverValueStack: [[ContextReceiverValue]] = []
    var currentFunctionSymbol: SymbolID?
    var currentLambdaAllowsNonLocalReturn = false
    var currentLambdaAllowsNonLocalBreakContinue = false
    var nonLocalReturnTarget: SymbolID?
    var pendingLambdaNonLocalReturnAllowance = false
    var loopControlStack: [(continueLabel: Int32, breakLabel: Int32, name: InternedString?)] = []
    var enclosingLoopControlStack: [(continueLabel: Int32, breakLabel: Int32, name: InternedString?)] = []
    private(set) var finallyBlockStack: [(exprID: ExprID, loopDepth: Int, exceptionHandlerDepth: Int)] = []
    private(set) var exceptionHandlerStack: [ExceptionHandler] = []
    var nextLoopLabel: Int32 = 10000


    var lazyThreadSafetyMode: LazyDelegateThreadSafetyMode = .synchronized

    var assertionsMode: AssertionsMode = .jvm

    private var functionDefaultArgumentsBySymbol: [SymbolID: [ExprID?]] = [:]
    private(set) var tailrecFunctionSymbols: Set<SymbolID> = []
    var pendingGeneratedCallableDeclIDs: [KIRDeclID] = []
    var callableValueInfoByExprID: [KIRExprID: KIRCallableValueInfo] = [:]
    var syntheticLambdaSymbolsByExprID: [ExprID: SymbolID] = [:]
    var topLevelPropertyCallableReferenceInitializerExprID: ExprID?
    /// Lambda symbols lowered with the receiver-first coroutine-launcher ABI
    /// (source literal was marked via `markCoroutineLauncherLambdaExpr` and
    /// carries an explicit receiver). Launcher-continuation rewrites must
    /// gate on this set: a lambda that resolves through a variable/alias was
    /// never marked, so its thunk keeps the captures-first layout and seeding
    /// the receiver at launcherArgs[0] would corrupt a capture slot.
    var receiverFirstLauncherLambdaSymbols: Set<SymbolID> = []
    var runtimeCoroutineScopeReceiverExprIDs: Set<KIRExprID> = []
    var erasedGenericReturnLambdaClaims: [ExprID: (declaredSymbol: SymbolID, substituted: TypeID)]?
    /// While lowering a lambda body that returns into an erased generic
    /// position, the declared `T` symbol and its per-call-site substitution.
    /// A generic call tail whose recorded consumer is that `T` must be
    /// checked against the substituted type — JVM specializes the lambda's
    /// invoke() to it and emits the boundary checkcast there (KUU-4496) —
    /// while the raw `T` would erase to `Any` and skip the check.
    var erasedLambdaReturnClaimStack: [(declaredSymbol: SymbolID, substituted: TypeID)] = []
    var syntheticObjectLiteralSymbolsByExprID: [ExprID: (nominalSymbol: SymbolID, constructorSymbol: SymbolID, constructorName: InternedString)] = [:]
    var emittedObjectLiteralExprIDs: Set<ExprID> = []
    var itableBridgeSymbolsByKey: [String: SymbolID] = [:]
    var samWrapperClassIdentitySymbols: [SymbolID: SymbolID] = [:]
    var anyToStringBridgeSymbolsByImplementation: [SymbolID: SymbolID] = [:]
    var throwableMessageBridgeSymbolsByGetter: [SymbolID: SymbolID] = [:]
    let nominalDispatchCache = KIRNominalDispatchCache()
    var nextSyntheticLambdaSymbolRawValue: Int32 = -60_000_000

    private var companionInitializerFunctions: [(symbol: SymbolID, name: InternedString)] = []
    private var reflectionInitializerFunctions: [(symbol: SymbolID, name: InternedString)] = []

    private var objectLazyInitBySymbol: [SymbolID: ObjectLazyInit] = [:]

    private(set) var deferredObjectLazyInitSymbols: [SymbolID: SymbolID] = [:]

    private var objectInitializerSymbols: Set<SymbolID> = []

    private var objectLazyInitOmittedSymbols: Set<SymbolID> = []

    private(set) var enumLazyInitByOwner: [SymbolID: (symbol: SymbolID, name: InternedString)] = [:]

    var enumEntryStorageSlots: [SymbolID: SymbolID] = [:]


    struct ScopeSnapshot {
        let localValuesBySymbol: [SymbolID: KIRExprID]
        let localDeclaredTypesBySymbol: [SymbolID: TypeID]
        let mutableCaptureCellsBySymbol: [SymbolID: KIRExprID]
        let localDelegateStorageBySymbol: [SymbolID: KIRExprID]
        let lambdaParamNameToSymbol: [InternedString: SymbolID]
        let currentImplicitReceiverExprID: KIRExprID?
        let currentImplicitReceiverSymbol: SymbolID?
        let qualifiedThisReceiverExprsByLabel: [InternedString: KIRExprID]
        let capturedOuterReceiverExprsByOwner: [SymbolID: KIRExprID]
        let contextReceiverValueStack: [[ContextReceiverValue]]
        let currentFunctionSymbol: SymbolID?
        let currentLambdaAllowsNonLocalReturn: Bool
        let currentLambdaAllowsNonLocalBreakContinue: Bool
        let nonLocalReturnTarget: SymbolID?
        let pendingLambdaNonLocalReturnAllowance: Bool
        let loopControlStack: [(continueLabel: Int32, breakLabel: Int32, name: InternedString?)]
        let enclosingLoopControlStack: [(continueLabel: Int32, breakLabel: Int32, name: InternedString?)]
        let finallyBlockStack: [(exprID: ExprID, loopDepth: Int, exceptionHandlerDepth: Int)]
        let exceptionHandlerStack: [ExceptionHandler]
        let nextLoopLabel: Int32
    }

    func saveScope() -> ScopeSnapshot {
        ScopeSnapshot(
            localValuesBySymbol: localValuesBySymbol,
            localDeclaredTypesBySymbol: localDeclaredTypesBySymbol,
            mutableCaptureCellsBySymbol: mutableCaptureCellsBySymbol,
            localDelegateStorageBySymbol: localDelegateStorageBySymbol,
            lambdaParamNameToSymbol: lambdaParamNameToSymbol,
            currentImplicitReceiverExprID: currentImplicitReceiverExprID,
            currentImplicitReceiverSymbol: currentImplicitReceiverSymbol,
            qualifiedThisReceiverExprsByLabel: qualifiedThisReceiverExprsByLabel,
            capturedOuterReceiverExprsByOwner: capturedOuterReceiverExprsByOwner,
            contextReceiverValueStack: contextReceiverValueStack,
            currentFunctionSymbol: currentFunctionSymbol,
            currentLambdaAllowsNonLocalReturn: currentLambdaAllowsNonLocalReturn,
            currentLambdaAllowsNonLocalBreakContinue: currentLambdaAllowsNonLocalBreakContinue,
            nonLocalReturnTarget: nonLocalReturnTarget,
            pendingLambdaNonLocalReturnAllowance: pendingLambdaNonLocalReturnAllowance,
            loopControlStack: loopControlStack,
            enclosingLoopControlStack: enclosingLoopControlStack,
            finallyBlockStack: finallyBlockStack,
            exceptionHandlerStack: exceptionHandlerStack,
            nextLoopLabel: nextLoopLabel
        )
    }

    func restoreScope(_ snapshot: ScopeSnapshot) {
        localValuesBySymbol = snapshot.localValuesBySymbol
        localDeclaredTypesBySymbol = snapshot.localDeclaredTypesBySymbol
        mutableCaptureCellsBySymbol = snapshot.mutableCaptureCellsBySymbol
        localDelegateStorageBySymbol = snapshot.localDelegateStorageBySymbol
        lambdaParamNameToSymbol = snapshot.lambdaParamNameToSymbol
        currentImplicitReceiverExprID = snapshot.currentImplicitReceiverExprID
        currentImplicitReceiverSymbol = snapshot.currentImplicitReceiverSymbol
        qualifiedThisReceiverExprsByLabel = snapshot.qualifiedThisReceiverExprsByLabel
        capturedOuterReceiverExprsByOwner = snapshot.capturedOuterReceiverExprsByOwner
        contextReceiverValueStack = snapshot.contextReceiverValueStack
        currentFunctionSymbol = snapshot.currentFunctionSymbol
        currentLambdaAllowsNonLocalReturn = snapshot.currentLambdaAllowsNonLocalReturn
        currentLambdaAllowsNonLocalBreakContinue = snapshot.currentLambdaAllowsNonLocalBreakContinue
        nonLocalReturnTarget = snapshot.nonLocalReturnTarget
        pendingLambdaNonLocalReturnAllowance = snapshot.pendingLambdaNonLocalReturnAllowance
        loopControlStack = snapshot.loopControlStack
        enclosingLoopControlStack = snapshot.enclosingLoopControlStack
        finallyBlockStack = snapshot.finallyBlockStack
        exceptionHandlerStack = snapshot.exceptionHandlerStack
        nextLoopLabel = snapshot.nextLoopLabel
    }

    func withNewScope<T>(_ body: () throws -> T) rethrows -> T {
        let snapshot = saveScope()
        defer { restoreScope(snapshot) }
        resetScopeForFunction()
        return try body()
    }

    func resetScopeForFunction() {
        localValuesBySymbol.removeAll(keepingCapacity: true)
        localDeclaredTypesBySymbol.removeAll(keepingCapacity: true)
        mutableCaptureCellsBySymbol.removeAll(keepingCapacity: true)
        localDelegateStorageBySymbol.removeAll(keepingCapacity: true)
        lambdaParamNameToSymbol.removeAll(keepingCapacity: true)
        currentImplicitReceiverExprID = nil
        currentImplicitReceiverSymbol = nil
        // `this@Label` entries only ever hold values valid inside one KIR
        // function's instruction stream — the exprIDs they point at are
        // dangling past a member-function/lambda boundary. Clear them so a
        // labeled `this` inside the next body cannot resolve to a stale
        // exprID from an unrelated context.
        qualifiedThisReceiverExprsByLabel.removeAll(keepingCapacity: true)
        capturedOuterReceiverExprsByOwner.removeAll(keepingCapacity: true)
        contextReceiverValueStack.removeAll(keepingCapacity: true)
        currentFunctionSymbol = nil
        currentLambdaAllowsNonLocalReturn = false
        currentLambdaAllowsNonLocalBreakContinue = false
        nonLocalReturnTarget = nil
        pendingLambdaNonLocalReturnAllowance = false
        loopControlStack.removeAll(keepingCapacity: true)
        enclosingLoopControlStack.removeAll(keepingCapacity: true)
        finallyBlockStack.removeAll(keepingCapacity: true)
        exceptionHandlerStack.removeAll(keepingCapacity: true)
        nextLoopLabel = 10000
    }

    func localValue(for symbol: SymbolID) -> KIRExprID? {
        localValuesBySymbol[symbol]
    }

    func setLocalValue(_ exprID: KIRExprID, for symbol: SymbolID) {
        localValuesBySymbol[symbol] = exprID
    }

    func clearLocalValue(for symbol: SymbolID) {
        localValuesBySymbol.removeValue(forKey: symbol)
        localDeclaredTypesBySymbol.removeValue(forKey: symbol)
        mutableCaptureCellsBySymbol.removeValue(forKey: symbol)
        localDelegateStorageBySymbol.removeValue(forKey: symbol)
    }

    func localDelegateStorage(for symbol: SymbolID) -> KIRExprID? {
        localDelegateStorageBySymbol[symbol]
    }

    func setLocalDelegateStorage(_ exprID: KIRExprID, for symbol: SymbolID) {
        localDelegateStorageBySymbol[symbol] = exprID
    }

    func localDeclaredType(for symbol: SymbolID) -> TypeID? {
        localDeclaredTypesBySymbol[symbol]
    }

    func setLocalDeclaredType(_ typeID: TypeID, for symbol: SymbolID) {
        localDeclaredTypesBySymbol[symbol] = typeID
    }

    func mutableCaptureCell(for symbol: SymbolID) -> KIRExprID? {
        mutableCaptureCellsBySymbol[symbol]
    }

    func setMutableCaptureCell(_ exprID: KIRExprID, for symbol: SymbolID) {
        mutableCaptureCellsBySymbol[symbol] = exprID
        localValuesBySymbol[symbol] = exprID
    }

    func isMutableCaptureBoxed(_ symbol: SymbolID) -> Bool {
        mutableCaptureCellsBySymbol[symbol] != nil
    }

    func allLocalValues() -> [SymbolID: KIRExprID] {
        localValuesBySymbol
    }

    func lambdaParamSymbol(named name: InternedString) -> SymbolID? {
        lambdaParamNameToSymbol[name]
    }

    func registerLambdaParam(symbol: SymbolID, forName name: InternedString) {
        lambdaParamNameToSymbol[name] = symbol
    }

    func activeImplicitReceiverExprID() -> KIRExprID? {
        currentImplicitReceiverExprID
    }

    func activeImplicitReceiverSymbol() -> SymbolID? {
        currentImplicitReceiverSymbol
    }

    func activeImplicitReceiver() -> (symbol: SymbolID, exprID: KIRExprID)? {
        guard let symbol = currentImplicitReceiverSymbol,
              let exprID = currentImplicitReceiverExprID
        else {
            return nil
        }
        return (symbol: symbol, exprID: exprID)
    }

    func setImplicitReceiver(symbol: SymbolID, exprID: KIRExprID) {
        currentImplicitReceiverSymbol = symbol
        currentImplicitReceiverExprID = exprID
    }

    func clearImplicitReceiver() {
        currentImplicitReceiverSymbol = nil
        currentImplicitReceiverExprID = nil
    }

    func qualifiedThisReceiverExprID(for label: InternedString) -> KIRExprID? {
        qualifiedThisReceiverExprsByLabel[label]
    }

    func setQualifiedThisReceiver(_ exprID: KIRExprID, for label: InternedString) {
        qualifiedThisReceiverExprsByLabel[label] = exprID
    }

    func capturedOuterReceiverExprID(for owner: SymbolID) -> KIRExprID? {
        capturedOuterReceiverExprsByOwner[owner]
    }

    func capturedOuterReceiverExprID(reaching owner: SymbolID, sema: SemaModule) -> KIRExprID? {
        capturedOuterReceiverOwner(reaching: owner, sema: sema).flatMap {
            capturedOuterReceiverExprsByOwner[$0]
        }
    }

    func capturedOuterReceiverOwner(reaching owner: SymbolID, sema: SemaModule) -> SymbolID? {
        for registeredOwner in capturedOuterReceiverExprsByOwner.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            if receiverOwnerReaches(registeredOwner, target: owner, sema: sema) {
                return registeredOwner
            }
        }
        return nil
    }

    private func receiverOwnerReaches(_ candidate: SymbolID, target: SymbolID, sema: SemaModule) -> Bool {
        var current: SymbolID? = candidate
        var visited: Set<SymbolID> = []
        while let owner = current, visited.insert(owner).inserted {
            if owner == target || sema.types.isNominalSubtypeSymbol(owner, of: target) {
                return true
            }
            current = sema.symbols.symbol(owner)?.flags.contains(.innerClass) == true
                ? sema.symbols.parentSymbol(for: owner)
                : nil
        }
        return false
    }

    func setCapturedOuterReceiver(_ exprID: KIRExprID, for owner: SymbolID) {
        capturedOuterReceiverExprsByOwner[owner] = exprID
    }

    func withContextReceiverValues<T>(
        _ values: [ContextReceiverValue],
        _ body: () throws -> T
    ) rethrows -> T {
        contextReceiverValueStack.append(values)
        defer { _ = contextReceiverValueStack.popLast() }
        return try body()
    }

    func withErasedLambdaReturnClaim<T>(
        _ claim: (declaredSymbol: SymbolID, substituted: TypeID)?,
        _ body: () throws -> T
    ) rethrows -> T {
        guard let claim else {
            return try body()
        }
        erasedLambdaReturnClaimStack.append(claim)
        defer { _ = erasedLambdaReturnClaimStack.popLast() }
        return try body()
    }

    func contextReceiverValue(matching targetType: TypeID, sema: SemaModule) -> KIRExprID? {
        let nonNullTargetType = sema.types.makeNonNullable(targetType)
        for scopeValues in contextReceiverValueStack.reversed() {
            for value in scopeValues.reversed() {
                let nonNullValueType = sema.types.makeNonNullable(value.type)
                if sema.types.isSubtype(nonNullValueType, nonNullTargetType) {
                    return value.exprID
                }
            }
        }
        return nil
    }

    func activeFunctionSymbol() -> SymbolID? {
        currentFunctionSymbol
    }

    func setCurrentFunctionSymbol(_ symbol: SymbolID?) {
        currentFunctionSymbol = symbol
    }

    func pushLoopControl(continueLabel: Int32, breakLabel: Int32, name: InternedString?) {
        loopControlStack.append((continueLabel: continueLabel, breakLabel: breakLabel, name: name))
    }


    func pushFinallyBlock(_ exprID: ExprID, exceptionHandlerDepth: Int? = nil) {
        finallyBlockStack.append((
            exprID: exprID,
            loopDepth: loopControlStack.count,
            exceptionHandlerDepth: exceptionHandlerDepth ?? exceptionHandlerStack.count
        ))
    }

    @discardableResult
    func popFinallyBlock() -> ExprID? {
        finallyBlockStack.popLast()?.exprID
    }

    func enclosingFinallyBlocks() -> [ExprID] {
        finallyBlockStack.map(\.exprID)
    }

    func pushExceptionHandler(
        exceptionSlot: KIRExprID,
        exceptionTypeSlot: KIRExprID,
        thrownTarget: Int32
    ) {
        exceptionHandlerStack.append(ExceptionHandler(
            exceptionSlot: exceptionSlot,
            exceptionTypeSlot: exceptionTypeSlot,
            thrownTarget: thrownTarget
        ))
    }

    @discardableResult
    func popExceptionHandler() -> ExceptionHandler? {
        exceptionHandlerStack.popLast()
    }

    func withExceptionHandlerTarget<T>(_ target: Int32, _ body: () throws -> T) rethrows -> T {
        precondition(!exceptionHandlerStack.isEmpty)
        let index = exceptionHandlerStack.count - 1
        let previousTarget = exceptionHandlerStack[index].thrownTarget
        exceptionHandlerStack[index].thrownTarget = target
        defer { exceptionHandlerStack[index].thrownTarget = previousTarget }
        return try body()
    }

    func withExceptionHandlerStackDepth<T>(_ depth: Int, _ body: () throws -> T) rethrows -> T {
        precondition(depth >= 0 && depth <= exceptionHandlerStack.count)
        let removedSuffix = Array(exceptionHandlerStack[depth...])
        exceptionHandlerStack.removeSubrange(depth..<exceptionHandlerStack.count)
        defer { exceptionHandlerStack.append(contentsOf: removedSuffix) }
        return try body()
    }

    func exceptionHandlerOutsideFinally(at stackIndex: Int) -> ExceptionHandler? {
        guard finallyBlockStack.indices.contains(stackIndex) else { return nil }
        let depth = finallyBlockStack[stackIndex].exceptionHandlerDepth
        guard depth > 0, depth <= exceptionHandlerStack.count else { return nil }
        return exceptionHandlerStack[depth - 1]
    }

    func exceptionHandlerDepthForFinallyBlock(at stackIndex: Int) -> Int {
        guard finallyBlockStack.indices.contains(stackIndex) else { return 0 }
        return finallyBlockStack[stackIndex].exceptionHandlerDepth
    }

    /// The returned `stackIndex` is the position of each entry in the full
    /// `finallyBlockStack`.  Callers must use this index (not the array
    /// position in the returned list) when trimming the stack via
    /// `withFinallyStackDepth` to avoid over-trimming outer entries.
    func enclosingFinallyBlocksForBreakOrContinue(targetLoopDepth: Int) -> [(exprID: ExprID, stackIndex: Int)] {
        finallyBlockStack
            .enumerated()
            .filter { $0.element.loopDepth > targetLoopDepth }
            .map { (exprID: $0.element.exprID, stackIndex: $0.offset) }
    }

    func breakTargetLoopDepth(for name: InternedString?) -> Int {
        if let name {
            if let idx = loopControlStack.lastIndex(where: { $0.name == name }) {
                return idx
            }
            if currentLambdaAllowsNonLocalBreakContinue,
               enclosingLoopControlStack.contains(where: { $0.name == name })
            {
                return -1
            }
        }
        if loopControlStack.isEmpty,
           currentLambdaAllowsNonLocalBreakContinue,
           !enclosingLoopControlStack.isEmpty
        {
            return -1
        }
        return max(0, loopControlStack.count - 1)
    }

    func withFinallyStackDepth<T>(_ depth: Int, _ body: () throws -> T) rethrows -> T {
        let removedSuffix = Array(finallyBlockStack[depth...])
        finallyBlockStack.removeSubrange(depth..<finallyBlockStack.count)
        defer { finallyBlockStack.append(contentsOf: removedSuffix) }
        return try body()
    }

    @discardableResult
    func popLoopControl() -> (continueLabel: Int32, breakLabel: Int32, name: InternedString?)? {
        loopControlStack.popLast()
    }

    func breakLabel(for name: InternedString?) -> Int32? {
        if let name {
            if let localTarget = loopControlStack.last(where: { $0.name == name })?.breakLabel {
                return localTarget
            }
            guard currentLambdaAllowsNonLocalBreakContinue,
                  let enclosingTarget = enclosingLoopControlStack.last(where: { $0.name == name })?.breakLabel
            else { return nil }
            return KIRExternalLoopJump.marker(for: enclosingTarget)
        }
        if let localTarget = loopControlStack.last?.breakLabel {
            return localTarget
        }
        guard currentLambdaAllowsNonLocalBreakContinue,
              let enclosingTarget = enclosingLoopControlStack.last?.breakLabel
        else { return nil }
        return KIRExternalLoopJump.marker(for: enclosingTarget)
    }

    func continueLabel(for name: InternedString?) -> Int32? {
        if let name {
            if let localTarget = loopControlStack.last(where: { $0.name == name })?.continueLabel {
                return localTarget
            }
            guard currentLambdaAllowsNonLocalBreakContinue,
                  let enclosingTarget = enclosingLoopControlStack.last(where: { $0.name == name })?.continueLabel
            else { return nil }
            return KIRExternalLoopJump.marker(for: enclosingTarget)
        }
        if let localTarget = loopControlStack.last?.continueLabel {
            return localTarget
        }
        guard currentLambdaAllowsNonLocalBreakContinue,
              let enclosingTarget = enclosingLoopControlStack.last?.continueLabel
        else { return nil }
        return KIRExternalLoopJump.marker(for: enclosingTarget)
    }


    func makeLoopLabel() -> Int32 {
        let label = nextLoopLabel
        nextLoopLabel += 1
        return label
    }


    func beginCallableLoweringScope() {
        pendingGeneratedCallableDeclIDs.removeAll(keepingCapacity: true)
    }

    func drainGeneratedCallableDecls() -> [KIRDeclID] {
        let generated = pendingGeneratedCallableDeclIDs
        pendingGeneratedCallableDeclIDs.removeAll(keepingCapacity: true)
        return generated
    }

    func appendGeneratedCallableDecl(_ declID: KIRDeclID) {
        pendingGeneratedCallableDeclIDs.append(declID)
    }

    func registerCallableValue(
        _ exprID: KIRExprID,
        symbol: SymbolID,
        callee: InternedString,
        captureArguments: [KIRExprID],
        hasClosureParam: Bool = false,
        unboxedSymbol: SymbolID? = nil,
        isFunctionValueBox: Bool = false
    ) {
        callableValueInfoByExprID[exprID] = KIRCallableValueInfo(
            symbol: symbol,
            callee: callee,
            captureArguments: captureArguments,
            hasClosureParam: hasClosureParam,
            unboxedSymbol: unboxedSymbol,
            isFunctionValueBox: isFunctionValueBox
        )
    }

    func callableValueInfo(for exprID: KIRExprID) -> KIRCallableValueInfo? {
        callableValueInfoByExprID[exprID]
    }

    func setFunctionDefaultArguments(_ mapping: [SymbolID: [ExprID?]]) {
        functionDefaultArgumentsBySymbol = mapping
    }

    func markTailrecFunction(_ symbol: SymbolID) {
        tailrecFunctionSymbols.insert(symbol)
    }

    func defaultArguments(for symbol: SymbolID) -> [ExprID?]? {
        functionDefaultArgumentsBySymbol[symbol]
    }


    func initializeSyntheticLambdaSymbolAllocator(sema: SemaModule, stdlibOnly: Bool = false) {
        _ = sema
        // Stdlib-only and consumer modules are linked together, but synthetic
        // lambda IDs are allocated per module. Keep their closure symbol bands
        // disjoint so a consumer lambda cannot collide with a stdlib wrapper.
        nextSyntheticLambdaSymbolRawValue = stdlibOnly ? -70_000_000 : -60_000_000
    }

    func syntheticLambdaSymbol(for exprID: ExprID) -> SymbolID {
        if let existing = syntheticLambdaSymbolsByExprID[exprID] {
            return existing
        }
        let symbol = allocateSyntheticGeneratedSymbol()
        syntheticLambdaSymbolsByExprID[exprID] = symbol
        return symbol
    }

    func allocateSyntheticGeneratedSymbol() -> SymbolID {
        SymbolID(rawValue: nextSyntheticLambdaSymbolRawID())
    }

    func syntheticObjectLiteralSymbols(
        for exprID: ExprID
    ) -> (nominalSymbol: SymbolID, constructorSymbol: SymbolID, constructorName: InternedString)? {
        syntheticObjectLiteralSymbolsByExprID[exprID]
    }

    func registerSyntheticObjectLiteralSymbols(
        _ symbols: (nominalSymbol: SymbolID, constructorSymbol: SymbolID, constructorName: InternedString),
        for exprID: ExprID
    ) {
        syntheticObjectLiteralSymbolsByExprID[exprID] = symbols
    }

    @discardableResult
    func markObjectLiteralEmitted(_ exprID: ExprID) -> Bool {
        emittedObjectLiteralExprIDs.insert(exprID).inserted
    }

    private func nextSyntheticLambdaSymbolRawID() -> Int32 {
        precondition(
            nextSyntheticLambdaSymbolRawValue > Int32.min + 1,
            "Exhausted synthetic symbol IDs for lambda lowering."
        )
        let allocated = nextSyntheticLambdaSymbolRawValue
        nextSyntheticLambdaSymbolRawValue -= 1
        return allocated
    }


    func registerCompanionInitializer(symbol: SymbolID, name: InternedString) {
        companionInitializerFunctions.append((symbol: symbol, name: name))
    }

    func allCompanionInitializers() -> [(symbol: SymbolID, name: InternedString)] {
        companionInitializerFunctions
    }

    func registerReflectionInitializer(symbol: SymbolID, name: InternedString) {
        reflectionInitializerFunctions.append((symbol: symbol, name: name))
        registerCompanionInitializer(symbol: symbol, name: name)
    }

    func allReflectionInitializers() -> [(symbol: SymbolID, name: InternedString)] {
        reflectionInitializerFunctions
    }

    func registerObjectLazyInit(
        for objectSymbol: SymbolID,
        ensureInitSymbol: SymbolID,
        ensureInitName: InternedString
    ) {
        objectLazyInitBySymbol[objectSymbol] = ObjectLazyInit(
            ensureInitSymbol: ensureInitSymbol,
            ensureInitName: ensureInitName
        )
    }

    func objectLazyInit(for objectSymbol: SymbolID) -> ObjectLazyInit? {
        objectLazyInitBySymbol[objectSymbol]
    }

    func deferredObjectLazyInitSymbol(for objectSymbol: SymbolID) -> SymbolID {
        if let symbol = deferredObjectLazyInitSymbols[objectSymbol] { return symbol }
        let symbol = allocateSyntheticGeneratedSymbol()
        deferredObjectLazyInitSymbols[objectSymbol] = symbol
        return symbol
    }

    func registerObjectInitializer(for objectSymbol: SymbolID) {
        objectInitializerSymbols.insert(objectSymbol)
    }

    func hasObjectInitializer(for objectSymbol: SymbolID) -> Bool {
        objectInitializerSymbols.contains(objectSymbol)
    }

    func markObjectLazyInitOmitted(for objectSymbol: SymbolID) {
        objectLazyInitOmittedSymbols.insert(objectSymbol)
    }

    func isObjectLazyInitOmitted(for objectSymbol: SymbolID) -> Bool {
        objectLazyInitOmittedSymbols.contains(objectSymbol)
    }

    func registerEnumLazyInit(for enumSymbol: SymbolID, symbol: SymbolID, name: InternedString) {
        enumLazyInitByOwner[enumSymbol] = (symbol, name)
    }

    func resetModuleState() {
        lambdaEnclosingClassNamesByFileID.removeAll(keepingCapacity: true)
        pendingGeneratedCallableDeclIDs.removeAll(keepingCapacity: true)
        callableValueInfoByExprID.removeAll(keepingCapacity: true)
        syntheticLambdaSymbolsByExprID.removeAll(keepingCapacity: true)
        syntheticObjectLiteralSymbolsByExprID.removeAll(keepingCapacity: true)
        emittedObjectLiteralExprIDs.removeAll(keepingCapacity: true)
        itableBridgeSymbolsByKey.removeAll(keepingCapacity: true)
        anyToStringBridgeSymbolsByImplementation.removeAll(keepingCapacity: true)
        throwableMessageBridgeSymbolsByGetter.removeAll(keepingCapacity: true)
        companionInitializerFunctions.removeAll(keepingCapacity: true)
        reflectionInitializerFunctions.removeAll(keepingCapacity: true)
        objectLazyInitBySymbol.removeAll(keepingCapacity: true)
        deferredObjectLazyInitSymbols.removeAll(keepingCapacity: true)
        objectInitializerSymbols.removeAll(keepingCapacity: true)
        objectLazyInitOmittedSymbols.removeAll(keepingCapacity: true)
        enumLazyInitByOwner.removeAll(keepingCapacity: true)
        enumEntryStorageSlots.removeAll(keepingCapacity: true)
        powerAssertCaptureStack.removeAll(keepingCapacity: true)
    }

    private var powerAssertCaptureStack: [(activeIDs: Set<ExprID>, values: [ExprID: KIRExprID])] = []

    var hasActivePowerAssertCapture: Bool {
        !powerAssertCaptureStack.isEmpty
    }

    func pushPowerAssertCapture(_ targetIDs: Set<ExprID>) {
        powerAssertCaptureStack.append((targetIDs, [:]))
    }

    func recordPowerAssertCapturedValue(exprID: ExprID, value: KIRExprID) {
        for index in powerAssertCaptureStack.indices where powerAssertCaptureStack[index].activeIDs.contains(exprID) {
            powerAssertCaptureStack[index].values[exprID] = value
        }
    }

    func popPowerAssertCapture() -> [ExprID: KIRExprID] {
        guard !powerAssertCaptureStack.isEmpty else { return [:] }
        return powerAssertCaptureStack.removeLast().values
    }
}
