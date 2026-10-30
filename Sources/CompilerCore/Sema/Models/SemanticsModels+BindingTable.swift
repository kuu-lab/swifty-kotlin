// swiftlint:disable file_length

public final class BindingTable {
    public private(set) var validatedAnnotationOptInMarkers: [String: Set<SymbolID>] = [:]

    public func recordValidatedAnnotationOptIn(usageID: String?, markers: Set<SymbolID>) {
        guard let usageID else { return }
        validatedAnnotationOptInMarkers[usageID, default: []].formUnion(markers)
    }

    public private(set) var annotationFactoryExpressions: [SymbolID: ExprID] = [:]

    /// Primary-constructor annotations selected for the synthesized property
    /// after annotation targets are resolved. Preserve tokens for factories.
    var primaryConstructorPropertyAnnotations: [SymbolID: [AnnotationNode]] = [:]

    /// Source parameter corresponding to each synthesized property. Its consent
    /// is available to header checks without changing property metadata.
    var primaryConstructorPropertyParameters: [SymbolID: (parameter: ValueParamDecl, type: TypeID, constructor: SymbolID)] = [:]

    public func bindAnnotationFactory(_ symbol: SymbolID, expression: ExprID) {
        annotationFactoryExpressions[symbol] = expression
    }

    public private(set) var exprTypes: [ExprID: TypeID] = [:]
    /// The ABI type that consumes a generic call result. This can be wider
    /// than the substituted expression type, as for `println(f<Int?>())`.
    public private(set) var genericCallConsumerTypes: [ExprID: TypeID] = [:]

    public func bindGenericCallConsumerType(_ expr: ExprID, type: TypeID?) {
        genericCallConsumerTypes[expr] = type
    }
    /// Flow-refined receiver types for local compound assignments. Their
    /// result is usually `Unit`, so the LHS type cannot be recovered from
    /// `exprTypes` during KIR lowering.
    public private(set) var compoundAssignReceiverTypes: [ExprID: TypeID] = [:]
    public private(set) var platformNullAssertionTypes: [ExprID: TypeID] = [:]

    public func bindPlatformNullAssertion(_ expr: ExprID, targetType: TypeID?) {
        platformNullAssertionTypes[expr] = targetType
    }
    /// JVM Unit returns evaluate their expression, then produce the singleton.
    public private(set) var unitReturnCoercionExprs: Set<ExprID> = []

    public func markUnitReturnCoercion(_ expr: ExprID) {
        unitReturnCoercionExprs.insert(expr)
    }
    public private(set) var whenExhaustiveness: [ExprID: Bool] = [:]
    public private(set) var identifierSymbols: [ExprID: SymbolID] = [:]
    /// Actual lambda destination and the boundaries crossed to reach it.
    /// Validated after overload resolution has bound the containing calls.
    public private(set) var lambdaReturnTargets: [ExprID: ExprID] = [:]
    public private(set) var lambdaReturnLambdaPaths: [ExprID: [ExprID]] = [:]
    public private(set) var functionReturnLambdaPaths: [ExprID: [ExprID]] = [:]
    /// Inline parameter eligibility is known only after overload resolution.
    public private(set) var loopJumpLambdaPaths: [ExprID: [ExprID]] = [:]
    public private(set) var callBindings: [ExprID: CallBinding] = [:]
    /// Specializations of callable references are separate from ordinary calls.
    public private(set) var callableReferenceBindings: [ExprID: CallBinding] = [:]

    public func bindCallableReference(_ expression: ExprID, binding: CallBinding?) {
        callableReferenceBindings[expression] = binding
    }

    public func callableReferenceBinding(for expression: ExprID) -> CallBinding? {
        callableReferenceBindings[expression]
    }

    /// Local nominal checks and field targets needing resolved accessor bindings
    /// run after expression inference.
    private var pendingAnnotationTargets: [DeclID: [[InternedString]]] = [:]

    func deferAnnotationTargets(_ declaration: DeclID, lexicalEnclosingFQNames: [[InternedString]]) {
        if pendingAnnotationTargets[declaration] == nil {
            pendingAnnotationTargets[declaration] = lexicalEnclosingFQNames
        }
    }

    func takePendingAnnotationTargets() -> [DeclID: [[InternedString]]] {
        let pending = pendingAnnotationTargets
        pendingAnnotationTargets.removeAll(keepingCapacity: false)
        return pending
    }
    /// Bundled Worker.execute entries whose jobs require a static environment.
    public private(set) var workerExecuteCallees: Set<SymbolID> = []
    public private(set) var workerExecuteJobRanges: [ExprID: SourceRange] = [:]

    public private(set) var loopIterationBindings: [ExprID: LoopIterationBinding] = [:]
    public private(set) var indexedCompoundAssignOperatorBindings: [ExprID: IndexedCompoundAssignOperatorBinding] = [:]
    public private(set) var indexedCompoundAssignElementOperatorBindings: [ExprID: IndexedCompoundAssignElementOperatorBinding] = [:]
    public private(set) var callableTargets: [ExprID: CallableTarget] = [:]
    /// `ConstructorDelegationCall` has no `ExprID` of its own, so this is keyed by
    /// the enclosing constructor's `SymbolID` instead. KIR lowering must consult
    /// this rather than re-deriving the target via FQ-name lookup, which cannot
    /// distinguish sibling overloads or exclude the constructor being lowered.
    public private(set) var constructorDelegationTargets: [SymbolID: SymbolID] = [:]
    /// Full call binding (argument -> parameter mapping) of the same delegation
    /// call, so KIR lowering can apply named-argument / default / vararg
    /// normalization exactly like an ordinary constructor call.
    public private(set) var constructorDelegationCallBindings: [SymbolID: CallBinding] = [:]
    /// Constructor selected for each enum entry, keyed by the entry field
    /// symbol because enum-entry arguments have no standalone call ExprID.
    public private(set) var enumEntryConstructorBindings: [SymbolID: CallBinding] = [:]
    public private(set) var enumEntryInvokeReceiverSymbols: [ExprID: SymbolID] = [:]
    public private(set) var callableValueCalls: [ExprID: CallableValueCallBinding] = [:]
    public private(set) var isCheckTargetTypes: [ExprID: TypeID] = [:]
    public private(set) var castTargetTypes: [ExprID: TypeID] = [:]
    public private(set) var findAnnotationSearchTypes: [ExprID: TypeID] = [:]
    public private(set) var catchClauseBindings: [ExprID: CatchClauseBinding] = [:]
    public private(set) var captureSymbolsByExpr: [ExprID: [SymbolID]] = [:]
    public private(set) var localFunctionCaptureSymbolsBySymbol: [SymbolID: [SymbolID]] = [:]
    /// STDLIB-592 definite assignment: outer-scope symbols a lambda literal's body
    /// unconditionally initializes, keyed by the lambda literal's own `ExprID`.
    /// Populated by `inferLambdaLiteralExpr` and consumed by `applyContractEffects`
    /// when the enclosing call's callee has a `callsInPlace(param, EXACTLY_ONCE/AT_LEAST_ONCE)`
    /// contract on that lambda parameter.
    public private(set) var contractCallsInPlaceInitializedSymbolsByExpr: [ExprID: [SymbolID]] = [:]
    /// Cached union of `contractCallsInPlaceInitializedSymbolsByExpr`'s values,
    /// computed once Sema has finished (mirrors `ExprLowerer.lambdaCapturedSymbols`).
    /// Lets KIR lowering ask "is this symbol EVER guaranteed-initialized by some
    /// callsInPlace lambda" without conflating it with any *other* reason a
    /// mutable local's `localValue` might transiently read as unset.
    private var cachedContractCallsInPlaceInitializedSymbolsUnion: Set<SymbolID>?
    public private(set) var declSymbols: [DeclID: SymbolID] = [:]
    public private(set) var superCallExprs: Set<ExprID> = []
    public private(set) var invokeOperatorCallExprs: Set<ExprID> = []
    public private(set) var extensionPropertyGetterCalls: [ExprID: CallBinding] = [:]
    public func bindExtensionPropertyGetterCall(_ expression: ExprID, binding: CallBinding) {
        extensionPropertyGetterCalls[expression] = binding
        propagateValueMarks(from: binding.chosenCallee, to: expression)
    }

    public private(set) var invokeOperatorPropertyCalls: [ExprID: InvokeOperatorPropertyBinding] = [:]
    public private(set) var collectionExprIDs: Set<ExprID> = []
    public private(set) var rangeExprIDs: Set<ExprID> = []
    public private(set) var charRangeExprIDs: Set<ExprID> = []
    public private(set) var uintRangeExprIDs: Set<ExprID> = []
    public private(set) var ulongRangeExprIDs: Set<ExprID> = []
    public private(set) var floatingPointRangeExprIDs: Set<ExprID> = []
    public private(set) var flowExprIDs: Set<ExprID> = []
    public private(set) var collectionSymbolIDs: Set<SymbolID> = []
    public private(set) var rangeSymbolIDs: Set<SymbolID> = []
    public private(set) var charRangeSymbolIDs: Set<SymbolID> = []
    public private(set) var uintRangeSymbolIDs: Set<SymbolID> = []
    public private(set) var ulongRangeSymbolIDs: Set<SymbolID> = []
    public private(set) var floatingPointRangeSymbolIDs: Set<SymbolID> = []
    public private(set) var flowSymbolIDs: Set<SymbolID> = []
    public private(set) var floatingPointRangeElementTypesByExpr: [ExprID: TypeID] = [:]
    public private(set) var floatingPointRangeElementTypesBySymbol: [SymbolID: TypeID] = [:]
    private var openFloatingPointRangeExprIDs: Set<ExprID> = []
    private var openFloatingPointRangeSymbolIDs: Set<SymbolID> = []
    public private(set) var flowElementTypesByExpr: [ExprID: TypeID] = [:]
    public private(set) var flowElementTypesBySymbol: [SymbolID: TypeID] = [:]
    /// Tracks the real element type produced by an `async { ... }` call, keyed by
    /// expr and (once assigned to a `val`/`var`) by symbol. `Deferred` is
    /// registered with no class-level type parameter, so this side-channel
    /// mirrors the Flow element-type tracking above rather than relying on
    /// `ClassType.args` (which would create an arity mismatch against the
    /// zero-type-parameter `Deferred` symbol).
    public private(set) var deferredElementTypesByExpr: [ExprID: TypeID] = [:]
    public private(set) var deferredElementTypesBySymbol: [SymbolID: TypeID] = [:]
    public private(set) var objectLiteralPropertySymbolIDs: Set<SymbolID> = []
    /// Maps `T::class` callable-ref expression IDs to the resolved type that
    /// `T` refers to.  Used by KIR lowering to emit the correct type token
    /// and name hint for `T::class.simpleName` / `.qualifiedName`.
    public private(set) var classRefTargetTypes: [ExprID: TypeID] = [:]
    public private(set) var boundClassRefExprs: Set<ExprID> = []
    /// Maps expression IDs to their compile-time constant values when the
    /// expression references a `const val` property.  This allows downstream
    /// passes (KIR lowering, codegen) to fold constant references without
    /// re-querying the symbol table.
    public private(set) var constExprValues: [ExprID: KIRExprKind] = [:]
    public private(set) var samConversionExprs: Set<ExprID> = []
    /// Maps SAM-converted lambda expressions to their underlying function type,
    /// so KIR lowering can generate the correct callable signature.
    public private(set) var samUnderlyingFunctionTypes: [ExprID: TypeID] = [:]
    /// Maps SAM-converted expressions to the target functional interface type.
    /// Lambda literals bind the interface type as their expression type, but
    /// callable references keep their function type, so the interface must be
    /// recorded separately for KIR lowering.
    public private(set) var samInterfaceTypes: [ExprID: TypeID] = [:]
    public private(set) var builderDSLExprIDs: Set<ExprID> = []
    public private(set) var builderDSLKinds: [ExprID: BuilderDSLKind] = [:]
    public private(set) var scopeFunctionExprIDs: Set<ExprID> = []
    public private(set) var scopeFunctionKinds: [ExprID: ScopeFunctionKind] = [:]
    public private(set) var collectionHOFLambdaExprIDs: Set<ExprID> = []
    /// Contextual function type to use when a lambda escapes as a boxed function value.
    public private(set) var functionValueExpectedTypes: [ExprID: TypeID] = [:]
    /// Tracks lambda literals that are the callee of a direct invocation
    /// (`{ ... }()`). `inferCallExpr` synthesizes `() -> Any` for them, which
    /// must not leak into the lambda's own type — the call's result is the
    /// body's concrete return type.
    public private(set) var directlyInvokedLambdaExprIDs: Set<ExprID> = []
    /// Tracks `.memberCall` expressions resolved by
    /// `CallTypeChecker.tryInferFQNPackageTopLevelCall` (e.g.
    /// `kotlin.math.abs(x)`, `kotlin.text.StringBuilder()`): the receiver
    /// chain is a bare namespace path, not a real value, so it is never type
    /// -checked and must not be lowered as one.
    public private(set) var fqnTopLevelCallExprIDs: Set<ExprID> = []
    /// Tracks namespace-qualified property and classifier expressions resolved
    /// before their package-path receiver is type-checked. The receiver is a
    /// qualifier such as `kotlin.math` or `kotlin`, not a runtime value.
    public private(set) var fqnQualifiedValueExprIDs: Set<ExprID> = []
    /// Tracks `.memberCall` expressions resolved as constructors of a static
    /// nested class (for example, `Outer.Inner()`): the type qualifier is not
    /// an instance receiver and must not be passed to the constructor ABI.
    public private(set) var typeQualifiedConstructorCallExprIDs: Set<ExprID> = []
    /// KUU-1211: `Comparable<Char>` locals that `ComparableCharEscapeAnalyzer`
    /// proved can keep kotlinc's unboxed `compareTo` semantics (normalized
    /// -1/0/1 like `Intrinsics.compare` on a primitive `char`). Populated once
    /// after body analysis; consumed by KIR lowering to swap the generic
    /// `__kk_comparable_compareTo` dispatch for `kk_char_compareTo` on
    /// `nameRef` receivers bound to these symbols.
    public private(set) var nonEscapingComparableCharLocals: Set<SymbolID> = []
    /// Tracks lambda literals passed to a KIR-level coroutine launcher
    /// (`runBlocking`/`launch`/`async`/`produce`) whose captures are forwarded
    /// via CoroutineLoweringPass's dedicated launcher-continuation rewrite
    /// (CoroutineLoweringPass+LauncherSupport.swift) rather than the generic
    /// escaping-callable-value (`kk_function_create_N`) ABI.
    public private(set) var coroutineLauncherLambdaExprIDs: Set<ExprID> = []
    /// Runtime trampolines require a raw suspend entry, not a nested boxed adapter.
    public private(set) var rawSuspendEntryLambdaExprIDs: Set<ExprID> = []
    /// Receivers supplied by the running continuation, not by launcherArgs.
    public private(set) var coroutineScopeLambdaReceiverTypes: [ExprID: TypeID] = [:]
    /// Tracks expressions whose expected type comes from a type annotation
    /// written in source (a property or local declaration's `: Type`), as
    /// opposed to an expected type the compiler synthesized while inferring a
    /// call. Only source-declared expected types are authoritative enough to
    /// contradict an explicit lambda parameter annotation with `Any`.
    public private(set) var sourceDeclaredExpectedTypeExprIDs: Set<ExprID> = []
    /// Callable literals checked against nominal FunctionN still infer a
    /// function type, but must materialize their closure ABI before escaping.
    public private(set) var nominalFunctionExpectedTypes: [ExprID: TypeID] = [:]
    public private(set) var stdlibSpecialCallExprIDs: Set<ExprID> = []
    public private(set) var stdlibSpecialCallKinds: [ExprID: StdlibSpecialCallKind] = [:]
    public private(set) var implicitReceiverMemberNames: [ExprID: InternedString] = [:]
    /// Static or flow-refined receiver type selected by implicit-member lookup.
    /// The KIR receiver value can retain its declaration type after a smart cast.
    public private(set) var implicitReceiverMemberReceiverTypes: [ExprID: TypeID] = [:]
    /// For member accesses that resolved on an *outer* implicit receiver (e.g. an
    /// enclosing class's member called unqualified from an object literal's
    /// member body), the enclosing function's receiver parameter symbol. KIR
    /// lowering reads the receiver through the captured value of that symbol
    /// instead of the innermost implicit receiver.
    public private(set) var implicitReceiverOuterReceiverSymbols: [ExprID: SymbolID] = [:]
    /// For implicit member-extension calls, the receiver-tower entry whose
    /// value supplies the declared extension receiver argument: e.g. `bump()`
    /// inside `with("s") { ... }` nested in `fun Int.gapProbe()` picks the
    /// enclosing `Int` receiver parameter, which capture analysis then routes
    /// into the lambda so KIR lowering reads the real Int value rather than
    /// the lambda's own `String` receiver. `implicitReceiverOuterReceiver`
    /// names the *dispatch* side; this names the *extension* side.
    public private(set) var implicitExtensionReceiverSymbols: [ExprID: SymbolID] = [:]
    /// Calls resolved through the ambient CoroutineScope of a coroutine builder
    /// need a runtime receiver even though the builder lambda keeps a no-receiver
    /// function ABI.
    public private(set) var coroutineScopeImplicitReceiverCallExprs: Set<ExprID> = []
    /// Maps callable reference expression IDs to their kind (function vs property)
    /// so that KIR lowering can emit KFunction / KProperty type identity (REFL-003).
    public private(set) var callableRefKinds: [ExprID: CallableRefKind] = [:]
    public var inferredCallableReferenceSymbols: Set<SymbolID> = []
    /// Tracks callable reference expressions that are unbound type references
    /// (e.g. `Type::member`).  The receiver is not captured; instead it
    /// becomes a parameter of the resulting function type (REFL-003).
    public private(set) var unboundCallableRefs: Set<ExprID> = []
    /// REFL-PRIMOP: primitive arithmetic operators (`Int.plus`/`times`, ...)
    /// have no real member symbol -- CallTypeChecker's
    /// `tryInferRegularMemberCallPrimitiveSpecials` binds a call's result
    /// type directly from the receiver/argument types instead of resolving a
    /// `plus`/`times` symbol. A callable reference to one (`Int::plus`) has
    /// no symbol to bind either, so this records which raw binary operator
    /// KIR lowering should synthesize a wrapper function around in its place.
    public private(set) var primitiveOperatorCallableRefs: [ExprID: BinaryOp] = [:]
    /// `Boolean::not` has no backing member symbol, so KIR lowering synthesizes
    /// a wrapper around the raw unary Boolean operation instead.
    public private(set) var primitiveUnaryOperatorCallableRefs: [ExprID: UnaryOp] = [:]
    /// `Int::toString` used as a `(Int) -> String` function value: `toString()`
    /// on a receiver has no member symbol (only the `toString(radix)` overload
    /// is a real declaration), so KIR lowering synthesizes a wrapper that
    /// stringifies its argument the way a literal `x.toString()` does.
    public private(set) var anyToStringCallableRefs: Set<ExprID> = []
    /// KSP-CAP-001: outer local variables/parameters captured by an object
    /// literal's member function bodies, keyed by the object literal's
    /// synthesized class symbol. Populated during Sema so KIR lowering can
    /// materialize each captured symbol as an instance field.
    public private(set) var objectLiteralCaptureSymbolsByOwner: [SymbolID: [SymbolID]] = [:]
    /// Mutable outer receiver properties are accessed through the enclosing
    /// instance, so object literals that use them capture that receiver here.
    public private(set) var objectLiteralCapturedReceiversByOwner: [SymbolID: (receiverSymbol: SymbolID, ownerSymbol: SymbolID)] = [:]
    /// Static type of a captured local/parameter symbol at the point it was
    /// captured, keyed by the captured symbol itself. `LocalBindings` (where
    /// this type normally lives) is a Sema-only, transient structure, so KIR
    /// lowering needs this durable side-channel to know what type to load a
    /// captured field back as.
    public private(set) var capturedLocalTypesBySymbol: [SymbolID: TypeID] = [:]
    /// Maps a destructuring declaration (or `for (a, b) in ...`) expression to the
    /// `componentN` function chosen per position. Names like `component1` are
    /// shared by several declarations (Pair, user extensions, bundled stdlib
    /// extensions), so KIR lowering must dispatch on the resolved symbol rather
    /// than re-resolving by name.
    public private(set) var destructuringComponentCallees: [ExprID: [Int: SymbolID]] = [:]
    var destructuringPropertyBindings: [ExprID: [Int: DestructuringPropertyBinding]] = [:]

    /// The initial independent-body contract permits scalar expression types,
    /// parameter references, and flow-refined compound-assignment receiver
    /// types. Any other side-table write rejects the worker delta, including
    /// calls, captures and Worker.execute metadata.
    var hasOnlyIndependentScalarBindings: Bool {
        hasOnlyIndependentScalarBindings(allowingSourceDeclaredExpectedTypeExprIDs: [])
    }

    func hasOnlyIndependentScalarBindings(allowingSourceDeclaredExpectedTypeExprIDs allowed: Set<ExprID>) -> Bool {
        if !validatedAnnotationOptInMarkers.isEmpty { return false }
        if !annotationFactoryExpressions.isEmpty { return false }
        if !primaryConstructorPropertyAnnotations.isEmpty { return false }
        if !pendingAnnotationTargets.isEmpty { return false }
        if !callableReferenceBindings.isEmpty { return false }
        if !genericCallConsumerTypes.isEmpty { return false }
        if !platformNullAssertionTypes.isEmpty { return false }
        if !unitReturnCoercionExprs.isEmpty { return false }
        if !whenExhaustiveness.isEmpty { return false }
        if !lambdaReturnTargets.isEmpty { return false }
        if !lambdaReturnLambdaPaths.isEmpty { return false }
        if !functionReturnLambdaPaths.isEmpty { return false }
        if !loopJumpLambdaPaths.isEmpty { return false }
        if !callBindings.isEmpty { return false }
        if !workerExecuteCallees.isEmpty { return false }
        if !workerExecuteJobRanges.isEmpty { return false }
        if !loopIterationBindings.isEmpty { return false }
        if !indexedCompoundAssignOperatorBindings.isEmpty { return false }
        if !indexedCompoundAssignElementOperatorBindings.isEmpty { return false }
        if !callableTargets.isEmpty { return false }
        if !constructorDelegationTargets.isEmpty { return false }
        if !constructorDelegationCallBindings.isEmpty { return false }
        if !enumEntryConstructorBindings.isEmpty { return false }
        if !enumEntryInvokeReceiverSymbols.isEmpty { return false }
        if !callableValueCalls.isEmpty { return false }
        if !isCheckTargetTypes.isEmpty { return false }
        if !castTargetTypes.isEmpty { return false }
        if !findAnnotationSearchTypes.isEmpty { return false }
        if !catchClauseBindings.isEmpty { return false }
        if !captureSymbolsByExpr.isEmpty { return false }
        if !localFunctionCaptureSymbolsBySymbol.isEmpty { return false }
        if !contractCallsInPlaceInitializedSymbolsByExpr.isEmpty { return false }
        if cachedContractCallsInPlaceInitializedSymbolsUnion != nil { return false }
        if !declSymbols.isEmpty { return false }
        if !superCallExprs.isEmpty { return false }
        if !invokeOperatorCallExprs.isEmpty { return false }
        if !extensionPropertyGetterCalls.isEmpty { return false }
        if !invokeOperatorPropertyCalls.isEmpty { return false }
        if !collectionExprIDs.isEmpty { return false }
        if !rangeExprIDs.isEmpty { return false }
        if !charRangeExprIDs.isEmpty { return false }
        if !uintRangeExprIDs.isEmpty { return false }
        if !ulongRangeExprIDs.isEmpty { return false }
        if !floatingPointRangeExprIDs.isEmpty { return false }
        if !flowExprIDs.isEmpty { return false }
        if !collectionSymbolIDs.isEmpty { return false }
        if !rangeSymbolIDs.isEmpty { return false }
        if !charRangeSymbolIDs.isEmpty { return false }
        if !uintRangeSymbolIDs.isEmpty { return false }
        if !ulongRangeSymbolIDs.isEmpty { return false }
        if !floatingPointRangeSymbolIDs.isEmpty { return false }
        if !flowSymbolIDs.isEmpty { return false }
        if !floatingPointRangeElementTypesByExpr.isEmpty { return false }
        if !floatingPointRangeElementTypesBySymbol.isEmpty { return false }
        if !openFloatingPointRangeExprIDs.isEmpty { return false }
        if !openFloatingPointRangeSymbolIDs.isEmpty { return false }
        if !flowElementTypesByExpr.isEmpty { return false }
        if !flowElementTypesBySymbol.isEmpty { return false }
        if !deferredElementTypesByExpr.isEmpty { return false }
        if !deferredElementTypesBySymbol.isEmpty { return false }
        if !objectLiteralPropertySymbolIDs.isEmpty { return false }
        if !classRefTargetTypes.isEmpty { return false }
        if !boundClassRefExprs.isEmpty { return false }
        if !constExprValues.isEmpty { return false }
        if !samConversionExprs.isEmpty { return false }
        if !samUnderlyingFunctionTypes.isEmpty { return false }
        if !samInterfaceTypes.isEmpty { return false }
        if !builderDSLExprIDs.isEmpty { return false }
        if !builderDSLKinds.isEmpty { return false }
        if !scopeFunctionExprIDs.isEmpty { return false }
        if !scopeFunctionKinds.isEmpty { return false }
        if !collectionHOFLambdaExprIDs.isEmpty { return false }
        if !functionValueExpectedTypes.isEmpty { return false }
        if !directlyInvokedLambdaExprIDs.isEmpty { return false }
        if !fqnTopLevelCallExprIDs.isEmpty { return false }
        if !fqnQualifiedValueExprIDs.isEmpty { return false }
        if !typeQualifiedConstructorCallExprIDs.isEmpty { return false }
        if !nonEscapingComparableCharLocals.isEmpty { return false }
        if !coroutineLauncherLambdaExprIDs.isEmpty { return false }
        if !rawSuspendEntryLambdaExprIDs.isEmpty { return false }
        if !coroutineScopeLambdaReceiverTypes.isEmpty { return false }
        if !sourceDeclaredExpectedTypeExprIDs.isSubset(of: allowed) { return false }
        if !nominalFunctionExpectedTypes.isEmpty { return false }
        if !stdlibSpecialCallExprIDs.isEmpty { return false }
        if !stdlibSpecialCallKinds.isEmpty { return false }
        if !implicitReceiverMemberNames.isEmpty { return false }
        if !implicitReceiverMemberReceiverTypes.isEmpty { return false }
        if !implicitReceiverOuterReceiverSymbols.isEmpty { return false }
        if !implicitExtensionReceiverSymbols.isEmpty { return false }
        if !coroutineScopeImplicitReceiverCallExprs.isEmpty { return false }
        if !callableRefKinds.isEmpty { return false }
        if !inferredCallableReferenceSymbols.isEmpty { return false }
        if !unboundCallableRefs.isEmpty { return false }
        if !primitiveOperatorCallableRefs.isEmpty { return false }
        if !primitiveUnaryOperatorCallableRefs.isEmpty { return false }
        if !anyToStringCallableRefs.isEmpty { return false }
        if !objectLiteralCaptureSymbolsByOwner.isEmpty { return false }
        if !objectLiteralCapturedReceiversByOwner.isEmpty { return false }
        if !capturedLocalTypesBySymbol.isEmpty { return false }
        if !destructuringComponentCallees.isEmpty { return false }
        if !destructuringPropertyBindings.isEmpty { return false }
        return true
    }

    /// Joins the closed scalar delta at its original declaration position.
    func mergeIndependentScalarExpressions(
        types: [ExprID: TypeID], identifiers: [ExprID: SymbolID], typeMapping: [TypeID: TypeID],
        compoundAssignReceiverTypes: [ExprID: TypeID] = [:],
        sourceDeclaredExpectedTypeExpressions: Set<ExprID> = [],
        symbolMapping: [SymbolID: SymbolID] = [:]
    ) {
        exprTypes.merge(types.mapValues { typeMapping[$0] ?? $0 }, uniquingKeysWith: { _, new in new })
        identifierSymbols.merge(identifiers.mapValues { symbolMapping[$0] ?? $0 }, uniquingKeysWith: { _, new in new })
        self.compoundAssignReceiverTypes.merge(
            compoundAssignReceiverTypes.mapValues { typeMapping[$0] ?? $0 },
            uniquingKeysWith: { _, new in new }
        )
        sourceDeclaredExpectedTypeExprIDs.formUnion(sourceDeclaredExpectedTypeExpressions)
    }

    /// Value-owned snapshot of every binding side table, including pending
    /// annotation checks and cached unions. Mutating a worker never changes
    /// the module's dictionary storage. General snapshots remain isolated;
    /// only an explicitly supported delta may be joined.
    func makeSemaWorkerBindings() -> BindingTable {
        let worker = BindingTable()
        worker.validatedAnnotationOptInMarkers = validatedAnnotationOptInMarkers
        worker.annotationFactoryExpressions = annotationFactoryExpressions
        worker.primaryConstructorPropertyAnnotations = primaryConstructorPropertyAnnotations
        worker.exprTypes = exprTypes
        worker.genericCallConsumerTypes = genericCallConsumerTypes
        worker.compoundAssignReceiverTypes = compoundAssignReceiverTypes
        worker.platformNullAssertionTypes = platformNullAssertionTypes
        worker.whenExhaustiveness = whenExhaustiveness
        worker.identifierSymbols = identifierSymbols
        worker.lambdaReturnTargets = lambdaReturnTargets
        worker.lambdaReturnLambdaPaths = lambdaReturnLambdaPaths
        worker.functionReturnLambdaPaths = functionReturnLambdaPaths
        worker.loopJumpLambdaPaths = loopJumpLambdaPaths
        worker.callBindings = callBindings
        worker.callableReferenceBindings = callableReferenceBindings
        worker.pendingAnnotationTargets = pendingAnnotationTargets
        worker.workerExecuteCallees = workerExecuteCallees
        worker.workerExecuteJobRanges = workerExecuteJobRanges
        worker.loopIterationBindings = loopIterationBindings
        worker.indexedCompoundAssignOperatorBindings = indexedCompoundAssignOperatorBindings
        worker.indexedCompoundAssignElementOperatorBindings = indexedCompoundAssignElementOperatorBindings
        worker.callableTargets = callableTargets
        worker.constructorDelegationTargets = constructorDelegationTargets
        worker.constructorDelegationCallBindings = constructorDelegationCallBindings
        worker.enumEntryConstructorBindings = enumEntryConstructorBindings
        worker.enumEntryInvokeReceiverSymbols = enumEntryInvokeReceiverSymbols
        worker.callableValueCalls = callableValueCalls
        worker.isCheckTargetTypes = isCheckTargetTypes
        worker.castTargetTypes = castTargetTypes
        worker.findAnnotationSearchTypes = findAnnotationSearchTypes
        worker.catchClauseBindings = catchClauseBindings
        worker.captureSymbolsByExpr = captureSymbolsByExpr
        worker.localFunctionCaptureSymbolsBySymbol = localFunctionCaptureSymbolsBySymbol
        worker.contractCallsInPlaceInitializedSymbolsByExpr = contractCallsInPlaceInitializedSymbolsByExpr
        worker.cachedContractCallsInPlaceInitializedSymbolsUnion = cachedContractCallsInPlaceInitializedSymbolsUnion
        worker.declSymbols = declSymbols
        worker.superCallExprs = superCallExprs
        worker.invokeOperatorCallExprs = invokeOperatorCallExprs
        worker.extensionPropertyGetterCalls = extensionPropertyGetterCalls
        worker.invokeOperatorPropertyCalls = invokeOperatorPropertyCalls
        worker.collectionExprIDs = collectionExprIDs
        worker.rangeExprIDs = rangeExprIDs
        worker.charRangeExprIDs = charRangeExprIDs
        worker.uintRangeExprIDs = uintRangeExprIDs
        worker.ulongRangeExprIDs = ulongRangeExprIDs
        worker.floatingPointRangeExprIDs = floatingPointRangeExprIDs
        worker.flowExprIDs = flowExprIDs
        worker.collectionSymbolIDs = collectionSymbolIDs
        worker.rangeSymbolIDs = rangeSymbolIDs
        worker.charRangeSymbolIDs = charRangeSymbolIDs
        worker.uintRangeSymbolIDs = uintRangeSymbolIDs
        worker.ulongRangeSymbolIDs = ulongRangeSymbolIDs
        worker.floatingPointRangeSymbolIDs = floatingPointRangeSymbolIDs
        worker.flowSymbolIDs = flowSymbolIDs
        worker.floatingPointRangeElementTypesByExpr = floatingPointRangeElementTypesByExpr
        worker.floatingPointRangeElementTypesBySymbol = floatingPointRangeElementTypesBySymbol
        worker.openFloatingPointRangeExprIDs = openFloatingPointRangeExprIDs
        worker.openFloatingPointRangeSymbolIDs = openFloatingPointRangeSymbolIDs
        worker.flowElementTypesByExpr = flowElementTypesByExpr
        worker.flowElementTypesBySymbol = flowElementTypesBySymbol
        worker.deferredElementTypesByExpr = deferredElementTypesByExpr
        worker.deferredElementTypesBySymbol = deferredElementTypesBySymbol
        worker.objectLiteralPropertySymbolIDs = objectLiteralPropertySymbolIDs
        worker.classRefTargetTypes = classRefTargetTypes
        worker.boundClassRefExprs = boundClassRefExprs
        worker.constExprValues = constExprValues
        worker.samConversionExprs = samConversionExprs
        worker.samUnderlyingFunctionTypes = samUnderlyingFunctionTypes
        worker.samInterfaceTypes = samInterfaceTypes
        worker.builderDSLExprIDs = builderDSLExprIDs
        worker.builderDSLKinds = builderDSLKinds
        worker.scopeFunctionExprIDs = scopeFunctionExprIDs
        worker.scopeFunctionKinds = scopeFunctionKinds
        worker.collectionHOFLambdaExprIDs = collectionHOFLambdaExprIDs
        worker.functionValueExpectedTypes = functionValueExpectedTypes
        worker.directlyInvokedLambdaExprIDs = directlyInvokedLambdaExprIDs
        worker.fqnTopLevelCallExprIDs = fqnTopLevelCallExprIDs
        worker.fqnQualifiedValueExprIDs = fqnQualifiedValueExprIDs
        worker.typeQualifiedConstructorCallExprIDs = typeQualifiedConstructorCallExprIDs
        worker.nonEscapingComparableCharLocals = nonEscapingComparableCharLocals
        worker.coroutineLauncherLambdaExprIDs = coroutineLauncherLambdaExprIDs
        worker.rawSuspendEntryLambdaExprIDs = rawSuspendEntryLambdaExprIDs
        worker.coroutineScopeLambdaReceiverTypes = coroutineScopeLambdaReceiverTypes
        worker.sourceDeclaredExpectedTypeExprIDs = sourceDeclaredExpectedTypeExprIDs
        worker.nominalFunctionExpectedTypes = nominalFunctionExpectedTypes
        worker.stdlibSpecialCallExprIDs = stdlibSpecialCallExprIDs
        worker.stdlibSpecialCallKinds = stdlibSpecialCallKinds
        worker.implicitReceiverMemberNames = implicitReceiverMemberNames
        worker.implicitReceiverMemberReceiverTypes = implicitReceiverMemberReceiverTypes
        worker.implicitReceiverOuterReceiverSymbols = implicitReceiverOuterReceiverSymbols
        worker.implicitExtensionReceiverSymbols = implicitExtensionReceiverSymbols
        worker.coroutineScopeImplicitReceiverCallExprs = coroutineScopeImplicitReceiverCallExprs
        worker.callableRefKinds = callableRefKinds
        worker.inferredCallableReferenceSymbols = inferredCallableReferenceSymbols
        worker.unboundCallableRefs = unboundCallableRefs
        worker.primitiveOperatorCallableRefs = primitiveOperatorCallableRefs
        worker.primitiveUnaryOperatorCallableRefs = primitiveUnaryOperatorCallableRefs
        worker.anyToStringCallableRefs = anyToStringCallableRefs
        worker.objectLiteralCaptureSymbolsByOwner = objectLiteralCaptureSymbolsByOwner
        worker.objectLiteralCapturedReceiversByOwner = objectLiteralCapturedReceiversByOwner
        worker.capturedLocalTypesBySymbol = capturedLocalTypesBySymbol
        worker.destructuringComponentCallees = destructuringComponentCallees
        worker.destructuringPropertyBindings = destructuringPropertyBindings
        return worker
    }

    public init() {}

    public func bindExprType(_ expr: ExprID, type: TypeID) {
        exprTypes[expr] = type
    }

    public func bindCompoundAssignReceiverType(_ expr: ExprID, type: TypeID) {
        compoundAssignReceiverTypes[expr] = type
    }

    public func compoundAssignReceiverType(for expr: ExprID) -> TypeID? {
        compoundAssignReceiverTypes[expr]
    }

    public func bindWhenExhaustiveness(_ expr: ExprID, isExhaustive: Bool) {
        whenExhaustiveness[expr] = isExhaustive
    }

    public func bindIdentifier(_ expr: ExprID, symbol: SymbolID) {
        identifierSymbols[expr] = symbol
        propagateValueMarks(from: symbol, to: expr)
    }

    public func setNonEscapingComparableCharLocals(_ symbols: Set<SymbolID>) {
        nonEscapingComparableCharLocals = symbols
    }

    func bindFunctionReturn(_ expr: ExprID, symbol: SymbolID, lambdaPath: [ExprID]) {
        identifierSymbols[expr] = symbol
        functionReturnLambdaPaths[expr] = lambdaPath
    }

    func bindLoopJump(_ expr: ExprID, lambdaPath: [ExprID]) {
        loopJumpLambdaPaths[expr] = lambdaPath
    }

    func bindLambdaReturn(_ expr: ExprID, target: ExprID, lambdaPath: [ExprID]) {
        lambdaReturnTargets[expr] = target
        lambdaReturnLambdaPaths[expr] = lambdaPath
    }

    public func bindCall(_ expr: ExprID, binding: CallBinding) {
        callBindings[expr] = binding
        propagateValueMarks(from: binding.chosenCallee, to: expr)
    }

    /// Symbols holding a range/collection/flow value carry side-channel marks so
    /// membership and member lowering can pick the typed runtime bridge. An
    /// expression bound to such a symbol evaluates to that same runtime value,
    /// so the marks transfer. `inferLocalDeclExpr` performs this copy explicitly
    /// for local declarations; doing it inside `bindIdentifier`/`bindCall`
    /// extends the convention to name/member reads of top-level, member, and
    /// object properties, and to calls of range-returning functions (KUU-2942:
    /// `0.0 in TOP_LEVEL_RANGE` must reach `__kk_double_range_contains` rather
    /// than falling back to the generic `kk_op_contains`/Comparable path, which
    /// misclassifies `0.0..-0.0` as empty).
    private func propagateValueMarks(from symbol: SymbolID, to expr: ExprID) {
        if rangeSymbolIDs.contains(symbol) {
            rangeExprIDs.insert(expr)
        }
        if charRangeSymbolIDs.contains(symbol) {
            charRangeExprIDs.insert(expr)
        }
        if uintRangeSymbolIDs.contains(symbol) {
            uintRangeExprIDs.insert(expr)
        }
        if ulongRangeSymbolIDs.contains(symbol) {
            ulongRangeExprIDs.insert(expr)
        }
        if floatingPointRangeSymbolIDs.contains(symbol) {
            floatingPointRangeExprIDs.insert(expr)
            if let elementType = floatingPointRangeElementTypesBySymbol[symbol] {
                floatingPointRangeElementTypesByExpr[expr] = elementType
            }
            if openFloatingPointRangeSymbolIDs.contains(symbol) {
                openFloatingPointRangeExprIDs.insert(expr)
            } else {
                openFloatingPointRangeExprIDs.remove(expr)
            }
        }
        if collectionSymbolIDs.contains(symbol) {
            collectionExprIDs.insert(expr)
        }
        if flowSymbolIDs.contains(symbol) {
            flowExprIDs.insert(expr)
            if let elementType = flowElementTypesBySymbol[symbol] {
                flowElementTypesByExpr[expr] = elementType
            }
        }
        if let elementType = deferredElementTypesBySymbol[symbol] {
            deferredElementTypesByExpr[expr] = elementType
        }
    }

    public func markWorkerExecuteCallee(_ symbol: SymbolID) {
        workerExecuteCallees.insert(symbol)
    }

    public func bindWorkerExecuteJobRange(_ expr: ExprID, range: SourceRange) {
        workerExecuteJobRanges[expr] = range
    }

    public func bindLoopIteration(_ expr: ExprID, binding: LoopIterationBinding) {
        loopIterationBindings[expr] = binding
    }

    public func bindIndexedCompoundAssignOperator(_ expr: ExprID, binding: IndexedCompoundAssignOperatorBinding) {
        indexedCompoundAssignOperatorBindings[expr] = binding
    }

    public func bindIndexedCompoundAssignElementOperator(_ expr: ExprID, binding: IndexedCompoundAssignElementOperatorBinding) {
        indexedCompoundAssignElementOperatorBindings[expr] = binding
    }

    public func bindCallableTarget(_ expr: ExprID, target: CallableTarget) {
        callableTargets[expr] = target
    }


    public func bindConstructorDelegationCall(_ ctorSymbol: SymbolID, binding: CallBinding) {
        constructorDelegationTargets[ctorSymbol] = binding.chosenCallee
        constructorDelegationCallBindings[ctorSymbol] = binding
    }

    public func bindEnumEntryConstructor(_ entrySymbol: SymbolID, binding: CallBinding) {
        enumEntryConstructorBindings[entrySymbol] = binding
    }

    public func bindCallableValueCall(_ expr: ExprID, binding: CallableValueCallBinding) {
        callableValueCalls[expr] = binding
    }

    public func bindIsCheckTargetType(_ expr: ExprID, type: TypeID) {
        isCheckTargetTypes[expr] = type
    }

    public func bindCastTargetType(_ expr: ExprID, type: TypeID) {
        castTargetTypes[expr] = type
    }

    /// STDLIB-REFLECT-065: Records the reified `T` argument of a
    /// `KClass<*>.findAnnotation<T>()` call so KIR lowering can compute the
    /// runtime search name (see `__kk_kclass_find_annotation_typed`).
    public func bindFindAnnotationSearchType(_ expr: ExprID, type: TypeID) {
        findAnnotationSearchTypes[expr] = type
    }

    public func bindCatchClause(_ catchBodyExpr: ExprID, binding: CatchClauseBinding) {
        catchClauseBindings[catchBodyExpr] = binding
    }

    public func bindDestructuringComponentCallee(_ expr: ExprID, index: Int, symbol: SymbolID) {
        destructuringComponentCallees[expr, default: [:]][index] = symbol
    }

    public func destructuringComponentCallee(for expr: ExprID, index: Int) -> SymbolID? {
        destructuringComponentCallees[expr]?[index]
    }

    func bindDestructuringProperty(
        _ expr: ExprID,
        index: Int,
        binding: DestructuringPropertyBinding
    ) {
        destructuringPropertyBindings[expr, default: [:]][index] = binding
    }

    func destructuringProperty(for expr: ExprID, index: Int) -> DestructuringPropertyBinding? {
        destructuringPropertyBindings[expr]?[index]
    }

    public func bindContractCallsInPlaceInitializedSymbols(_ expr: ExprID, symbols: [SymbolID]) {
        contractCallsInPlaceInitializedSymbolsByExpr[expr] = symbols
        cachedContractCallsInPlaceInitializedSymbolsUnion = nil
    }

    public func contractCallsInPlaceInitializedSymbols(for expr: ExprID) -> [SymbolID] {
        contractCallsInPlaceInitializedSymbolsByExpr[expr] ?? []
    }

    public func isContractCallsInPlaceInitializedSymbol(_ symbol: SymbolID) -> Bool {
        if cachedContractCallsInPlaceInitializedSymbolsUnion == nil {
            cachedContractCallsInPlaceInitializedSymbolsUnion = Set(contractCallsInPlaceInitializedSymbolsByExpr.values.joined())
        }
        return cachedContractCallsInPlaceInitializedSymbolsUnion?.contains(symbol) == true
    }

    public func bindCaptureSymbols(_ expr: ExprID, symbols: [SymbolID]) {
        let unique = Array(Set(symbols)).sorted(by: { $0.rawValue < $1.rawValue })
        captureSymbolsByExpr[expr] = unique
    }

    public func bindLocalFunctionCaptureSymbols(_ symbol: SymbolID, symbols: [SymbolID]) {
        localFunctionCaptureSymbolsBySymbol[symbol] = Array(Set(symbols)).sorted(by: { $0.rawValue < $1.rawValue })
    }

    public func localFunctionCaptureSymbols(for symbol: SymbolID) -> [SymbolID] {
        localFunctionCaptureSymbolsBySymbol[symbol] ?? []
    }

    public func bindDecl(_ decl: DeclID, symbol: SymbolID) {
        declSymbols[decl] = symbol
    }

    public func markSuperCall(_ expr: ExprID) {
        superCallExprs.insert(expr)
    }

    public func markInvokeOperatorCall(_ expr: ExprID) {
        invokeOperatorCallExprs.insert(expr)
    }

    public func bindInvokeOperatorPropertyCall(_ expr: ExprID, binding: InvokeOperatorPropertyBinding) {
        invokeOperatorPropertyCalls[expr] = binding
    }

    public func markCollectionExpr(_ expr: ExprID) {
        collectionExprIDs.insert(expr)
    }

    public func isCollectionExpr(_ expr: ExprID) -> Bool {
        collectionExprIDs.contains(expr)
    }

    public func markRangeExpr(_ expr: ExprID) {
        rangeExprIDs.insert(expr)
    }

    public func isRangeExpr(_ expr: ExprID) -> Bool {
        rangeExprIDs.contains(expr)
    }

    public func markCharRangeExpr(_ expr: ExprID) {
        charRangeExprIDs.insert(expr)
    }

    public func isCharRangeExpr(_ expr: ExprID) -> Bool {
        charRangeExprIDs.contains(expr)
    }

    public func markUIntRangeExpr(_ expr: ExprID) {
        uintRangeExprIDs.insert(expr)
    }

    public func isUIntRangeExpr(_ expr: ExprID) -> Bool {
        uintRangeExprIDs.contains(expr)
    }

    public func markULongRangeExpr(_ expr: ExprID) {
        ulongRangeExprIDs.insert(expr)
    }

    public func isULongRangeExpr(_ expr: ExprID) -> Bool {
        ulongRangeExprIDs.contains(expr)
    }

    public func markFloatingPointRangeExpr(_ expr: ExprID) {
        floatingPointRangeExprIDs.insert(expr)
    }

    public func isFloatingPointRangeExpr(_ expr: ExprID) -> Bool {
        floatingPointRangeExprIDs.contains(expr)
    }

    public func bindFloatingPointRangeElementType(_ type: TypeID, forExpr expr: ExprID, endExclusive: Bool = false) {
        floatingPointRangeExprIDs.insert(expr)
        floatingPointRangeElementTypesByExpr[expr] = type
        if endExclusive {
            openFloatingPointRangeExprIDs.insert(expr)
        } else {
            openFloatingPointRangeExprIDs.remove(expr)
        }
    }

    public func isOpenFloatingPointRangeExpr(_ expr: ExprID) -> Bool {
        openFloatingPointRangeExprIDs.contains(expr)
    }

    public func floatingPointRangeElementType(forExpr expr: ExprID) -> TypeID? {
        floatingPointRangeElementTypesByExpr[expr]
    }

    public func markFlowExpr(_ expr: ExprID) {
        flowExprIDs.insert(expr)
    }

    public func isFlowExpr(_ expr: ExprID) -> Bool {
        flowExprIDs.contains(expr)
    }

    public func bindFlowElementType(_ type: TypeID, forExpr expr: ExprID) {
        flowExprIDs.insert(expr)
        flowElementTypesByExpr[expr] = type
    }

    public func flowElementType(forExpr expr: ExprID) -> TypeID? {
        flowElementTypesByExpr[expr]
    }

    public func markObjectLiteralPropertySymbol(_ symbol: SymbolID) {
        objectLiteralPropertySymbolIDs.insert(symbol)
    }

    public func isObjectLiteralPropertySymbol(_ symbol: SymbolID) -> Bool {
        objectLiteralPropertySymbolIDs.contains(symbol)
    }

    public func bindObjectLiteralCaptureSymbols(_ owner: SymbolID, symbols: [SymbolID]) {
        objectLiteralCaptureSymbolsByOwner[owner] = symbols
    }

    public func objectLiteralCaptureSymbols(for owner: SymbolID) -> [SymbolID] {
        objectLiteralCaptureSymbolsByOwner[owner] ?? []
    }

    public func bindObjectLiteralCapturedReceiver(
        _ owner: SymbolID,
        receiverSymbol: SymbolID,
        ownerSymbol: SymbolID
    ) {
        objectLiteralCapturedReceiversByOwner[owner] = (receiverSymbol, ownerSymbol)
    }

    public func objectLiteralCapturedReceiver(for owner: SymbolID) -> (receiverSymbol: SymbolID, ownerSymbol: SymbolID)? {
        objectLiteralCapturedReceiversByOwner[owner]
    }

    public func bindCapturedLocalType(_ symbol: SymbolID, type: TypeID) {
        capturedLocalTypesBySymbol[symbol] = type
    }

    public func capturedLocalType(for symbol: SymbolID) -> TypeID? {
        capturedLocalTypesBySymbol[symbol]
    }

    public func markCollectionSymbol(_ symbol: SymbolID) {
        collectionSymbolIDs.insert(symbol)
    }

    public func isCollectionSymbol(_ symbol: SymbolID) -> Bool {
        collectionSymbolIDs.contains(symbol)
    }

    public func markRangeSymbol(_ symbol: SymbolID) {
        rangeSymbolIDs.insert(symbol)
    }

    public func isRangeSymbol(_ symbol: SymbolID) -> Bool {
        rangeSymbolIDs.contains(symbol)
    }

    public func markCharRangeSymbol(_ symbol: SymbolID) {
        charRangeSymbolIDs.insert(symbol)
    }

    public func isCharRangeSymbol(_ symbol: SymbolID) -> Bool {
        charRangeSymbolIDs.contains(symbol)
    }

    public func markUIntRangeSymbol(_ symbol: SymbolID) {
        uintRangeSymbolIDs.insert(symbol)
    }

    public func isUIntRangeSymbol(_ symbol: SymbolID) -> Bool {
        uintRangeSymbolIDs.contains(symbol)
    }

    public func markULongRangeSymbol(_ symbol: SymbolID) {
        ulongRangeSymbolIDs.insert(symbol)
    }

    public func isULongRangeSymbol(_ symbol: SymbolID) -> Bool {
        ulongRangeSymbolIDs.contains(symbol)
    }

    public func markFloatingPointRangeSymbol(_ symbol: SymbolID) {
        floatingPointRangeSymbolIDs.insert(symbol)
    }

    public func isFloatingPointRangeSymbol(_ symbol: SymbolID) -> Bool {
        floatingPointRangeSymbolIDs.contains(symbol)
    }

    public func bindFloatingPointRangeElementType(_ type: TypeID, forSymbol symbol: SymbolID, endExclusive: Bool = false) {
        floatingPointRangeSymbolIDs.insert(symbol)
        floatingPointRangeElementTypesBySymbol[symbol] = type
        if endExclusive {
            openFloatingPointRangeSymbolIDs.insert(symbol)
        } else {
            openFloatingPointRangeSymbolIDs.remove(symbol)
        }
    }

    public func isOpenFloatingPointRangeSymbol(_ symbol: SymbolID) -> Bool {
        openFloatingPointRangeSymbolIDs.contains(symbol)
    }

    public func floatingPointRangeElementType(forSymbol symbol: SymbolID) -> TypeID? {
        floatingPointRangeElementTypesBySymbol[symbol]
    }

    public func markFlowSymbol(_ symbol: SymbolID) {
        flowSymbolIDs.insert(symbol)
    }

    public func unmarkFlowSymbol(_ symbol: SymbolID) {
        flowSymbolIDs.remove(symbol)
        flowElementTypesBySymbol.removeValue(forKey: symbol)
    }

    public func isFlowSymbol(_ symbol: SymbolID) -> Bool {
        flowSymbolIDs.contains(symbol)
    }

    public func bindFlowElementType(_ type: TypeID, forSymbol symbol: SymbolID) {
        flowSymbolIDs.insert(symbol)
        flowElementTypesBySymbol[symbol] = type
    }

    public func flowElementType(forSymbol symbol: SymbolID) -> TypeID? {
        flowElementTypesBySymbol[symbol]
    }

    public func bindDeferredElementType(_ type: TypeID, forExpr expr: ExprID) {
        deferredElementTypesByExpr[expr] = type
    }

    public func deferredElementType(forExpr expr: ExprID) -> TypeID? {
        deferredElementTypesByExpr[expr]
    }

    public func bindDeferredElementType(_ type: TypeID, forSymbol symbol: SymbolID) {
        deferredElementTypesBySymbol[symbol] = type
    }

    public func deferredElementType(forSymbol symbol: SymbolID) -> TypeID? {
        deferredElementTypesBySymbol[symbol]
    }

    public func bindClassRefTargetType(_ expr: ExprID, type: TypeID) {
        classRefTargetTypes[expr] = type
    }

    public func classRefTargetType(for expr: ExprID) -> TypeID? {
        classRefTargetTypes[expr]
    }

    public func bindBoundClassRef(_ expr: ExprID) {
        boundClassRefExprs.insert(expr)
    }

    public func exprType(for expr: ExprID) -> TypeID? {
        exprTypes[expr]
    }

    public func identifierSymbol(for expr: ExprID) -> SymbolID? {
        identifierSymbols[expr]
    }

    public func callBinding(for expr: ExprID) -> CallBinding? {
        callBindings[expr]
    }

    public func loopIterationBinding(for expr: ExprID) -> LoopIterationBinding? {
        loopIterationBindings[expr]
    }

    public func indexedCompoundAssignOperatorBinding(for expr: ExprID) -> IndexedCompoundAssignOperatorBinding? {
        indexedCompoundAssignOperatorBindings[expr]
    }

    public func indexedCompoundAssignElementOperatorBinding(for expr: ExprID) -> IndexedCompoundAssignElementOperatorBinding? {
        indexedCompoundAssignElementOperatorBindings[expr]
    }

    public func callableTarget(for expr: ExprID) -> CallableTarget? {
        callableTargets[expr]
    }

    public func constructorDelegationTarget(for ctorSymbol: SymbolID) -> SymbolID? {
        constructorDelegationTargets[ctorSymbol]
    }

    public func constructorDelegationCallBinding(for ctorSymbol: SymbolID) -> CallBinding? {
        constructorDelegationCallBindings[ctorSymbol]
    }

    public func enumEntryConstructorBinding(for entrySymbol: SymbolID) -> CallBinding? {
        enumEntryConstructorBindings[entrySymbol]
    }

    public func bindEnumEntryInvokeReceiver(_ expression: ExprID, symbol: SymbolID) {
        enumEntryInvokeReceiverSymbols[expression] = symbol
    }

    public func enumEntryInvokeReceiverSymbol(for expression: ExprID) -> SymbolID? {
        enumEntryInvokeReceiverSymbols[expression]
    }

    public func callableValueCallBinding(for expr: ExprID) -> CallableValueCallBinding? {
        callableValueCalls[expr]
    }

    public func isCheckTargetType(for expr: ExprID) -> TypeID? {
        isCheckTargetTypes[expr]
    }

    public func castTargetType(for expr: ExprID) -> TypeID? {
        castTargetTypes[expr]
    }

    public func findAnnotationSearchType(for expr: ExprID) -> TypeID? {
        findAnnotationSearchTypes[expr]
    }

    public func catchClauseBinding(for catchBodyExpr: ExprID) -> CatchClauseBinding? {
        catchClauseBindings[catchBodyExpr]
    }

    public func captureSymbols(for expr: ExprID) -> [SymbolID] {
        captureSymbolsByExpr[expr] ?? []
    }

    public func declSymbol(for decl: DeclID) -> SymbolID? {
        declSymbols[decl]
    }

    public func isSuperCallExpr(_ expr: ExprID) -> Bool {
        superCallExprs.contains(expr)
    }

    public func isInvokeOperatorCall(_ expr: ExprID) -> Bool {
        invokeOperatorCallExprs.contains(expr)
    }

    public func bindConstExprValue(_ expr: ExprID, value: KIRExprKind) {
        constExprValues[expr] = value
    }

    public func constExprValue(for expr: ExprID) -> KIRExprKind? {
        constExprValues[expr]
    }

    public func markSamConversion(_ expr: ExprID) {
        samConversionExprs.insert(expr)
    }

    public func isSamConversion(_ expr: ExprID) -> Bool {
        samConversionExprs.contains(expr)
    }

    public func bindSamUnderlyingFunctionType(_ expr: ExprID, type: TypeID) {
        samUnderlyingFunctionTypes[expr] = type
    }

    public func bindSamInterfaceType(_ expr: ExprID, type: TypeID) {
        samInterfaceTypes[expr] = type
    }

    public func samInterfaceType(for expr: ExprID) -> TypeID? {
        samInterfaceTypes[expr]
    }

    public func samUnderlyingFunctionType(for expr: ExprID) -> TypeID? {
        samUnderlyingFunctionTypes[expr]
    }

    public func markBuilderDSLExpr(_ expr: ExprID, kind: BuilderDSLKind) {
        builderDSLExprIDs.insert(expr)
        builderDSLKinds[expr] = kind
    }

    public func builderDSLKind(for expr: ExprID) -> BuilderDSLKind? {
        builderDSLKinds[expr]
    }

    public func markScopeFunctionExpr(_ expr: ExprID, kind: ScopeFunctionKind) {
        scopeFunctionExprIDs.insert(expr)
        scopeFunctionKinds[expr] = kind
    }

    public func scopeFunctionKind(for expr: ExprID) -> ScopeFunctionKind? {
        scopeFunctionKinds[expr]
    }

    public func markCollectionHOFLambdaExpr(_ expr: ExprID) {
        collectionHOFLambdaExprIDs.insert(expr)
    }

    /// Used when a call originally speculatively marked as a native collection
    /// HOF later turns out to bind to a bundled Kotlin-source declaration
    /// instead, which expects an ordinary boxed callable value rather than the
    /// native (closureObj, it) two-argument ABI.
    public func unmarkCollectionHOFLambdaExpr(_ expr: ExprID) {
        collectionHOFLambdaExprIDs.remove(expr)
    }

    public func isCollectionHOFLambdaExpr(_ expr: ExprID) -> Bool {
        collectionHOFLambdaExprIDs.contains(expr)
    }

    public func bindFunctionValueExpectedType(_ expr: ExprID, type: TypeID) {
        functionValueExpectedTypes[expr] = type
    }

    public func functionValueExpectedType(for expr: ExprID) -> TypeID? {
        functionValueExpectedTypes[expr]
    }

    public func markDirectlyInvokedLambdaExpr(_ expr: ExprID) {
        directlyInvokedLambdaExprIDs.insert(expr)
    }

    public func isDirectlyInvokedLambdaExpr(_ expr: ExprID) -> Bool {
        directlyInvokedLambdaExprIDs.contains(expr)
    }

    public func markFQNTopLevelCallExpr(_ expr: ExprID) {
        fqnTopLevelCallExprIDs.insert(expr)
    }

    public func isFQNTopLevelCallExpr(_ expr: ExprID) -> Bool {
        fqnTopLevelCallExprIDs.contains(expr)
    }

    public func markFQNQualifiedValueExpr(_ expr: ExprID) {
        fqnQualifiedValueExprIDs.insert(expr)
    }

    public func isFQNQualifiedValueExpr(_ expr: ExprID) -> Bool {
        fqnQualifiedValueExprIDs.contains(expr)
    }

    public func markTypeQualifiedConstructorCallExpr(_ expr: ExprID) {
        typeQualifiedConstructorCallExprIDs.insert(expr)
    }

    public func isTypeQualifiedConstructorCallExpr(_ expr: ExprID) -> Bool {
        typeQualifiedConstructorCallExprIDs.contains(expr)
    }

    public func markCoroutineLauncherLambdaExpr(_ expr: ExprID) {
        coroutineLauncherLambdaExprIDs.insert(expr)
    }

    public func markRawSuspendEntryLambdaExpr(_ expr: ExprID) {
        rawSuspendEntryLambdaExprIDs.insert(expr)
    }

    public func isCoroutineLauncherLambdaExpr(_ expr: ExprID) -> Bool {
        coroutineLauncherLambdaExprIDs.contains(expr)
    }

    public func bindCoroutineScopeLambdaReceiverType(_ expr: ExprID, type: TypeID) {
        coroutineScopeLambdaReceiverTypes[expr] = type
    }

    public func markSourceDeclaredExpectedType(_ expr: ExprID) {
        sourceDeclaredExpectedTypeExprIDs.insert(expr)
    }

    public func hasSourceDeclaredExpectedType(_ expr: ExprID) -> Bool {
        sourceDeclaredExpectedTypeExprIDs.contains(expr)
    }

    public func bindNominalFunctionExpectedType(_ expr: ExprID, type: TypeID) {
        nominalFunctionExpectedTypes[expr] = type
    }

    public func markStdlibSpecialCallExpr(_ expr: ExprID, kind: StdlibSpecialCallKind) {
        stdlibSpecialCallExprIDs.insert(expr)
        stdlibSpecialCallKinds[expr] = kind
    }

    public func stdlibSpecialCallKind(for expr: ExprID) -> StdlibSpecialCallKind? {
        stdlibSpecialCallKinds[expr]
    }

    public func markImplicitReceiverMember(
        _ expr: ExprID,
        name: InternedString,
        receiverType: TypeID? = nil
    ) {
        implicitReceiverMemberNames[expr] = name
        if let receiverType {
            implicitReceiverMemberReceiverTypes[expr] = receiverType
        }
    }

    public func implicitReceiverMemberReceiverType(for expr: ExprID) -> TypeID? {
        implicitReceiverMemberReceiverTypes[expr]
    }

    public func markImplicitReceiverOuterReceiver(_ expr: ExprID, symbol: SymbolID) {
        implicitReceiverOuterReceiverSymbols[expr] = symbol
    }

    public func implicitReceiverOuterReceiver(for expr: ExprID) -> SymbolID? {
        implicitReceiverOuterReceiverSymbols[expr]
    }

    public func markImplicitExtensionReceiver(_ expr: ExprID, symbol: SymbolID) {
        implicitExtensionReceiverSymbols[expr] = symbol
    }

    public func implicitExtensionReceiver(for expr: ExprID) -> SymbolID? {
        implicitExtensionReceiverSymbols[expr]
    }

    public func markCoroutineScopeImplicitReceiverCall(_ expr: ExprID) {
        coroutineScopeImplicitReceiverCallExprs.insert(expr)
    }

    public func isCoroutineScopeImplicitReceiverCall(_ expr: ExprID) -> Bool {
        coroutineScopeImplicitReceiverCallExprs.contains(expr)
    }

    public func bindCallableRefKind(_ expr: ExprID, kind: CallableRefKind) {
        callableRefKinds[expr] = kind
    }

    public func callableRefKind(for expr: ExprID) -> CallableRefKind? {
        callableRefKinds[expr]
    }

    public func markUnboundCallableRef(_ expr: ExprID) {
        unboundCallableRefs.insert(expr)
    }

    /// Callable references can be re-inferred under a different expected
    /// function type (e.g. per-candidate overload probing), which may switch
    /// a `Type::member` reference between the unbound shape and a bound
    /// companion/extension interpretation. A bound commit must clear any
    /// unbound mark an earlier inference left behind, or KIR lowering keeps
    /// treating the reference as unbound and drops the captured receiver.
    public func unmarkUnboundCallableRef(_ expr: ExprID) {
        unboundCallableRefs.remove(expr)
    }

    public func isUnboundCallableRef(_ expr: ExprID) -> Bool {
        unboundCallableRefs.contains(expr)
    }

    public func bindPrimitiveOperatorCallableRef(_ expr: ExprID, op: BinaryOp) {
        primitiveOperatorCallableRefs[expr] = op
    }

    public func primitiveOperatorCallableRef(for expr: ExprID) -> BinaryOp? {
        primitiveOperatorCallableRefs[expr]
    }

    public func bindPrimitiveUnaryOperatorCallableRef(_ expr: ExprID, op: UnaryOp) {
        primitiveUnaryOperatorCallableRefs[expr] = op
    }

    public func primitiveUnaryOperatorCallableRef(for expr: ExprID) -> UnaryOp? {
        primitiveUnaryOperatorCallableRefs[expr]
    }

    public func bindAnyToStringCallableRef(_ expr: ExprID) {
        anyToStringCallableRefs.insert(expr)
    }

    public func isAnyToStringCallableRef(_ expr: ExprID) -> Bool {
        anyToStringCallableRefs.contains(expr)
    }
}
