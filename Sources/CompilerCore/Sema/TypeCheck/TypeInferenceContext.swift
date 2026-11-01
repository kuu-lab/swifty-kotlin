/// Shared by copied contexts so nested returns contribute to their actual target.
final class LambdaReturnInferenceScope {
    let exprID: ExprID
    let label: InternedString?
    let expectedReturnType: TypeID?
    var returnValueTypes: [ExprID: TypeID] = [:]

    init(exprID: ExprID, label: InternedString?, expectedReturnType: TypeID?) {
        self.exprID = exprID
        self.label = label
        self.expectedReturnType = expectedReturnType
    }
}

/// Shared by copied contexts so loop jumps retain the local state at their target.
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
    /// An Elvis branch call may use its peer's type to infer generic return
    /// arguments without requiring the call result to be a subtype of that type.
    var isElvisBranchExpectedTypeHint = false
    /// A direct generic call on the Elvis RHS may use the LHS's non-null type
    /// to fill type variables that its inputs did not determine.
    var elvisRhsCallResultTypeHint: TypeID?
    var elvisRhsCallResultTypeHintExpr: ExprID?
    /// A failed call may retry once using its arguments' natural types while
    /// keeping the outer result constraint in overload resolution.
    var allowsLiftedCallExpectedTypeHints = true
    /// Collection fast paths must check inputs when their result type comes
    /// from a speculative superclass hint rather than the inputs themselves.
    var validatesLiftedHintCollectionArguments = false
    /// Direct equality operands have no argument type that can infer a generic
    /// zero-argument collection factory's element type.
    var collectionFactoryInferenceRequiredForEqualityOperand: ExprID?
    /// The current call expression is in statement position and its result is
    /// discarded. This lets generic call inference apply Kotlin's Unit-coercion
    /// rules without weakening calls whose values are consumed by expressions.
    var isCallResultDiscarded = false
    /// The surrounding function or lambda body is expected to produce Unit.
    /// A discarded call may pass Unit to its lambda arguments only in this
    /// context; ordinary statements in non-Unit functions keep natural types.
    var isUnitCoercionContext = false
    /// The current expression sits on a conditionally-evaluated path within the
    /// current locals scope (the conditional tail of a `?.` chain). Effects
    /// recorded unconditionally into `locals` — such as `x as T` narrowing —
    /// must not leak to code after the conditional point, so they are
    /// suppressed while this is set. Cleared when a fresh locals scope starts
    /// (lambda bodies, `if`/`when` branches), where local narrowing cannot leak.
    var isConditionallyEvaluated = false
    /// The `isConditionallyEvaluated` value for receiver/callee spine elements
    /// of the call expression currently being entered — the flag as it was
    /// before that node raised `isConditionallyEvaluated` for its arguments.
    /// `a?.b` reads `a` even when `b` is skipped, so spine elements keep the
    /// conditionality the enclosing call node itself was evaluated under:
    /// `(x!!)?.f()` still narrows `x`, while `x?.f(y!!.v)` keeps `y!!` on the
    /// conditional path. Set at each call-expression entry; only meaningful
    /// until the expression's own `?.` raise, after which non-spine children
    /// must read `isConditionallyEvaluated` instead.
    var receiverConditionallyEvaluated = false
    /// Already-checked typed when subjects reused by synthesized is/in conditions.
    /// Keep initializer bindings intact while conditions see the declared variable type.
    var whenSubjectTypes: [ExprID: TypeID] = [:]
    /// The subject ExprID of the enclosing `when` while one of its branch
    /// conditions is being inferred. The parser reuses that exact ExprID as
    /// the operand of a synthesized `is` condition, so consumer recording on
    /// the operand must not erase the claim the subject still owes its
    /// synthetic typed local (KUU-3893).
    var whenConditionSubject: ExprID?
    var implicitReceiverType: TypeID?
    /// Receiver values in lexical order, including shadowed lambda receivers.
    var implicitReceiverStack: [(type: TypeID, symbol: SymbolID)] = []
    var builderInference: BuilderInferenceSession?
    /// Formal parameters of the surrounding call, not rigid lexical parameters.
    var callableReferenceInferenceParameters: Set<SymbolID> = []
    /// True while inferring a callable reference directly against a call
    /// parameter. Keep its source function type visible so call lowering can
    /// emit a required suspend-conversion adapter.
    var isCallableReferenceArgument = false
    var loopDepth: Int
    var loopLabelStack: [InternedString]
    /// Loop targets share jump snapshots across copied branch contexts.
    var loopFlowScopes: [LoopControlFlowInferenceScope] = []
    /// Loop scopes visible immediately before each enclosing lambda boundary.
    /// A break/continue may cross these boundaries only when every intervening
    /// lambda is an argument to an inline parameter that allows non-local jumps.
    var lambdaLoopScopes: [(exprID: ExprID, loopDepth: Int, labels: [InternedString])] = []
    /// A label written on a lambda that is immediately consumed by a postfix
    /// suffix (`foo@{ ... }()`) binds to the postfix expression in Kotlin, so it
    /// is tracked here as visible but not function-denoting.
    var lambdaLabelStack: [(label: InternedString, denotesFunction: Bool)]
    var lambdaReturnScopes: [LambdaReturnInferenceScope] = []
    /// Number of lambda bodies enclosing the expression currently being inferred.
    /// An unlabeled return inside such a body is a non-local return and is checked
    /// against the surrounding named function's return type rather than the
    /// lambda's predicate/result type.
    var lambdaDepth: Int = 0
    /// Independent of return targets: initializers cannot inherit suspension.
    var suspensionContext = SuspensionContext()
    /// Return type of the nearest named function body. This remains unchanged
    /// while entering lambda literals so non-local return values are checked
    /// against the actual return target.
    var enclosingFunctionReturnType: TypeID?
    var enclosingFunctionSymbol: SymbolID?
    /// Whether the return target — the nearest named function or accessor,
    /// which an unlabeled `return` and `return@name` bind to — has an
    /// `= expression` body *without* an explicitly declared return type.
    /// Kotlin rejects `return` in that position (`fun f() = return`, including
    /// `return` inside `if`/`when`/`try` branches of the body), reported as
    /// KSWIFTK-SEMA-0311; kotlinc only warns when the return crosses an
    /// inline-lambda boundary, so the diagnostic additionally requires
    /// `lambdaDepth == 0` at the return site. Each nested named function,
    /// accessor, constructor, or init block re-derives it for its own target.
    var enclosingFunctionProhibitsExpressionBodyReturn: Bool = false
    /// Init blocks are not function bodies, so a bare return cannot target the
    /// function whose declaration lexically contains a local class.
    var returnTargetIsInitBlock: Bool = false
    /// Unit getters return a value through their reference ABI; ordinary
    /// Unit functions discard their result.
    var isPropertyGetterReturn: Bool {
        guard let function = enclosingFunctionSymbol else { return false }
        if SyntheticSymbolScheme.decodedPropertyAccessor(function)?.kind == .getter { return true }
        guard let property = sema.symbols.parentSymbol(for: function) else { return false }
        return sema.symbols.extensionPropertyGetterAccessor(for: property) == function
    }
    var enclosingLambdaExprIDs: [ExprID] = []
    /// When set, the specified block expression exports its local bindings to
    /// the outer locals map. Used for do-while body-to-condition visibility.
    var exportBlockLocalsForExpr: ExprID?
    var flowState: DataFlowState
    let currentFileID: FileID
    var currentDeclSymbol: SymbolID?
    /// The direct super receiver synthesized for enum-entry member bodies.
    /// Entry overrides have the enum instance as `this`, while their implicit
    /// `super` receiver is the enum class itself.
    var enumEntrySuperContext: (ownerSymbol: SymbolID, type: TypeID)?
    /// When set, the symbol of the property/val whose initializer expression is
    /// currently being type-checked. A bare name reference that resolves back to
    /// this same symbol is a self-referential read before the property has ever
    /// been initialized (DEBT-SEMA-003), e.g. `val cyclic: List<*> = listOf(cyclic)`.
    /// Scoped to just the initializer expression — not carried into getter/setter
    /// bodies, where reading the property's own name is a normal (if recursive)
    /// property access rather than a use-before-init.
    var initializingPropertySymbol: SymbolID?
    /// True only while checking the property initializer itself. Nested named
    /// functions replace `currentDeclSymbol` and retain their own return target.
    var isInPropertyInitializer: Bool {
        initializingPropertySymbol != nil && initializingPropertySymbol == currentDeclSymbol
    }
    var enclosingClassSymbol: SymbolID?
    let visibilityChecker: VisibilityChecker
    /// `symbol` is the enclosing function's receiver parameter when the entry's
    /// runtime value is reachable through capture (e.g. the enclosing `this`
    /// captured into an object literal's fields); `nil` entries participate in
    /// `this@Label` typing only.
    var outerReceiverTypes: [(label: InternedString, type: TypeID, symbol: SymbolID?)]
    /// Context receiver types available to `contextOf<A>()` in the current lambda body.
    var contextReceiverTypes: [TypeID] = []
    /// Context receiver types each enclosing lambda literal introduced,
    /// keyed by the lambda's expression ID. Kotlin resolves an implicit
    /// context argument per enclosing-lambda level: the receivers a deeper
    /// `context(...) { ... }` block supplies are nearer than receivers from
    /// scopes enclosing that lambda, while `contextReceiverTypes` alone
    /// cannot order them against `implicitReceiverStack` entries.
    var lambdaContextReceiverTypes: [ExprID: [TypeID]] = [:]
    /// Supertype constructor arguments run before `this` exists, so the
    /// enclosing class must not act as an implicit receiver there (it still
    /// drives visibility checks).
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
    /// When true, the current scope is a builder DSL lambda body.
    /// Used to scope `append`/`add`/`put` fallback resolution.
    var isBuilderLambdaScope: Bool = false
    /// When true, platform-type warnings for `return` expressions should be suppressed.
    /// Set for functions whose return type is inferred (not user-declared).
    var suppressPlatformReturnWarning: Bool = false
    /// The specific builder kind for this scope.
    /// Used to restrict member function resolution to the correct kind.
    var builderKind: BuilderDSLKind?
    /// When true, the current scope is a `flow { ... }` builder lambda body.
    /// Used to resolve unqualified `emit(...)` fallback.
    var isFlowBuilderLambdaScope: Bool = false
    var flowBuilderInference: FlowBuilderInferenceSession?
    /// When true, the current scope is a coroutine builder lambda body.
    /// The lambda keeps the existing no-receiver ABI, but unqualified
    /// `CoroutineScope` extension calls still resolve against the ambient scope.
    var isCoroutineBuilderLambdaScope: Bool = false
    /// When true, assigning to an immutable member property is treated as
    /// initialization rather than reassignment. Used for `init {}` and
    /// constructor bodies.
    var allowsValPropertyInitialization: Bool = false
    let semaCacheContext: SemaCacheContext?
    /// Mirrors Kotlin's `-Xnew-inference`.
    let useNewInference: Bool
    /// Mirrors Kotlin's `-Xunrestricted-builder-inference`.
    let useUnrestrictedBuilderInference: Bool
    /// Mirrors Kotlin's `ProperTypeInferenceConstraintsProcessing`.
    let useProperTypeInferenceConstraintsProcessing: Bool
    /// Marker annotations accepted through compiler-wide `-opt-in=<fqName>`.
    let globalOptInMarkerNames: [String]
    /// Opt-ins granted only inside the current accessor body.
    var accessorOptInMarkers: Set<SymbolID> = []
    /// Only the outer annotation constructor can reuse earlier application checks.
    /// Nested expressions and constructor-specific markers still need checking.
    var annotationOptInValidation: (owner: SymbolID, range: SourceRange?, markers: Set<SymbolID>)?
    /// The annotation class already resolved from declaration metadata for the
    /// synthetic constructor call that replays one annotation application.
    var annotationConstructionTarget: (call: ExprID, annotationClass: SymbolID)?
    /// Opt-ins retained when local functions replace the current declaration.
    var inheritedOptInMarkers: Set<SymbolID> = []
    /// When a nested lambda introduces a receiver whose class carries the same
    /// DslMarker annotation as an outer receiver, the outer receiver is hidden
    /// from implicit resolution.
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

    /// Member-style fallback resolution occasionally needs the file's import
    /// provenance to disambiguate source-backed aliases that expand to the same
    /// nominal runtime type. Keep that lookup on the context so callers do not
    /// duplicate the AST scan.
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
        // Lambda-local loops start a fresh scope. Candidate jumps to enclosing
        // loops are recorded and checked after overload resolution determines
        // whether each lambda boundary is inline-permitted.
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

    /// The lambda boundaries a non-local loop jump would cross, or nil when no
    /// enclosing loop matches the requested target.
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

    /// The function-denoting status of the nearest enclosing label named
    /// `label`, or nil when no enclosing label matches. The nearest match wins:
    /// a non-function label (`foo@{ ... }()`) shadows outer same-named labels
    /// without becoming a valid `return@` target itself.
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

    /// Demotes the implicit receiver whose class is `classSymbol` below its
    /// companion block in member lookup — see
    /// `companionDemotedReceiverSymbols`.
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

    /// Whether `label` matches an enclosing label that does not denote a
    /// function — used to phrase `return@label` diagnostics like kotlinc's
    /// "target label does not denote a function".
    func hasNonFunctionLambdaLabel(_ label: InternedString) -> Bool {
        lambdaLabelDenotesFunction(label) == false
    }

    /// DFA already narrows the immutable `this` local in branch and surviving
    /// guard paths. Keep bare-name lookup on that same receiver value; outer
    /// tower entries and ordinary user locals (including escaped `this`) stay
    /// unchanged. The local receiver type is the established stable flow result.
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

    /// Non-inner nested classes discard enclosing instances, but retain enclosing singleton objects.
    func nestedClassContext(isInner: Bool) -> TypeInferenceContext {
        guard !isInner else { return self }
        return copying(outerReceiverTypes: singletonObjectOuterReceivers)
    }

    /// Singleton object receivers remain accessible from nested class headers,
    /// even when the nested class has no enclosing instance of its own.
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

    /// The receiver parameter symbol attached to a `this@Label` entry, when the
    /// enclosing `this` is materializable through capture. See
    /// `outerReceiverTypes`.
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

    /// Same tower as `implicitReceiverMemberLookupTypes()` but keeps each
    /// entry's receiver symbol when one exists: the symbol is how capture
    /// analysis and KIR lowering materialize that exact receiver value
    /// (e.g. a member extension's receiver parameter captured into a lambda).
    /// The innermost active receiver has no symbol at this layer — KIR maps it
    /// to the active implicit receiver expression instead.
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

    /// Ordered implicit receiver types for unqualified member lookup, innermost
    /// first: the active implicit receiver, then enclosing lambda receivers,
    /// then labeled `this@Label` receivers innermost-out, then the enclosing
    /// class. A member extension body's `this` is its extension receiver, but
    /// Kotlin still resolves the dispatch owner's members — including inherited
    /// ones — through the same implicit receiver tower, so callers must probe
    /// every entry rather than only `implicitReceiverType`.
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

    /// Returns the enclosing class's companion when it inherits the candidate's
    /// declaring class. Class bodies expose these members through companion
    /// shorthand, so calls must use that singleton as their dispatch receiver.
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
        protectedAccessReceiverType: TypeID? = nil
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
            guard !isHiddenByDeprecationOrVersionAnnotation(candidate, symbols: sema.symbols)
                    || !hasNonHiddenCandidate
            else { continue }
            let accessibleInEnclosingClass = visibilityChecker.isAccessible(
                symbol, fromFile: currentFileID, enclosingClass: enclosingClassSymbol
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
                    symbol, fromFile: currentFileID, enclosingClass: companion
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

    /// `expect`/`actual` pairs are intentionally allowed to coexist in the same
    /// scope (KSwiftK has no separate common/platform module compilation), so a
    /// linked `expect` declaration is filtered out here once its `actual` is
    /// known. Without this, every expression-level reference to the pair would
    /// see two candidates with an identical shape: call resolution reports a
    /// false ambiguous-overload, and name resolution binds arbitrarily to
    /// whichever declaration happens to come first.
    func cachedScopeLookup(_ name: InternedString) -> [SymbolID] {
        let results: [SymbolID] = if let cache = semaCacheContext {
            cache.lookupInScope(name, scope: scope)
        } else {
            scope.lookup(name)
        }
        return results.filter {
            !isExpectDeclarationSupersededByActual($0)
                && !isImportedCallableShadowedBySource($0)
        }
    }

    /// Resolve within a candidate namespace so bindings of another kind in an
    /// inner scope do not hide the matching declaration in an outer scope.
    func cachedScopeLookup(
        _ name: InternedString,
        matching predicate: (SymbolID) -> Bool
    ) -> [SymbolID] {
        scope.lookup(name, matching: predicate).filter {
            !isExpectDeclarationSupersededByActual($0)
                && !isImportedCallableShadowedBySource($0)
        }
    }

    /// Expression names cannot inherit nested classifiers from an
    /// interface, but an outer declaration or explicit import can still bind
    /// the same name. Return the rejected symbols for the global fallback too.
    func valueScopeLookup(_ name: InternedString) -> (matches: [SymbolID], inheritedInterfaces: Set<SymbolID>) {
        valueScopeLookup(name) { symbolID in
            guard let symbol = cachedSymbol(symbolID) else { return false }
            return symbol.kind != .function && symbol.kind != .constructor
        }
    }

    /// Variant of `valueScopeLookup` that applies `predicate` to each
    /// candidate so the caller can require a specific binding kind (e.g. only
    /// declarations that denote a value). Interface-inherited classifiers are
    /// still rejected and collected regardless of the predicate.
    func valueScopeLookup(
        _ name: InternedString,
        matching predicate: (SymbolID) -> Bool
    ) -> (matches: [SymbolID], inheritedInterfaces: Set<SymbolID>) {
        var inheritedInterfaces: Set<SymbolID> = []
        var current: Scope? = scope
        while let currentScope = current as? BaseScope {
            let candidates = currentScope.candidates(for: name).filter { symbolID in
                guard let symbol = cachedSymbol(symbolID),
                      !isExpectDeclarationSupersededByActual(symbolID),
                      !isImportedCallableShadowedBySource(symbolID)
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
            if !candidates.isEmpty { return (candidates, inheritedInterfaces) }
            current = currentScope.parent
        }
        return ([], inheritedInterfaces)
    }

    /// A source callable shadows an imported callable at the same FQ name when
    /// their erased signatures match — e.g. upstream `kotlinx.io` sources
    /// vendored over the bundled stdlib copy. Keeping both as call candidates
    /// merges two declarations that must behave as one and can leak
    /// library-side member types into lambda expected types, so the imported
    /// twin is dropped from scope results here.
    func isImportedCallableShadowedBySource(_ id: SymbolID) -> Bool {
        guard let symbol = cachedSymbol(id),
              symbol.flags.contains(.importedLibrary),
              symbol.kind == .function || symbol.kind == .constructor,
              let signature = sema.symbols.functionSignature(for: id)
        else {
            return false
        }
        return sema.symbols.lookupAll(fqName: symbol.fqName).contains { other in
            guard other != id,
                  let otherSymbol = cachedSymbol(other),
                  !otherSymbol.flags.contains(.importedLibrary),
                  otherSymbol.kind == symbol.kind,
                  let otherSignature = sema.symbols.functionSignature(for: other)
            else {
                return false
            }
            return hasSameSourceErasedSignature(signature, otherSignature)
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

    /// Erased type equality across the source/imported boundary: nominal types
    /// compare by FQ name (the shadowing pair has different symbols), type
    /// parameters by position within each signature.
    private func erasedTypeEqual(
        _ lhs: TypeID,
        in lhsSignature: FunctionSignature,
        _ rhs: TypeID,
        in rhsSignature: FunctionSignature
    ) -> Bool {
        switch (sema.types.kind(of: sema.types.makeNonNullable(lhs)),
                sema.types.kind(of: sema.types.makeNonNullable(rhs))) {
        case let (.classType(lhsType), .classType(rhsType)):
            return sema.symbols.symbol(lhsType.classSymbol)?.fqName
                == sema.symbols.symbol(rhsType.classSymbol)?.fqName
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

    /// A type carries a DslMarker if it is a class/interface annotated with an
    /// annotation class that is itself annotated with `@DslMarker`.
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

    /// A member symbol is blocked when its owner class/interface carries a
    /// DslMarker annotation that also applies to the current implicit receiver,
    /// and the owner is NOT the current implicit receiver itself.
    func isCandidateBlockedByDslMarker(_ candidateID: SymbolID) -> Bool {
        guard !activeDslMarkerAnnotations.isEmpty else {
            return false
        }
        guard let parentID = sema.symbols.parentSymbol(for: candidateID) else {
            return false
        }
        // The parent must be a class, interface, or object to carry DslMarker.
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

    /// Implicit receiver tower entries hidden by the Kotlin DSL marker rule:
    /// walking innermost to outermost, an entry is hidden when a strictly
    /// nearer entry carries at least one DslMarker annotation it also
    /// carries. `implicitReceiverMemberLookupEntries` deduplicates entries
    /// by `TypeID`, so a type identifies exactly one tower position.
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
