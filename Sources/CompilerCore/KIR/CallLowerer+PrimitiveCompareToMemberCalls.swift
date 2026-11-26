
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
        func isSignedNumeric(_ type: TypeID) -> Bool {
            switch sema.types.kind(of: sema.types.makeNonNullable(type)) {
            case .primitive(.byte, _), .primitive(.short, _), .primitive(.int, _),
                 .primitive(.long, _), .primitive(.float, _), .primitive(.double, _):
                true
            default:
                false
            }
        }
        let isNumericComparison = isSignedNumeric(receiverType) && isSignedNumeric(argType)
        guard argumentKind == receiverKind || isNumericComparison else {
            return nil
        }

        let kind: PrimitiveCompareABIKind
        if isNumericComparison {
            if receiverKind == .double || argumentKind == .double {
                kind = .double
            } else if receiverKind == .float || argumentKind == .float {
                kind = .float
            } else if receiverKind == .long || argumentKind == .long {
                kind = .long
            } else {
                kind = .int
            }
        } else {
            kind = receiverKind
        }
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
        if kind == .float || kind == .double {
            lhsID = widenIntegerOperandToFloatingPoint(
                lhsID, operandTypeID: nonNullReceiverType,
                isFloatingPoint: receiverKind == .float || receiverKind == .double, toDouble: kind == .double,
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
            callee: interner.intern("kk_primitive_compareTo"),
            arguments: [lhsID, rhsID, kindExpr],
            result: result,
            canThrow: false
        ))
        return result
    }
}
