struct LocalBindings: ExpressibleByDictionaryLiteral, Sequence {
    typealias Value = (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)
    private var bindings: [InternedString: Value]
    private var shadowedBindings: [InternedString: [Value]] = [:]
    var memberFlow: [DataFlowReference: VariableFlowState] = [:]
    var immutableLocalInitializers: [SymbolID: ExprID] = [:]
    var delegatedLocalSymbols: Set<SymbolID> = []
    var variableFacts: [SymbolID: DataFlowValueFacts] = [:]
    var invalidatedVariableFacts: Set<SymbolID> = []
    var possiblyAssignedVals: Set<SymbolID> = []
    var safeCallArgumentInitializations: [ExprID: Set<SymbolID>] = [:]
    var preservesShadowedBindings = false

    init(dictionaryLiteral elements: (InternedString, Value)...) {
        bindings = Dictionary(uniqueKeysWithValues: elements)
    }

    subscript(name: InternedString) -> Value? {
        get { bindings[name] }
        set {
            if preservesShadowedBindings,
               let newValue,
               let displaced = bindings[name],
               displaced.symbol != newValue.symbol {
                shadowedBindings[name, default: []].append(displaced)
            }
            bindings[name] = newValue
        }
    }

    func binding(named name: InternedString, matching symbol: SymbolID) -> Value? {
        if let current = bindings[name], current.symbol == symbol {
            return current
        }
        return shadowedBindings[name]?.last(where: { $0.symbol == symbol })
    }

    func containsInitializedBinding(for symbol: SymbolID) -> Bool {
        if bindings.values.contains(where: { $0.symbol == symbol && $0.isInitialized }) {
            return true
        }
        return shadowedBindings.values.contains { stack in
            stack.contains { $0.symbol == symbol && $0.isInitialized }
        }
    }

    var values: Dictionary<InternedString, Value>.Values { bindings.values }
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
        variableFacts.removeValue(forKey: root)
        invalidatedVariableFacts.insert(root)
    }

    mutating func joinVariableFacts(from branches: [LocalBindings]) {
        guard let first = branches.first else { return }
        invalidatedVariableFacts = branches.reduce(into: Set<SymbolID>()) {
            $0.formUnion($1.invalidatedVariableFacts)
        }
        var joined = first.variableFacts
        for branch in branches.dropFirst() {
            for symbol in Array(joined.keys) {
                guard let other = branch.variableFacts[symbol],
                      let current = joined[symbol]
                else {
                    joined.removeValue(forKey: symbol)
                    continue
                }
                joined[symbol] = current.joining(other)
            }
        }
        variableFacts = joined.filter { !$0.value.isEmpty }
    }
}

final class TypeCheckDriver {
    var isCheckingAnnotationConstruction = false
    var callSuspensionContexts: [ExprID: SuspensionContext] = [:]
    var callComposableContexts: [ExprID: SuspensionContext] = [:]
    var specialSuspendingCallNames: [ExprID: String] = [:]
    var coroutineContextPropertySuspensionContexts: [ExprID: SuspensionContext] = [:]
    var precheckedPropertyDecls: Set<DeclID> = []
    var publishedInferredPropertyDecls: Set<DeclID> = []
    var predeclaredObjectLiteralDecls: Set<DeclID> = []
    /// Ordered log of local nominal decls (object literals, local
    /// classes/objects, typealiases) whose member check committed. A
    /// speculative inferred-return check can roll its diagnostics back and
    /// retry the declaration later; the bound symbols survive the rollback,
    /// so without `pendingLocalNominalRechecks` the `ensure*` early returns
    /// would skip their member checks and lose any errors inside them.
    var localNominalDeclChecks: [DeclID] = []
    var pendingLocalNominalRechecks: Set<DeclID> = []

    func markLocalNominalRechecks(since mark: Int) {
        guard mark < localNominalDeclChecks.count else { return }
        pendingLocalNominalRechecks.formUnion(localNominalDeclChecks[mark...])
    }

    var inferredReturnFunctions: [SymbolID: (function: FunDecl, context: TypeInferenceContext, baseLocals: LocalBindings)] = [:]
    var checkingInferredReturnFunctions: Set<SymbolID> = []
    var checkedInferredReturnFunctions: Set<SymbolID> = []
    var inferredPropertyDeclarations: [SymbolID: (declaration: DeclID, property: PropertyDecl, context: TypeInferenceContext, initialLocals: LocalBindings)] = [:]
    var checkingInferredProperties: Set<SymbolID> = []
    var pendingPropertyTypes: Set<SymbolID> = []
    var deferredInferredReturnFunctions: Set<SymbolID> = []
    var deferredInferredProperties: Set<SymbolID> = []
    var isCheckingSourceOrderBodies = false

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
    private let superReceiverExprIDs: Set<ExprID>

    private(set) lazy var exprChecker = ExprTypeChecker(driver: self)
    private(set) lazy var callChecker = CallTypeChecker(driver: self)
    private(set) lazy var controlFlowChecker = ControlFlowTypeChecker(driver: self)
    private(set) lazy var localDeclChecker = LocalDeclTypeChecker(driver: self)
    private(set) lazy var declChecker = DeclTypeChecker(driver: self)

    private(set) lazy var builtinTypeNamesCache = BuiltinTypeNames(interner: interner)

    private(set) lazy var companionExtensionFunctionDeclsByName: [InternedString: [SymbolID]] = {
        var index: [InternedString: [SymbolID]] = [:]
        for file in ast.files {
            for declID in file.topLevelDecls {
                guard case let .funDecl(function)? = ast.arena.decl(declID),
                      function.modifiers.contains(.companion),
                      function.receiverType != nil,
                      let symbol = sema.bindings.declSymbols[declID]
                else {
                    continue
                }
                index[function.name, default: []].append(symbol)
            }
        }
        return index
    }()

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
        self.superReceiverExprIDs = Self.collectSuperReceiverExprIDs(in: ast)
    }

    func isSuperReceiverExpression(_ id: ExprID) -> Bool {
        superReceiverExprIDs.contains(id)
    }

    private static func collectSuperReceiverExprIDs(in ast: ASTModule) -> Set<ExprID> {
        var result: Set<ExprID> = []

        func insertIfSuper(_ id: ExprID) {
            guard case .superRef? = ast.arena.expr(id) else { return }
            result.insert(id)
        }

        for index in ast.arena.exprs.indices {
            let id = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(id) else { continue }
            switch expr {
            case let .memberAssign(receiver, _, _, _),
                 let .safeMemberAssign(receiver, _, _, _),
                 let .memberCall(receiver, _, _, _, _),
                 let .safeMemberCall(receiver, _, _, _, _),
                 let .indexedAssign(receiver, _, _, _),
                 let .indexedAccess(receiver, _, _),
                 let .indexedCompoundAssign(_, receiver, _, _, _),
                 let .memberCompoundAssign(_, receiver, _, _, _):
                insertIfSuper(receiver)
            case let .binary(op, lhs, _, _):
                switch op {
                case .add, .subtract, .multiply, .divide, .modulo,
                     .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual,
                     .rangeTo, .rangeUntil, .downTo, .step,
                     .bitwiseAnd, .bitwiseOr, .bitwiseXor, .shl, .shr, .ushr:
                    insertIfSuper(lhs)
                case .equal, .notEqual, .identityEqual, .notIdentityEqual,
                     .logicalAnd, .logicalOr, .elvis:
                    break
                }
            case let .unaryExpr(_, operand, _):
                insertIfSuper(operand)
            case let .inExpr(_, rhs, _), let .notInExpr(_, rhs, _):
                insertIfSuper(rhs)
            default:
                break
            }
        }

        return result
    }

    func inferExpr(
        _ id: ExprID,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID? = nil,
        isStatementContext: Bool = false,
        inferLambdaResultType: Bool = false
    ) -> TypeID {
        sema.types.attribution?.increment(.exprInferences)
        if let subjectType = ctx.whenSubjectTypes[id] {
            return subjectType
        }
        var expressionContext = ctx
        if expressionContext.elvisRhsCallResultTypeHintExpr != id {
            expressionContext.elvisRhsCallResultTypeHint = nil
            expressionContext.elvisRhsCallResultTypeHintExpr = nil
        }
        expressionContext = helpers.expressionOptInContext(id, ctx: expressionContext)
        let ctx = expressionContext.syncingImplicitReceiver(from: locals)
        let type = exprChecker.inferExpr(
            id, ctx: ctx, locals: &locals, expectedType: expectedType,
            isStatementContext: isStatementContext, inferLambdaResultType: inferLambdaResultType
        )
        if let expectedType, sema.bindings.hasSourceDeclaredExpectedType(id) {
            recordGenericCallConsumer(id, type: expectedType)
        }
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
        if !composableCallTargets(for: id).isEmpty {
            var composition = ctx.suspensionContext
            if composition.function == nil { composition.function = ctx.defaultArgumentComposableFunction }
            callComposableContexts[id] = composition
        }
        if isCoroutineContextPropertyRead(id) {
            coroutineContextPropertySuspensionContexts[id] = ctx.suspensionContext
        }
        checkInlineCallVisibility(id, ctx: ctx)
        return type
    }

    func recordGenericCallConsumer(_ id: ExprID, type: TypeID?) {
        var value = id
        while case let .blockExpr(_, trailing, _) = ast.arena.expr(value), let trailing {
            value = trailing
        }
        switch ast.arena.expr(value) {
        case .call, .memberCall, .safeMemberCall, .indexedAccess:
            sema.bindings.bindGenericCallConsumerType(value, type: type)
        default:
            break
        }
    }

    func isCoroutineContextPropertyRead(_ id: ExprID) -> Bool {
        let isPropertyReadSyntax: Bool
        switch ast.arena.expr(id) {
        case .nameRef?:
            isPropertyReadSyntax = true
        case let .memberCall(_, _, _, args, _)? where args.isEmpty && !ast.arena.isExplicitCall(id):
            isPropertyReadSyntax = true
        default:
            isPropertyReadSyntax = false
        }
        guard isPropertyReadSyntax,
              let symbolID = sema.bindings.identifierSymbol(for: id),
              let symbol = sema.symbols.symbol(symbolID),
              symbol.kind == .property
        else {
            return false
        }
        let coroutineContextFQName = ["kotlin", "coroutines", "coroutineContext"].map(interner.intern)
        return symbol.fqName == coroutineContextFQName
    }

    func diagnoseLocalValueOrClassifierRedeclaration(
        named name: InternedString,
        expression: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) {
        guard let scope = ctx.scope as? BaseScope,
              scope.registerLocalValueOrClassifierDeclaration(named: name, expression: expression)
        else {
            return
        }
        diagnostics.error(
            "KSWIFTK-SEMA-0001",
            "Conflicting local declarations for '\(interner.resolve(name))'.",
            range: range
        )
    }

    func recordPlatformNullAssertion(
        _ id: ExprID, sourceType: TypeID, targetType: TypeID, declaredParameterType: TypeID? = nil
    ) {
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
              owner.flags.contains(.objectLiteralSynthetic),
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
            diagnostics: diagnostics,
            interner: interner,
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
            return args.allSatisfy {
                declChecker.safePrecheckExpressionType($0.expr, in: ctx, locals: [:]) != nil
            }
        }

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
                    inferredPropertyDeclarations[symbol] = (declaration, property, declarationCtx, [:])
                default:
                    break
                }
            }
        }

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

        var previousPrecheckedCount: Int
        var previousPendingCount: Int
        var previousPublishedCount: Int
        repeat {
            previousPrecheckedCount = precheckedPropertyDecls.count
            previousPendingCount = pendingPropertyTypes.count
            previousPublishedCount = publishedInferredPropertyDecls.count
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
                        if declChecker.canSafelyPrecheckInferredProperty(
                            property,
                            symbol: symbol,
                            in: inferCtx
                        ) {
                            declChecker.typeCheckBoundPropertyDecl(
                                property,
                                declID: declID,
                                symbol: symbol,
                                ctx: inferCtx.with(currentDeclSymbol: symbol),
                                solver: solver,
                                diagnostics: diagnostics
                            )
                            precheckedPropertyDecls.insert(declID)
                        } else if sema.symbols.propertyType(for: symbol) == sema.types.nullableAnyType,
                                  declChecker.canPublishInferredPropertyTypeEarly(
                                      property,
                                      in: inferCtx
                                  )
                        {
                            let diagnosticSnapshot = diagnostics.count
                            let nominalDeclsCheckedBefore = localNominalDeclChecks.count
                            declChecker.typeCheckBoundPropertyDecl(
                                property,
                                declID: declID,
                                symbol: symbol,
                                ctx: inferCtx.with(currentDeclSymbol: symbol),
                                solver: solver,
                                diagnostics: diagnostics,
                                checkAccessorBodies: false
                            )
                            diagnostics.truncate(to: diagnosticSnapshot)
                            markLocalNominalRechecks(since: nominalDeclsCheckedBefore)
                        } else if !publishedInferredPropertyDecls.contains(declID),
                                  declChecker.canSafelyPrecheckInferredPropertyInitializerType(
                                      property,
                                      in: inferCtx
                                  )
                        {
                            declChecker.publishInferredPropertyInitializerType(
                                property,
                                symbol: symbol,
                                in: inferCtx.with(currentDeclSymbol: symbol)
                            )
                            publishedInferredPropertyDecls.insert(declID)
                        } else if !publishedInferredPropertyDecls.contains(declID),
                                  declChecker.canPublishInferredGetterPropertyType(
                                      property,
                                      in: inferCtx
                                  )
                        {
                            declChecker.publishInferredGetterPropertyType(
                                property,
                                symbol: symbol,
                                in: inferCtx.with(currentDeclSymbol: symbol)
                            )
                            publishedInferredPropertyDecls.insert(declID)
                        }
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
                    case let .interfaceDecl(interfaceDecl):
                        declChecker.precheckIndependentInterfaceMemberProperties(
                            interfaceDecl,
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
            || pendingPropertyTypes.count < previousPendingCount
            || publishedInferredPropertyDecls.count > previousPublishedCount

        let independentBodies = try checkIndependentBodies(files: files, fileScopes: fileScopes, frontendJobs: frontendJobs)

        var deferredJVMInlineBodies: [SymbolID: (declaration: DeclID, function: FunDecl, context: TypeInferenceContext)] = [:]
        isCheckingSourceOrderBodies = true
        for file in files {
            guard let inferCtx = inferenceContext(for: file) else { continue }
            let skipResidualStdlibBodies = compilationContext.map {
                !$0.options.stdlibOnly
                    && $0.sourceManager.origin(of: file.fileID) == .residualStdlib
                    && !$0.jvmConsumerEmittedStdlibFiles.contains(file.fileID)
            } ?? false
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      let declSymbol = sema.bindings.declSymbols[declID]
                else {
                    continue
                }
                if precheckedPropertyDecls.contains(declID)
                    || sema.unreachableTopLevelFunctionDecls.contains(declID)
                {
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
                        compoundAssignReceiverTypes: result.compoundAssignReceiverTypes,
                        sourceDeclaredExpectedTypeExpressions: result.sourceDeclaredExpectedTypeExpressions,
                        symbolMapping: symbolMapping
                    )
                    for diagnostic in result.diagnostics { diagnostics.emit(diagnostic) }
                    sema.independentBodyCount += 1
                    continue
                }
                switch decl {
                case let .funDecl(function):
                    if compilationContext?.deferredJVMInlineBodies[declID] != nil {
                        deferredJVMInlineBodies[declSymbol] = (declID, function, inferCtx.with(currentDeclSymbol: declSymbol))
                        continue
                    }
                    if skipResidualStdlibBodies && !function.isInline {
                        continue
                    }
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
        checkDemandedJVMInlineBodies(&deferredJVMInlineBodies)
    }

    func emitSubtypeConstraint(
        left: TypeID,
        right: TypeID,
        range: SourceRange?,
        solver: ConstraintSolver,
        sema: SemaModule,
        diagnostics: DiagnosticEngine,
        secondaryRanges: [SourceRange] = [],
        suppressPlatformWarning: Bool = false,
        diagnosticCode: String? = nil,
        failureMessage: String? = nil
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
            var failure = failure
            if let diagnosticCode {
                failure = Diagnostic(
                    severity: failure.severity,
                    code: diagnosticCode,
                    message: failureMessage ?? failure.message,
                    primaryRange: failure.primaryRange,
                    secondaryRanges: failure.secondaryRanges,
                    codeActions: failure.codeActions
                )
            }
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
                  sema.types.nullability(of: right) == .nonNull,
                  !isCompilerOwnedSourceRange(warningRange)
        {
            diagnostics.warning(
                "KSWIFTK-SEMA-PLATFORM",
                "Expression of platform type is used as non-null without a null check. " +
                    "This may cause a NullPointerException at runtime.",
                range: warningRange
            )
        }
    }

    private func isCompilerOwnedSourceRange(_ range: SourceRange) -> Bool {
        sourceManager?.origin(of: range.start.file)?.isBundledStdlib == true
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
