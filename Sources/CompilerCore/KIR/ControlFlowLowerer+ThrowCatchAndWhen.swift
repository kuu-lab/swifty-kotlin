
extension ControlFlowLowerer {
    func appendThrowAwareInstructions(
        _ loweredInstructions: KIRLoweringEmitContext,
        exceptionSlot: KIRExprID,
        exceptionTypeSlot: KIRExprID,
        thrownTarget: Int32,
        sema: SemaModule,
        interner: StringInterner,
        arena: KIRArena,
        emit instructions: inout KIRLoweringEmitContext
    ) {
        appendThrowAwareInstructions(
            Array(loweredInstructions),
            exceptionSlot: exceptionSlot,
            exceptionTypeSlot: exceptionTypeSlot,
            thrownTarget: thrownTarget,
            sema: sema,
            interner: interner,
            arena: arena,
            instructions: &instructions.instructions
        )
    }

    func resolveCatchClauseBinding(
        _ clause: CatchClause,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> CatchClauseBinding {
        if let binding = sema.bindings.catchClauseBinding(for: clause.body) {
            return binding
        }
        let fallbackType = resolveLegacyCatchClauseType(
            clause.paramType,
            ast: ast,
            sema: sema,
            interner: interner
        )
        let fallbackSymbol = sema.bindings.identifierSymbols[clause.body] ?? .invalid
        return CatchClauseBinding(parameterSymbol: fallbackSymbol, parameterType: fallbackType)
    }

    func resolveLegacyCatchClauseType(
        _ paramType: TypeRefID?,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        guard let paramType else {
            return sema.types.anyType
        }
        guard let ref = ast.arena.typeRef(paramType),
              case let .named(path, _, nullable) = ref,
              let shortName = path.last
        else {
            return sema.types.errorType
        }
        let nullability: Nullability = nullable ? .nullable : .nonNull
        if path.count == 1,
           let builtin = BuiltinTypeNames(interner: interner).resolveBuiltinType(shortName, nullability: nullability, types: sema.types)
        {
            return builtin
        }
        func isTypeLikeSymbol(_ symbolID: SymbolID) -> Bool {
            guard let symbol = sema.symbols.symbol(symbolID) else {
                return false
            }
            switch symbol.kind {
            case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
                return true
            default:
                return false
            }
        }
        let fqCandidates = sema.symbols.lookupAll(fqName: path)
            .filter(isTypeLikeSymbol)
            .sorted { $0.rawValue < $1.rawValue }
        let candidates = if !fqCandidates.isEmpty {
            fqCandidates
        } else {
            sema.symbols.lookupByShortName(shortName)
                .filter(isTypeLikeSymbol)
                .sorted { $0.rawValue < $1.rawValue }
        }
        guard let symbol = candidates.first else {
            return sema.types.errorType
        }
        return sema.types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: nullability)))
    }

    func isCatchAllType(_ type: TypeID, sema: SemaModule) -> Bool {
        type == sema.types.anyType || type == sema.types.nullableAnyType || type == sema.types.errorType
    }

    func isCatchAllType(_ type: TypeID, sema: SemaModule, interner: StringInterner) -> Bool {
        if isCatchAllType(type, sema: sema) {
            return true
        }
        if type == sema.types.anyType || type == sema.types.nullableAnyType {
            return true
        }
        guard let (_, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        return KnownCompilerNames(interner: interner).isThrowableCatchAllSymbol(symbol)
    }

    func isCancellationExceptionType(_ type: TypeID, sema: SemaModule, interner: StringInterner) -> Bool {
        guard let (_, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        return KnownCompilerNames(interner: interner).isCancellationExceptionSymbol(symbol)
    }

    func lowerForDestructuringExpr(
        _ exprID: ExprID,
        names: [InternedString?],
        iterableExpr: ExprID,
        bodyExpr: ExprID,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        lowerForDestructuringExpr(
            exprID,
            names: names,
            iterableExpr: iterableExpr,
            bodyExpr: bodyExpr,
            ast: shared.ast,
            sema: shared.sema,
            arena: shared.arena,
            interner: shared.interner,
            propertyConstantInitializers: shared.propertyConstantInitializers,
            instructions: &instructions.instructions
        )
    }

    func lowerWhenExpr(
        _ exprID: ExprID,
        subject: ExprID?,
        branches: [WhenBranch],
        elseExpr: ExprID?,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        lowerWhenExpr(
            exprID,
            subject: subject,
            branches: branches,
            elseExpr: elseExpr,
            ast: shared.ast,
            sema: shared.sema,
            arena: shared.arena,
            interner: shared.interner,
            propertyConstantInitializers: shared.propertyConstantInitializers,
            instructions: &instructions.instructions
        )
    }
}
