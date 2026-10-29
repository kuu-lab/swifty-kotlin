extension JVMFunctionBuilder {
    func numericMod(
        _ receiver: ExprID,
        sourceType: JVMValueType,
        args: [CallArgument],
        id: ExprID
    ) throws -> JVMValue? {
        if let selected = program.sema.bindings.callBinding(for: id)?.chosenCallee
            ?? program.sema.bindings.identifierSymbol(for: id)
        {
            guard let symbol = program.sema.symbols.symbol(selected) else { return nil }
            let primitiveName: String? = switch sourceType {
            case .byte: "Byte"
            case .short: "Short"
            case .int: "Int"
            case .long: "Long"
            case .float: "Float"
            case .double: "Double"
            default: nil
            }
            let path = symbol.fqName.map(context.interner.resolve)
            let isBuiltin = path == ["kotlin", "mod"]
                || primitiveName.map { path == ["kotlin", $0, "mod"] } == true
            guard isBuiltin,
                  symbol.declSite.map({ context.sourceManager.origin(of: $0.start.file) != .user }) ?? true
            else { return nil }
        }
        guard args.count == 1, args[0].label == nil, !args[0].isSpread,
              let argumentType = (try? program.expressionType(args[0].expr))?.numericCarrier
        else { return nil }
        let signed: Set<JVMValueType> = [.byte, .short, .int, .long]
        let floating: Set<JVMValueType> = [.float, .double]
        guard (signed.contains(sourceType) && signed.contains(argumentType))
            || (floating.contains(sourceType) && floating.contains(argumentType))
        else { return nil }

        let resultType: JVMValueType
        if case .safeMemberCall = arena.expr(id), let semantic = program.sema.bindings.exprType(for: id) {
            resultType = try program.type(program.sema.types.makeNonNullable(semantic))
        } else {
            resultType = try program.expressionType(id)
        }
        let calculationType = try numericType(sourceType, argumentType)
        let left = try convert(requireValue(receiver), to: calculationType)
        let right = try convert(requireValue(args[0].expr), to: calculationType)
        if signed.contains(sourceType) {
            let value = try jdkCall(
                "java/lang/Math", "floorMod", [calculationType, calculationType], calculationType,
                arguments: [left, right]
            )!
            return try convert(value, to: resultType)
        }

        // Kotlin preserves a zero remainder's sign and otherwise adjusts it
        // when the divisor has a different sign, including infinite divisors.
        let remainder = try value(calculationType)
        instructions.append(.binary(.modulo, left, right, remainder))
        let zero = try constant(calculationType == .float ? .float(0) : .double(0), calculationType)
        let isZero = try value(.boolean)
        instructions.append(.binary(.equal, remainder, zero, isZero))
        let checkSign = label(), adjust = label(), end = label()
        let result = try value(calculationType)
        instructions.append(.jumpIfFalse(isZero, checkSign))
        instructions.append(.copy(remainder, result))
        jump(end)
        mark(checkSign)
        let remainderSign = try jdkCall("java/lang/Math", "signum", [calculationType], calculationType, arguments: [remainder])!
        let divisorSign = try jdkCall("java/lang/Math", "signum", [calculationType], calculationType, arguments: [right])!
        let sameSign = try value(.boolean)
        instructions.append(.binary(.equal, remainderSign, divisorSign, sameSign))
        instructions.append(.jumpIfFalse(sameSign, adjust))
        instructions.append(.copy(remainder, result))
        jump(end)
        mark(adjust)
        instructions.append(.binary(.add, remainder, right, result))
        mark(end)
        return try convert(result, to: resultType)
    }
}
