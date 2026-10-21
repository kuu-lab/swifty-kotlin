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

/// Replaces the monolithic extension-based splitting of `TypeCheckSemaPhase` with
/// independent delegate classes.
///
/// Each delegate holds an `unowned` back-reference to this driver so that mutually
/// recursive calls (e.g. `inferExpr` → `inferCallExpr` → `inferExpr`) can be
/// dispatched through the driver rather than sharing a single fat class instance.
final class TypeCheckDriver {
    var isCheckingAnnotationConstruction = false
    /// Lexical boundaries retained until overload and lambda inference finish.
    var callSuspensionContexts: [ExprID: SuspensionContext] = [:]
    /// Properties whose types were inferred in a safe module pre-pass so earlier
    /// files can use them without running the property checker a second time.
    var precheckedPropertyDecls: Set<DeclID> = []
    /// Object headers published for forward references, with bodies still unchecked.
    var predeclaredObjectLiteralDecls: Set<DeclID> = []
    var inferredReturnFunctions: [SymbolID: (function: FunDecl, context: TypeInferenceContext)] = [:]
    var checkingInferredReturnFunctions: Set<SymbolID> = []
    var checkedInferredReturnFunctions: Set<SymbolID> = []
    var inferredPropertyDeclarations: [SymbolID: (declaration: DeclID, property: PropertyDecl, context: TypeInferenceContext)] = [:]
    var checkingInferredProperties: Set<SymbolID> = []
    var pendingPropertyTypes: Set<SymbolID> = []
    var deferredInferredReturnFunctions: Set<SymbolID> = []
    var deferredInferredProperties: Set<SymbolID> = []

    let ast: ASTModule
    let sema: SemaModule
    let compilationContext: CompilationContext?
    let sourceManager: SourceManager?
    let solver: ConstraintSolver
    let resolver: OverloadResolver
    let dataFlow: DataFlowAnalyzer
    let interner: StringInterner
    let diagnostics: DiagnosticEngine
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

    private(set) lazy var builtinTypeNamesCache = BuiltinTypeNames(interner: interner)

    // Stateless utilities (no back-reference needed)
    let helpers = TypeCheckHelpers()
    let scopeBuilder = TypeCheckScopeBuilder()
    let captureAnalyzer = CaptureAnalyzer()

    init(
        ast: ASTModule,
        sema: SemaModule,
        compilationContext: CompilationContext? = nil,
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
        self.compilationContext = compilationContext
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
        var expressionContext = ctx
        if expressionContext.elvisRhsCallResultTypeHintExpr != id {
            expressionContext.elvisRhsCallResultTypeHint = nil
            expressionContext.elvisRhsCallResultTypeHintExpr = nil
        }
        let ctx = expressionContext.syncingImplicitReceiver(from: locals)
        let type = exprChecker.inferExpr(id, ctx: ctx, locals: &locals, expectedType: expectedType, isStatementContext: isStatementContext)
        // JVM Unit locals keep the Java value, while Unit returns discard it.
        // Argument checks are recorded separately after callable resolution.
        if let expectedType, type != sema.types.unitType,
           !(sema.types.kind(of: type) == .platformUnit && expectedType == sema.types.unitType)
        {
            recordPlatformNullAssertion(id, sourceType: type, targetType: expectedType)
        }
        notePendingDeclarationDependency(at: id)
        if let callee = sema.bindings.callBinding(for: id)?.chosenCallee {
            diagnoseRecursiveInferredReturnType(for: callee)
        }
        if !suspendingCallNames(for: id).isEmpty {
            callSuspensionContexts[id] = ctx.suspensionContext
        }
        checkInlineCallVisibility(id, ctx: ctx)
        return type
    }

    /// Unbounded T can contain null even though its type-parameter node is
    /// spelled non-null. Only concrete non-null targets or non-null bounds
    /// need an assertion when accepting a flexible Java return.
    func recordPlatformNullAssertion(
        _ id: ExprID, sourceType: TypeID, targetType: TypeID, declaredParameterType: TypeID? = nil
    ) {
        // A Unit local may hold null after assignment from Unit!. Keep the
        // non-null argument check even after its declared type becomes Unit.
        guard sema.types.nullability(of: sourceType) == .platformType
            || sourceType == sema.types.unitType else { return }
        var visited: Set<SymbolID> = []
        func requiresNonNull(_ type: TypeID) -> Bool {
            guard sema.types.nullability(of: type) == .nonNull else { return false }
            if case let .typeParam(parameter) = sema.types.kind(of: type) {
                guard visited.insert(parameter.symbol).inserted else { return false }
                if let capture = parameter.capture { return requiresNonNull(capture.upper) }
                return sema.symbols.typeParameterUpperBounds(for: parameter.symbol).contains(where: requiresNonNull)
            }
            return sema.types.isDefinitelyNonNull(type)
        }
        // Erased generic parameters use their declaration bounds, even when
        // inference substitutes a concrete Unit that may still contain null.
        if requiresNonNull(declaredParameterType ?? targetType), sema.types.isSubtype(sourceType, targetType) {
            sema.bindings.bindPlatformNullAssertion(id, targetType: targetType)
        }
    }

    private func checkInlineCallVisibility(_ id: ExprID, ctx: TypeInferenceContext) {
        guard !isCheckingAnnotationConstruction,
              let callerID = ctx.currentDeclSymbol,
              let caller = sema.symbols.symbol(callerID),
              caller.flags.contains(.inlineFunction),
              ctx.visibilityChecker.isPublicAPI(caller),
              let binding = sema.bindings.callBinding(for: id),
              let callee = sema.symbols.symbol(binding.chosenCallee),
              !isInlineBodyAnonymousObjectMethod(callee, caller: caller),
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

    private func isInlineBodyAnonymousObjectMethod(_ callee: SemanticSymbol, caller: SemanticSymbol) -> Bool {
        guard callee.kind == .function,
              let ownerID = sema.symbols.parentSymbol(for: callee.id),
              let owner = sema.symbols.symbol(ownerID),
              owner.kind == .class,
              owner.flags.contains(.synthetic),
              interner.resolve(owner.name).hasPrefix("__ObjectLiteral_"),
              let callerRange = caller.declSite,
              let ownerRange = owner.declSite,
              callerRange.contains(ownerRange)
        else {
            return false
        }
        return true
    }

    func typeCheckModule(fileScopes: [Int32: FileScope], files: [ASTFile], frontendJobs: Int = 1) throws {
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
                ast: ast, sema: sema,
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

        func hasHeaderResolvedConstructorInitializer(_ property: PropertyDecl, in file: ASTFile, ctx: TypeInferenceContext) -> Bool {
            guard property.type == nil,
                  let initializer = property.initializer,
                  let initializerExpr = ast.arena.expr(initializer),
                  case let .call(calleeID, _, args, _) = initializerExpr,
                  let calleeExpr = ast.arena.expr(calleeID),
                  case let .nameRef(name, _) = calleeExpr,
                  let symbolID = sema.symbols.lookup(fqName: file.packageFQName + [name]),
                  let symbol = sema.symbols.symbol(symbolID),
                  symbol.kind == .class || symbol.kind == .enumClass
            else {
                return false
            }
            // Arguments may read inferred member properties still holding the
            // nullable-Any placeholder (`Node.EMPTY` ahead of the companion
            // body). Defer unless every argument's type is already safe.
            return args.allSatisfy {
                declChecker.safePrecheckExpressionType($0.expr, in: ctx, locals: [:]) != nil
            }
        }

        // Active declarations are file roots, so include their member trees.
        // Otherwise an early function can cache a member property's placeholder.
        var pendingDeclarations = Array(ast.activeDeclarationIDs)
        var visitedDeclarations: Set<DeclID> = []
        while let declaration = pendingDeclarations.popLast() {
            guard visitedDeclarations.insert(declaration).inserted,
                  let node = ast.arena.decl(declaration)
            else { continue }
            switch node {
            case let .propertyDecl(property):
                if property.type == nil, let symbol = sema.bindings.declSymbols[declaration] {
                    pendingPropertyTypes.insert(symbol)
                }
            case let .classDecl(classDecl):
                pendingDeclarations += classDecl.memberProperties + classDecl.nestedClasses + classDecl.nestedObjects
                pendingDeclarations += classDecl.enumEntries.flatMap(\.memberProperties)
                pendingDeclarations += classDecl.enumEntries.flatMap(\.nestedClasses)
                if let companion = classDecl.companionObject { pendingDeclarations.append(companion) }
            case let .interfaceDecl(interfaceDecl):
                pendingDeclarations += interfaceDecl.memberProperties + interfaceDecl.nestedClasses + interfaceDecl.nestedObjects
                if let companion = interfaceDecl.companionObject { pendingDeclarations.append(companion) }
            case let .objectDecl(objectDecl):
                pendingDeclarations += objectDecl.memberProperties + objectDecl.nestedClasses + objectDecl.nestedObjects
            case let .enumEntryDecl(entry):
                pendingDeclarations += entry.memberProperties + entry.nestedClasses
            default:
                break
            }
        }
        for file in files {
            guard let inferCtx = inferenceContext(for: file) else { continue }
            for declaration in file.topLevelDecls {
                guard let symbol = sema.bindings.declSymbols[declaration]
                else { continue }
                let declarationCtx = inferCtx.with(currentDeclSymbol: symbol)
                switch ast.arena.decl(declaration) {
                case let .propertyDecl(property)
                    where property.type == nil && property.receiverType == nil:
                    inferredPropertyDeclarations[symbol] = (declaration, property, declarationCtx)
                default:
                    break
                }
            }
        }

        // A direct object initializer has a fixed nominal type even when its
        // member bodies depend on declarations checked later. Publish only its
        // header so forward callers see its parameterized supertypes. This
        // pre-pass does not check initializers or bodies; existing demand
        // inference and the authoritative declaration pass still own them.
        for file in files {
            guard let inferCtx = inferenceContext(for: file) else { continue }
            for declaration in file.topLevelDecls {
                guard case let .propertyDecl(property)? = ast.arena.decl(declaration),
                      property.type == nil, property.receiverType == nil,
                      let initializer = property.initializer,
                      case let .objectLiteral(superTypes, objectDeclID?, _)? = ast.arena.expr(initializer),
                      case let .objectDecl(objectDecl)? = ast.arena.decl(objectDeclID),
                      let symbol = sema.bindings.declSymbols[declaration]
                else { continue }
                let objectSymbol = exprChecker.predeclareObjectLiteralSymbol(
                    declID: objectDeclID,
                    objectDecl: objectDecl,
                    superTypes: superTypes,
                    ctx: inferCtx.with(currentDeclSymbol: symbol)
                )
                sema.symbols.setPropertyType(sema.types.make(.classType(ClassType(
                    classSymbol: objectSymbol, args: [], nullability: .nonNull
                ))), for: symbol)
                pendingPropertyTypes.remove(symbol)
            }
        }

        // Explicit contracts are declaration metadata. Earlier callers must
        // see them before a later function body happens to be type checked.
        var registeredInferredReturnDeclarations: Set<DeclID> = []
        for file in files {
            guard let inferCtx = inferenceContext(for: file) else { continue }
            for declaration in file.topLevelDecls {
                registerInferredReturnFunctions(
                    in: declaration,
                    context: inferCtx,
                    visited: &registeredInferredReturnDeclarations
                )
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
                      hasHeaderResolvedConstructorInitializer(property, in: file, ctx: inferCtx),
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

        // Explicit backing-field initializers can narrow stable `val` reads.
        // Resolve simple, zero-argument factory initializers before function
        // bodies are checked so their property accesses see the backing type.
        for file in files {
            guard let inferCtx = inferenceContext(for: file) else { continue }
            for declID in file.topLevelDecls {
                guard !precheckedPropertyDecls.contains(declID),
                      case let .propertyDecl(property)? = ast.arena.decl(declID),
                      declChecker.canSafelyPrecheckExplicitBackingFieldProperty(property, in: inferCtx),
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
        // candidate has a concrete declared return type. Include companion and
        // nested object properties before any caller can observe their header
        // placeholders. Unresolved references, inferred-return calls and cycles
        // stay on the source-order pass.
        var previousPrecheckedCount: Int
        repeat {
            previousPrecheckedCount = precheckedPropertyDecls.count
            for file in files {
                guard let inferCtx = inferenceContext(for: file) else { continue }
                for declID in file.topLevelDecls {
                    guard !precheckedPropertyDecls.contains(declID),
                          let decl = ast.arena.decl(declID),
                          let symbol = sema.bindings.declSymbols[declID]
                    else {
                        continue
                    }
                    switch decl {
                    case let .propertyDecl(property):
                        guard declChecker.canSafelyPrecheckInferredProperty(property, in: inferCtx) else {
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
                    case let .classDecl(classDecl):
                        declChecker.precheckIndependentClassMemberProperties(
                            classDecl,
                            symbol: symbol,
                            ctx: inferCtx,
                            solver: solver,
                            diagnostics: diagnostics
                        )
                    case let .objectDecl(objectDecl):
                        declChecker.precheckIndependentObjectMemberProperties(
                            objectDecl,
                            symbol: symbol,
                            ctx: inferCtx,
                            solver: solver,
                            diagnostics: diagnostics
                        )
                    default:
                        continue
                    }
                }
            }
        } while precheckedPropertyDecls.count > previousPrecheckedCount

        // Dependency inference and contract collection above remain module-owned.
        // Workers cannot demand an inferred declaration or modify a signature.
        let independentBodies = try checkIndependentBodies(files: files, fileScopes: fileScopes, frontendJobs: frontendJobs)

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
                if let result = independentBodies[declID] {
                    let stringMapping = interner.mergeWorkerStrings(result.newStrings, startingAt: result.initialStringCount)
                    let typeMapping = sema.types.mergeWorkerTypes(result.newTypes, startingAt: result.initialTypeCount)
                    let symbolMapping = sema.symbols.mergeWorkerLocals(
                        result.localSymbols, strings: stringMapping, types: typeMapping
                    )
                    sema.bindings.mergeIndependentScalarExpressions(
                        types: result.expressionTypes, identifiers: result.identifierSymbols,
                        typeMapping: typeMapping,
                        sourceDeclaredExpectedTypeExpressions: result.sourceDeclaredExpectedTypeExpressions,
                        symbolMapping: symbolMapping
                    )
                    for diagnostic in result.diagnostics { diagnostics.emit(diagnostic) }
                    sema.independentBodyCount += 1
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

                case let .typeAliasDecl(typeAlias):
                    if let underlyingType = sema.symbols.typeAliasUnderlyingType(for: declSymbol) {
                        declChecker.validateOptInTypeUsage(
                            underlyingType,
                            ctx: inferCtx.with(currentDeclSymbol: declSymbol),
                            range: typeAlias.range
                        )
                    }

                case .enumEntryDecl:
                    continue
                }
            }
        }
    }

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
