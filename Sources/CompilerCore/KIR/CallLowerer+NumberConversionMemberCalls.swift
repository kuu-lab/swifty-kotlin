
extension CallLowerer {
    func tryLowerNumberConversion(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction],
        precomputedReceiver: KIRExprID? = nil,
        safeCall: Bool = false
    ) -> KIRExprID? {
        guard args.isEmpty,
              let targetKind = numberConversionTargetKind(for: calleeName, interner: interner),
              let chosenCallee = sema.bindings.callBindings[exprID]?.chosenCallee,
              chosenCallee != .invalid,
              let numberClassSymbol = sema.types.numberClassSymbol,
              sema.symbols.parentSymbol(for: chosenCallee) == numberClassSymbol,
              let layout = sema.symbols.nominalLayout(for: numberClassSymbol),
              let slot = layout.vtableSlots[chosenCallee]
        else {
            return nil
        }

        let receiverType = sema.types.makeNonNullable(
            sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        )
        switch sema.types.kind(of: receiverType) {
        case let .classType(classType) where classType.classSymbol == numberClassSymbol:
            break
        case .typeParam:
            break
        case let .intersection(parts) where parts.contains(where: {
            if case .typeParam = sema.types.kind(of: $0) { return true }
            return false
        }):
            break
        default:
            return nil
        }

        let intType = sema.types.intType
        let receiverID: KIRExprID
        if let precomputedReceiver {
            receiverID = precomputedReceiver
        } else {
            receiverID = driver.lowerExpr(
                receiverExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }
        let slotLiteral = Int64(slot)
        let kindLiteral = Int64(targetKind.rawValue)
        let resultType = sema.bindings.exprTypes[exprID] ?? intType
        if safeCall {
            let nonNullLabel = driver.ctx.makeLoopLabel()
            let endLabel = driver.ctx.makeLoopLabel()
            let result = arena.appendTemporary(type: resultType)
            let nullValue = arena.appendExpr(.unit, type: resultType)
            instructions.append(.jumpIfNotNull(value: receiverID, target: nonNullLabel))
            instructions.append(.constValue(result: nullValue, value: .null))
            instructions.append(.copy(from: nullValue, to: result))
            instructions.append(.jump(endLabel))
            instructions.append(.label(nonNullLabel))
            let slotExpr = arena.appendExpr(.intLiteral(slotLiteral), type: intType)
            instructions.append(.constValue(result: slotExpr, value: .intLiteral(slotLiteral)))
            let kindExpr = arena.appendExpr(.intLiteral(kindLiteral), type: intType)
            instructions.append(.constValue(result: kindExpr, value: .intLiteral(kindLiteral)))
            let callResult = arena.appendTemporary(type: sema.types.makeNonNullable(resultType))
            instructions.append(.call(
                callee: interner.intern("kk_number_to_primitive"),
                arguments: [receiverID, slotExpr, kindExpr],
                result: callResult,
                canThrow: false
            ))
            instructions.append(.copy(from: callResult, to: result))
            instructions.append(.label(endLabel))
            return result
        }
        let slotExpr = arena.appendExpr(.intLiteral(slotLiteral), type: intType)
        instructions.append(.constValue(result: slotExpr, value: .intLiteral(slotLiteral)))
        let kindExpr = arena.appendExpr(.intLiteral(kindLiteral), type: intType)
        instructions.append(.constValue(result: kindExpr, value: .intLiteral(kindLiteral)))
        let result = arena.appendTemporary(type: resultType)
        instructions.append(.call(
            callee: interner.intern("kk_number_to_primitive"),
            arguments: [receiverID, slotExpr, kindExpr],
            result: result,
            canThrow: false
        ))
        return result
    }
}
