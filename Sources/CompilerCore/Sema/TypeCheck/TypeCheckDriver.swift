struct LocalBindings: ExpressibleByDictionaryLiteral, Sequence {
    typealias Value = (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)
    private var bindings: [InternedString: Value]
    var memberFlow: [DataFlowReference: VariableFlowState] = [:]

    init(dictionaryLiteral elements: (InternedString, Value)...) {
        bindings = Dictionary(uniqueKeysWithValues: elements)
    }

    subscript(name: InternedString) -> Value? {
        get { bindings[name] }
        set { bindings[name] = newValue }
    }

    var values: Dictionary<InternedString, Value>.Values { bindings.values }
    var isEmpty: Bool { bindings.isEmpty }

    func makeIterator() -> Dictionary<InternedString, Value>.Iterator {
        bindings.makeIterator()
    }

    func merging(_ other: LocalBindings, uniquingKeysWith combine: (Value, Value) throws -> Value) rethrows -> LocalBindings {
        var merged = self
        merged.bindings = try bindings.merging(other.bindings, uniquingKeysWith: combine)
        return merged
    }

    mutating func invalidateMembers(root: SymbolID) {
        memberFlow = memberFlow.filter { $0.key.root != root }
    }
}

/// Dispatch hub for type checking. Replaces the monolithic extension-based splitting
/// of `TypeCheckSemaPhase` with independent delegate classes.
///
/// Each delegate holds an `unowned` back-reference to this driver so that mutually
/// recursive calls (e.g. `inferExpr` → `inferCallExpr` → `inferExpr`) can be
/// dispatched through the driver rather than sharing a single fat class instance.
final class TypeCheckDriver {
    /// Lexical boundaries retained until overload and lambda inference finish.
    var callSuspensionContexts: [ExprID: SuspensionContext] = [:]
    /// Properties whose types were inferred in a safe module pre-pass so earlier
    /// files can use them without running the property checker a second time.
    var precheckedPropertyDecls: Set<DeclID> = []

    let ast: ASTModule
    let sema: SemaModule
    let semaCtx: SemaModule
    let sourceManager: SourceManager?
    let solver: ConstraintSolver
    let resolver: OverloadResolver
    let dataFlow: DataFlowAnalyzer
    let interner: StringInterner
    let diagnostics: DiagnosticEngine
    /// Sema cache context for hot-path caching.  `nil` when caching is disabled.
    let semaCacheContext: SemaCacheContext?
    let useNewInference: Bool
    let useUnrestrictedBuilderInference: Bool
    let useProperTypeInferenceConstraintsProcessing: Bool
    let globalOptInMarkerNames: [String]

    // Delegates (lazy to break initialization ordering; each holds unowned back-reference)
    private(set) lazy var exprChecker = ExprTypeChecker(driver: self)
    private(set) lazy var callChecker = CallTypeChecker(driver: self)
    private(set) lazy var controlFlowChecker = ControlFlowTypeChecker(driver: self)
    private(set) lazy var localDeclChecker = LocalDeclTypeChecker(driver: self)
    private(set) lazy var declChecker = DeclTypeChecker(driver: self)

    /// Cached `BuiltinTypeNames` instance to avoid repeated allocations on hot paths.
    private(set) lazy var builtinTypeNamesCache = BuiltinTypeNames(interner: interner)

    // Stateless utilities (no back-reference needed)
    let helpers = TypeCheckHelpers()
    let scopeBuilder = TypeCheckScopeBuilder()
    let captureAnalyzer = CaptureAnalyzer()

    init(
        ast: ASTModule,
        sema: SemaModule,
        semaCtx: SemaModule,
        sourceManager: SourceManager? = nil,
        solver: ConstraintSolver,
        resolver: OverloadResolver,
        dataFlow: DataFlowAnalyzer,
        interner: StringInterner,
        diagnostics: DiagnosticEngine,
        semaCacheContext: SemaCacheContext? = nil,
        useNewInference: Bool = false,
        useUnrestrictedBuilderInference: Bool = false,
        useProperTypeInferenceConstraintsProcessing: Bool = false,
        globalOptInMarkerNames: [String] = []
    ) {
        self.ast = ast
        self.sema = sema
        self.semaCtx = semaCtx
        self.sourceManager = sourceManager
        self.solver = solver
        self.resolver = resolver
        self.dataFlow = dataFlow
        self.interner = interner
        self.diagnostics = diagnostics
        self.semaCacheContext = semaCacheContext
        self.useNewInference = useNewInference
        self.useUnrestrictedBuilderInference = useUnrestrictedBuilderInference
        self.useProperTypeInferenceConstraintsProcessing = useProperTypeInferenceConstraintsProcessing
        self.globalOptInMarkerNames = globalOptInMarkerNames
    }

    // MARK: - Main Recursive Dispatch Entry Point

    func inferExpr(
        _ id: ExprID,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID? = nil,
        isStatementContext: Bool = false
    ) -> TypeID {
        if let subjectType = ctx.whenSubjectTypes[id] {
            return subjectType
        }
        let type = exprChecker.inferExpr(id, ctx: ctx, locals: &locals, expectedType: expectedType, isStatementContext: isStatementContext)
        if !suspendingCallNames(for: id).isEmpty {
            callSuspensionContexts[id] = ctx.suspensionContext
        }
        checkInlineCallVisibility(id, ctx: ctx)
        return type
    }

    private func checkInlineCallVisibility(_ id: ExprID, ctx: TypeInferenceContext) {
        guard let callerID = ctx.currentDeclSymbol,
              let caller = sema.symbols.symbol(callerID),
              caller.flags.contains(.inlineFunction),
              ctx.visibilityChecker.isPublicAPI(caller),
              let binding = sema.bindings.callBinding(for: id),
              let callee = sema.symbols.symbol(binding.chosenCallee),
              !ctx.visibilityChecker.isPublicAPI(callee, allowProtected: false),
              let range = ast.arena.exprRange(id),
              !diagnostics.diagnostics.contains(where: {
                  $0.code == "KSWIFTK-SEMA-0045" && $0.primaryRange == range
              })
        else { return }
        diagnostics.error(
            "KSWIFTK-SEMA-0045",
            "Public-API inline function cannot access non-public-API declaration '\(interner.resolve(callee.name))'.",
            range: range
        )
    }

    // MARK: - Module-Level Type Checking

    func typeCheckModule(fileScopes: [Int32: FileScope], files: [ASTFile]) {
        let invisibleAccessFiles = Set(files.compactMap { file -> Int32? in
            file.annotations.contains { annotation in
                guard KnownCompilerAnnotation.suppress.matches(annotation.name) else {
                    return false
                }
                return annotation.arguments.contains { argument in
                    let code = argument.filter { $0 != "\"" && $0 != "'" }
                    return code == "INVISIBLE_MEMBER" || code == "INVISIBLE_REFERENCE"
                }
            } ? file.fileID.rawValue : nil
        })
        let checker = VisibilityChecker(
            symbols: sema.symbols,
            sourceManager: sourceManager,
            invisibleAccessFiles: invisibleAccessFiles
        )

        func inferenceContext(for file: ASTFile) -> TypeInferenceContext? {
            guard let fileScope = fileScopes[file.fileID.rawValue] else {
                return nil
            }
            return TypeInferenceContext(
                ast: ast, sema: sema, semaCtx: semaCtx,
                resolver: resolver, dataFlow: dataFlow,
                interner: interner, scope: fileScope,
                implicitReceiverType: nil,
                loopDepth: 0,
                loopLabelStack: [],
                lambdaLabelStack: [],
                exportBlockLocalsForExpr: nil,
                flowState: DataFlowState(),
                currentFileID: file.fileID,
                currentDeclSymbol: nil,
                enclosingClassSymbol: nil,
                visibilityChecker: checker,
                outerReceiverTypes: [],
                semaCacheContext: semaCacheContext,
                useNewInference: useNewInference,
                useUnrestrictedBuilderInference: useUnrestrictedBuilderInference,
                useProperTypeInferenceConstraintsProcessing: useProperTypeInferenceConstraintsProcessing,
                globalOptInMarkerNames: globalOptInMarkerNames
            )
        }

        func hasHeaderResolvedConstructorInitializer(_ property: PropertyDecl, in file: ASTFile) -> Bool {
            guard property.type == nil,
                  let initializer = property.initializer,
                  let initializerExpr = ast.arena.expr(initializer),
                  case let .call(calleeID, _, _, _) = initializerExpr,
                  let calleeExpr = ast.arena.expr(calleeID),
                  case let .nameRef(name, _) = calleeExpr,
                  let symbolID = sema.symbols.lookup(fqName: file.packageFQName + [name]),
                  let symbol = sema.symbols.symbol(symbolID)
            else {
                return false
            }
            return symbol.kind == .class || symbol.kind == .enumClass
        }

        // Explicit contracts are declaration metadata. Earlier callers must
        // see them before a later function body happens to be type checked.
        for file in files {
            guard let inferCtx = inferenceContext(for: file) else { continue }
            for declaration in file.topLevelDecls {
                guard case let .funDecl(function)? = ast.arena.decl(declaration),
                      let symbol = sema.bindings.declSymbols[declaration]
                else { continue }
                declChecker.precollectContractEffects(function: function, symbol: symbol, ctx: inferCtx)
            }
        }

        // A direct constructor call has a type fixed by its collected header.
        // Infer those properties before earlier files can observe the
        // nullable-Any placeholder; pure inferred expressions are resolved in
        // dependency order below.
        for file in files {
            guard let inferCtx = inferenceContext(for: file) else { continue }
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case let .propertyDecl(property) = decl,
                      hasHeaderResolvedConstructorInitializer(property, in: file),
                      let symbol = sema.bindings.declSymbols[declID]
                else {
                    continue
                }
                declChecker.typeCheckBoundPropertyDecl(
                    property,
                    declID: declID,
                    symbol: symbol,
                    ctx: inferCtx.with(currentDeclSymbol: symbol),
                    solver: solver,
                    diagnostics: diagnostics
                )
                precheckedPropertyDecls.insert(declID)
            }
        }

        // Revisit property initializers until their inferred property
        // dependencies have types. Calls are eligible only when every
        // candidate has a concrete declared return type; arbitrary control flow,
        // unresolved references, inferred-return calls and cycles stay on the
        // source-order pass.
        var didPrecheckProperty: Bool
        repeat {
            didPrecheckProperty = false
            for file in files {
                guard let inferCtx = inferenceContext(for: file) else { continue }
                for declID in file.topLevelDecls {
                    guard !precheckedPropertyDecls.contains(declID),
                          let decl = ast.arena.decl(declID),
                          case let .propertyDecl(property) = decl,
                          declChecker.canSafelyPrecheckInferredProperty(property, in: inferCtx),
                          let symbol = sema.bindings.declSymbols[declID]
                    else {
                        continue
                    }
                    declChecker.typeCheckBoundPropertyDecl(
                        property,
                        declID: declID,
                        symbol: symbol,
                        ctx: inferCtx.with(currentDeclSymbol: symbol),
                        solver: solver,
                        diagnostics: diagnostics
                    )
                    precheckedPropertyDecls.insert(declID)
                    didPrecheckProperty = true
                }
            }
        } while didPrecheckProperty

        // Resolve simple inferred member properties in later classes before an
        // earlier file's function body observes their header placeholders.
        // Each class helper repeats until its inferred member dependencies are
        // concrete or the remaining expressions are outside the safe subset.
        for file in files {
            guard let inferCtx = inferenceContext(for: file) else { continue }
            for declID in file.topLevelDecls {
                guard case let .classDecl(classDecl)? = ast.arena.decl(declID),
                      let symbol = sema.bindings.declSymbols[declID]
                else {
                    continue
                }
                declChecker.precheckIndependentClassMemberProperties(
                    classDecl,
                    symbol: symbol,
                    ctx: inferCtx,
                    solver: solver,
                    diagnostics: diagnostics
                )
            }
        }

        for file in files {
            guard let inferCtx = inferenceContext(for: file) else { continue }
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      let declSymbol = sema.bindings.declSymbols[declID]
                else {
                    continue
                }
                if precheckedPropertyDecls.contains(declID) {
                    continue
                }
                switch decl {
                case let .funDecl(function):
                    declChecker.typeCheckFunctionDecl(
                        function,
                        symbol: declSymbol,
                        ctx: inferCtx.with(currentDeclSymbol: declSymbol),
                        solver: solver,
                        diagnostics: diagnostics
                    )

                case let .classDecl(classDecl):
                    declChecker.typeCheckClassDecl(
                        classDecl,
                        symbol: declSymbol,
                        ctx: inferCtx.with(currentDeclSymbol: declSymbol),
                        solver: solver,
                        diagnostics: diagnostics
                    )

                case let .interfaceDecl(interfaceDecl):
                    declChecker.typeCheckInterfaceDecl(
                        interfaceDecl,
                        symbol: declSymbol,
                        ctx: inferCtx.with(currentDeclSymbol: declSymbol),
                        solver: solver,
                        diagnostics: diagnostics
                    )

                case let .propertyDecl(property):
                    declChecker.typeCheckBoundPropertyDecl(
                        property,
                        declID: declID,
                        symbol: declSymbol,
                        ctx: inferCtx.with(currentDeclSymbol: declSymbol),
                        solver: solver,
                        diagnostics: diagnostics
                    )

                case let .objectDecl(objectDecl):
                    declChecker.typeCheckObjectDecl(
                        objectDecl,
                        symbol: declSymbol,
                        ctx: inferCtx.with(currentDeclSymbol: declSymbol),
                        solver: solver,
                        diagnostics: diagnostics
                    )

                case .typeAliasDecl, .enumEntryDecl:
                    continue
                }
            }
        }
    }

    // MARK: - Shared Utilities

    func emitSubtypeConstraint(
        left: TypeID,
        right: TypeID,
        range: SourceRange?,
        solver: ConstraintSolver,
        sema: SemaModule,
        diagnostics: DiagnosticEngine,
        secondaryRanges: [SourceRange] = [],
        suppressPlatformWarning: Bool = false
    ) {
        let solution = solver.solve(
            vars: [],
            constraints: [
                Constraint(
                    kind: .subtype,
                    left: left,
                    right: right,
                    blameRange: range
                ),
            ],
            typeSystem: sema.types
        )
        if !solution.isSuccess, let failure = solution.failure {
            diagnostics.emit(withExpectedTypeOrigin(
                failure,
                expectedType: right,
                extraRanges: secondaryRanges,
                primaryRange: range,
                sema: sema
            ))
        } else if !suppressPlatformWarning,
                  let warningRange = range,
                  sema.types.nullability(of: left) == .platformType,
                  sema.types.nullability(of: right) == .nonNull
        {
            diagnostics.warning(
                "KSWIFTK-SEMA-PLATFORM",
                "Expression of platform type is used as non-null without a null check. " +
                    "This may cause a NullPointerException at runtime.",
                range: warningRange
            )
        }
    }

    /// ARCH-031: attach where the expected type comes from as secondary ranges
    /// on a failed subtype constraint — the expected type's own declaration
    /// site plus any caller-provided ranges (e.g. the enclosing function whose
    /// signature declares the expected return type).
    private func withExpectedTypeOrigin(
        _ failure: Diagnostic,
        expectedType: TypeID,
        extraRanges: [SourceRange],
        primaryRange: SourceRange?,
        sema: SemaModule
    ) -> Diagnostic {
        var secondary: [SourceRange] = []
        for candidate in extraRanges + expectedTypeOriginRanges(of: expectedType, sema: sema) {
            if candidate == primaryRange || secondary.contains(candidate) {
                continue
            }
            secondary.append(candidate)
        }
        guard !secondary.isEmpty else {
            return failure
        }
        return Diagnostic(
            severity: failure.severity,
            code: failure.code,
            message: failure.message,
            primaryRange: failure.primaryRange,
            secondaryRanges: secondary,
            codeActions: failure.codeActions
        )
    }

    /// Declaration site of the expected type itself (a nominal class or a type
    /// parameter declared in source). Returns empty for primitive, function,
    /// or otherwise non-declared types.
    private func expectedTypeOriginRanges(of type: TypeID, sema: SemaModule) -> [SourceRange] {
        let symbol: SymbolID? = switch sema.types.kind(of: type) {
        case let .classType(classType):
            classType.classSymbol
        case let .typeParam(typeParam):
            typeParam.symbol
        default:
            nil
        }
        guard let symbol, let site = sema.symbols.symbol(symbol)?.declSite else {
            return []
        }
        return [site]
    }
}
