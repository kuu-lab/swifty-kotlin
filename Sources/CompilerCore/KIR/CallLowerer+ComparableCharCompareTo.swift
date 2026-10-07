/// KUU-1211: `v.compareTo(other)` on a `Comparable<Char>` local that the
/// escape analysis (`ComparableCharEscapeAnalyzer`) proved can stay unboxed
/// under kotlinc's boxing elimination. The generic `Comparable.compareTo`
/// dispatch goes through `__kk_comparable_compareTo`, which mirrors
/// `java.lang.Character.compareTo` and returns the raw code-unit difference
/// (e.g. 'z'-'a' = 25) — correct for a value that escaped into an object
/// position. For a non-escaping local JVM emits `Intrinsics.compare` on the
/// primitive instead, normalizing to -1/0/1; routing the call to
/// `kk_char_compareTo` reproduces that without changing how the local is
/// stored (the runtime helper unboxes either representation).
extension CallLowerer {
    /// Whether `exprID` reads a non-escaping `Comparable<Char>` local —
    /// a `nameRef` bound to a member of the escape-analysis set, optionally
    /// wrapped in `!!` (the null check itself is a non-escaping read).
    private func comparableCharReceiverSymbol(
        _ exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule
    ) -> SymbolID? {
        var current = exprID
        if case let .nullAssert(inner, _) = ast.arena.expr(current) {
            current = inner
        }
        guard case .nameRef = ast.arena.expr(current),
              let symbol = sema.bindings.identifierSymbols[current],
              sema.bindings.nonEscapingComparableCharLocals.contains(symbol)
        else {
            return nil
        }
        return symbol
    }

    func tryLowerComparableCharCompareTo(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        precomputedReceiver: KIRExprID? = nil,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard args.count == 1,
              calleeName == KnownCompilerNames(interner: interner).compareTo,
              // Only when the call resolved to `Comparable<T>.compareTo` — the
              // member whose generic dispatch is `__kk_comparable_compareTo`.
              let chosenCallee = sema.bindings.callBindings[exprID]?.chosenCallee,
              sema.symbols.externalLinkName(for: chosenCallee) == "__kk_comparable_compareTo",
              comparableCharReceiverSymbol(receiverExpr, ast: ast, sema: sema) != nil
        else {
            return nil
        }
        let lhsID = precomputedReceiver ?? driver.lowerExpr(
            receiverExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let rhsID = driver.lowerExpr(
            args[0].expr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let resultType = sema.types.makeNonNullable(sema.bindings.exprTypes[exprID] ?? sema.types.intType)
        let result = arena.appendTemporary(type: resultType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_char_compareTo"),
            arguments: [lhsID, rhsID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return result
    }

    /// The `?.compareTo` counterpart of `tryLowerComparableCharCompareTo`:
    /// emits the same null-guard scaffold the generic safe-call path builds,
    /// but dispatches the non-null branch through `kk_char_compareTo`.
    /// `loweredReceiverID` must already hold the lowered receiver.
    func tryLowerComparableCharCompareToSafeCall(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        loweredReceiverID: KIRExprID,
        boundType: TypeID?,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID? {
        let ast = shared.ast
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        guard args.count == 1,
              calleeName == KnownCompilerNames(interner: interner).compareTo,
              let chosenCallee = sema.bindings.callBindings[exprID]?.chosenCallee,
              sema.symbols.externalLinkName(for: chosenCallee) == "__kk_comparable_compareTo",
              comparableCharReceiverSymbol(receiverExpr, ast: ast, sema: sema) != nil
        else {
            return nil
        }
        let nonNullLabel = driver.ctx.makeLoopLabel()
        let endLabel = driver.ctx.makeLoopLabel()
        let callResultType = sema.types.makeNonNullable(boundType ?? sema.types.intType)
        let nullableResultType = sema.types.makeNullable(callResultType)
        let nullableResult = arena.appendTemporary(type: nullableResultType)
        instructions.append(.jumpIfNotNull(value: loweredReceiverID, target: nonNullLabel))
        let nullValue = arena.appendExpr(.unit, type: nullableResultType)
        instructions.append(.constValue(result: nullValue, value: .null))
        instructions.append(.copy(from: nullValue, to: nullableResult))
        instructions.append(.jump(endLabel))
        instructions.append(.label(nonNullLabel))
        var receiverArgument = loweredReceiverID
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        if receiverType != nonNullReceiverType {
            receiverArgument = arena.appendTemporary(type: nonNullReceiverType)
            instructions.append(.copy(from: loweredReceiverID, to: receiverArgument))
        }
        let argumentID = driver.lowerExpr(args[0].expr, shared: shared, emit: &instructions)
        let nonNullResult = arena.appendTemporary(type: callResultType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_char_compareTo"),
            arguments: [receiverArgument, argumentID],
            result: nonNullResult,
            canThrow: false,
            thrownResult: nil
        ))
        instructions.append(.copy(from: nonNullResult, to: nullableResult))
        instructions.append(.label(endLabel))
        return nullableResult
    }
}
