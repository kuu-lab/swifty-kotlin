
/// Lowering for an explicit `.compareTo(other)` member call on a primitive
/// `Comparable` receiver (Int/Long/UInt/ULong/Boolean/Float/Double, plus the
/// signed Byte/Short and unsigned UByte/UShort that share the Int ABI).
///
/// The desugared comparison operators (`<`, `>`, …) already compute the
/// comparison directly via machine compare in `lowerBinaryExpr`, but the
/// *explicit* member call has no runtime mapping: its `compareTo` symbol comes
/// from the built-in `Comparable<T>` member and carries no `externalLinkName`,
/// so the generic resolution in `loweredMemberCalleeName` falls back to the raw
/// symbol name `compareTo` and codegen emits an undefined external `_compareTo`
/// reference that fails to link. Here we intercept the call before that generic
/// path and route it to `kk_primitive_compareTo`, mirroring how
/// `String.compareTo` maps to `kk_string_compareTo_member`.
///
/// Char is intentionally excluded: it already resolves through its own
/// `kk_char_compareTo` synthetic stub, which returns the raw codepoint
/// difference (matching `Character.compare`) rather than the sign (-1/0/1) that
/// `kk_primitive_compareTo` produces.
extension CallLowerer {
    func tryLowerPrimitiveCompareTo(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard args.count == 1,
              interner.resolve(calleeName) == "compareTo",
              let receiverType = sema.bindings.exprTypes[receiverExpr],
              let kind = primitiveCompareABIKind(for: receiverType, sema: sema),
              kind != .char
        else {
            return nil
        }
        // Only handle same-kind comparisons (e.g. Int.compareTo(Int)). Mixed
        // numeric overloads such as Int.compareTo(Double) require widening the
        // receiver to the common type before comparing, which this raw-value
        // path cannot express; let those fall through unchanged.
        guard let argType = sema.bindings.exprTypes[args[0].expr],
              primitiveCompareABIKind(for: argType, sema: sema) == kind
        else {
            return nil
        }

        let lhsID = driver.lowerExpr(
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
        let kindLiteral = Int64(kind.rawValue)
        let kindExpr = arena.appendExpr(.intLiteral(kindLiteral), type: sema.types.intType)
        instructions.append(.constValue(result: kindExpr, value: .intLiteral(kindLiteral)))

        let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.intType
        let result = arena.appendTemporary(type: resultType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_primitive_compareTo"),
            arguments: [lhsID, rhsID, kindExpr],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return result
    }
}
