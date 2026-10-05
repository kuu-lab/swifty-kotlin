
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
/// `String.compareTo` maps to `__kk_string_compareTo_member`.
///
/// Char is intentionally excluded: it already resolves through its own
/// `kk_char_compareTo` synthetic stub, which also returns the sign (-1/0/1).
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
        precomputedReceiver: KIRExprID? = nil,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        let knownNames = KnownCompilerNames(interner: interner)
        guard args.count == 1,
              calleeName == knownNames.compareTo,
              let receiverType = sema.bindings.exprTypes[receiverExpr],
              let receiverKind = primitiveCompareABIKind(for: receiverType, sema: sema),
              receiverKind != .char,
              let argType = sema.bindings.exprTypes[args[0].expr]
        else {
            return nil
        }
        let argumentKind = primitiveCompareABIKind(for: argType, sema: sema)
        let isFloatingReceiver = receiverKind == .float || receiverKind == .double
        let isNumericArgument: Bool = switch sema.types.kind(of: sema.types.makeNonNullable(argType)) {
        case .primitive(.byte, _), .primitive(.short, _), .primitive(.int, _),
             .primitive(.long, _), .primitive(.float, _), .primitive(.double, _):
            true
        default:
            false
        }
        guard argumentKind == receiverKind || (isFloatingReceiver && isNumericArgument) else {
            return nil
        }

        let kind: PrimitiveCompareABIKind = isFloatingReceiver && argumentKind == .double ? .double : receiverKind
        var lhsID = precomputedReceiver ?? driver.lowerExpr(
            receiverExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        if precomputedReceiver != nil, nonNullReceiverType != receiverType {
            let unboxedReceiver = arena.appendTemporary(type: nonNullReceiverType)
            instructions.append(.copy(from: lhsID, to: unboxedReceiver))
            lhsID = unboxedReceiver
        }
        var rhsID = driver.lowerExpr(
            args[0].expr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        if isFloatingReceiver {
            lhsID = widenIntegerOperandToFloatingPoint(
                lhsID, operandTypeID: nonNullReceiverType, isFloatingPoint: true, toDouble: kind == .double,
                sema: sema, arena: arena, interner: interner, instructions: &instructions
            )
            rhsID = widenIntegerOperandToFloatingPoint(
                rhsID, operandTypeID: argType,
                isFloatingPoint: argumentKind == .float || argumentKind == .double, toDouble: kind == .double,
                sema: sema, arena: arena, interner: interner, instructions: &instructions
            )
        }
        let kindLiteral = Int64(kind.rawValue)
        let kindExpr = arena.appendExpr(.intLiteral(kindLiteral), type: sema.types.intType)
        instructions.append(.constValue(result: kindExpr, value: .intLiteral(kindLiteral)))

        let resultType = sema.types.makeNonNullable(sema.bindings.exprTypes[exprID] ?? sema.types.intType)
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
