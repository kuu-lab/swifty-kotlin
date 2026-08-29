
final class OperatorLoweringPass: LoweringPass, ParallelLoweringPass {
    static let name = "OperatorLowering"

    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool {
        _ = ctx
        module.ensureFeaturesScanned()
        return !module.features.isDisjoint(with: [.hasBinaryOp, .hasUnaryOp, .hasNullAssert])
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
        module.arena.transformFunctions { function in
            var updated = function
            var newBody: [KIRInstruction] = []
            newBody.reserveCapacity(function.body.count)
            for instruction in function.body {
                switch instruction {
                case let .binary(op, lhs, rhs, result):
                    lowerBinaryInstruction(
                        op: op, lhs: lhs, rhs: rhs, result: result,
                        arena: module.arena, interner: ctx.interner,
                        types: ctx.sema?.types, newBody: &newBody
                    )
                case let .unary(op, operand, result):
                    let callee: InternedString = switch op {
                    case .not: ctx.interner.intern("kk_op_not")
                    case .unaryPlus: ctx.interner.intern("kk_op_uplus")
                    case .unaryMinus: ctx.interner.intern("kk_op_uminus")
                    }
                    newBody.append(.call(symbol: nil, callee: callee, arguments: [operand], result: result, canThrow: false, thrownResult: nil))
                case let .nullAssert(operand, result):
                    lowerNullAssertInstruction(
                        operand: operand,
                        result: result,
                        arena: module.arena,
                        interner: ctx.interner,
                        types: ctx.sema?.types,
                        newBody: &newBody
                    )
                case .call:
                    newBody.append(instruction)
                default:
                    newBody.append(instruction)
                }
            }
            updated.replaceBody(newBody)
            return updated
        }
        module.recordLowering(Self.name)
    }

    private func lowerNullAssertInstruction(
        operand: KIRExprID,
        result: KIRExprID,
        arena: KIRArena,
        interner: StringInterner,
        types: TypeSystem?,
        newBody: inout [KIRInstruction]
    ) {
        let notNullResult = arena.appendTemporary(type: arena.exprType(result))
        newBody.append(
            .call(
                symbol: nil,
                callee: interner.intern("kk_op_notnull"),
                arguments: [operand],
                result: notNullResult,
                canThrow: true,
                thrownResult: nil
            )
        )

        guard let types, let resultType = arena.exprType(result) else {
            // No type information available; keep the raw not-null result.
            newBody.append(.copy(from: notNullResult, to: result))
            return
        }

        if let unboxCallee = unboxCallee(for: types.kind(of: resultType), interner: interner) {
            newBody.append(
                .call(
                    symbol: nil,
                    callee: unboxCallee,
                    arguments: [notNullResult],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                )
            )
        } else {
            newBody.append(.copy(from: notNullResult, to: result))
        }
    }

    private func unboxCallee(for typeKind: TypeKind, interner: StringInterner) -> InternedString? {
        guard case let .primitive(primitiveType, .nonNull) = typeKind else {
            return nil
        }
        switch primitiveType {
        case .int, .byte, .short, .ubyte, .ushort, .uint:
            return interner.intern("kk_unbox_int")
        case .long:
            return interner.intern("kk_unbox_long")
        case .ulong:
            return interner.intern("kk_unbox_ulong")
        case .boolean:
            return interner.intern("kk_unbox_bool")
        case .char:
            return interner.intern("kk_unbox_char")
        case .float:
            return interner.intern("kk_unbox_float")
        case .double:
            return interner.intern("kk_unbox_double")
        }
    }

    private func lowerBinaryInstruction(
        op: KIRBinaryOp,
        lhs: KIRExprID,
        rhs: KIRExprID,
        result: KIRExprID,
        arena: KIRArena,
        interner: StringInterner,
        types: TypeSystem?,
        newBody: inout [KIRInstruction]
    ) {
        // STDLIB-CORO-077: CoroutineContext + operator -> kk_context_plus
        if op == .add, isCoroutineContextType(lhs, arena: arena, types: types, interner: interner)
            || isCoroutineContextType(rhs, arena: arena, types: types, interner: interner)
        {
            let callee = interner.intern("kk_context_plus")
            newBody.append(.call(symbol: nil, callee: callee, arguments: [lhs, rhs], result: result, canThrow: false, thrownResult: nil))
            return
        }

        let lhsRank = primitiveRank(for: lhs, arena: arena, types: types)
        let rhsRank = primitiveRank(for: rhs, arena: arena, types: types)
        let rank = max(lhsRank, rhsRank)
        let isUnsigned = isUnsignedOperand(lhs, arena: arena, types: types)
            || isUnsignedOperand(rhs, arena: arena, types: types)
        let prefix = switch rank {
        case 2: "d"
        case 1: "f"
        default: ""
        }
        var effectiveLhs = lhs
        var effectiveRhs = rhs
        if rank > 0 {
            if lhsRank < rank {
                let convCallee = conversionCallee(fromRank: lhsRank, toRank: rank, interner: interner)
                let converted = arena.appendTemporary(type: arena.exprType(result))
                emitNonThrowingCall(callee: convCallee, arg: lhs, result: converted, into: &newBody)
                effectiveLhs = converted
            }
            if rhsRank < rank {
                let convCallee = conversionCallee(fromRank: rhsRank, toRank: rank, interner: interner)
                let converted = arena.appendTemporary(type: arena.exprType(result))
                emitNonThrowingCall(callee: convCallee, arg: rhs, result: converted, into: &newBody)
                effectiveRhs = converted
            }
        }
        // For unsigned int/long: add/sub/mul/eq/ne use same callees; div/rem/lt/le/gt/ge use u-prefix
        let useUnsignedRank0 = isUnsigned && rank == 0
        let divModCmpPrefix = useUnsignedRank0 ? "u" : prefix
        let divModOp = useUnsignedRank0 ? "rem" : "mod" // unsigned uses urem (LLVM), signed uses mod
        // For == / != on non-primitive reference types, use structural equality
        let needsStructuralEquality = (op == .equal || op == .notEqual) && rank == 0
            && (isReferenceType(lhs, arena: arena, types: types) || isReferenceType(rhs, arena: arena, types: types))
        let callee: InternedString = switch op {
        case .add: interner.intern("kk_op_\(prefix)add")
        case .subtract: interner.intern("kk_op_\(prefix)sub")
        case .multiply: interner.intern("kk_op_\(prefix)mul")
        case .divide: interner.intern("kk_op_\(divModCmpPrefix)div")
        case .modulo: interner.intern("kk_op_\(divModCmpPrefix)\(divModOp)")
        case .equal: interner.intern(needsStructuralEquality ? "kk_structural_eq" : "kk_op_\(prefix)eq")
        case .notEqual: interner.intern(needsStructuralEquality ? "kk_structural_ne" : "kk_op_\(prefix)ne")
        case .lessThan: interner.intern("kk_op_\(divModCmpPrefix)lt")
        case .lessOrEqual: interner.intern("kk_op_\(divModCmpPrefix)le")
        case .greaterThan: interner.intern("kk_op_\(divModCmpPrefix)gt")
        case .greaterOrEqual: interner.intern("kk_op_\(divModCmpPrefix)ge")
        case .logicalAnd: interner.intern("kk_op_and")
        case .logicalOr: interner.intern("kk_op_or")
        }
        newBody.append(.call(symbol: nil, callee: callee, arguments: [effectiveLhs, effectiveRhs], result: result, canThrow: false, thrownResult: nil))
    }

    /// Returns true when the expression is a reference type that requires structural
    /// equality (e.g. List, Set, Map, String, Any, class instances).
    /// String is a compiler aggregate, so pointer comparison is insufficient.
    private func isReferenceType(_ exprID: KIRExprID, arena: KIRArena, types: TypeSystem?) -> Bool {
        guard let types, let typeID = arena.exprType(exprID) else { return false }
        switch types.kind(of: typeID) {
        case .stringStruct:
            return true
        case .primitive:
            return false
        case .classType, .any:
            return true
        case .typeParam:
            // Type parameters have an Any? upper bound by default, so equality on them
            // must use structural equality (e.g. String values in a generic Map function).
            return true
        default:
            return false
        }
    }

    /// STDLIB-CORO-077: Detect CoroutineContext-family types for `+` operator rewriting.
    private func isCoroutineContextType(_ exprID: KIRExprID, arena: KIRArena, types: TypeSystem?, interner: StringInterner) -> Bool {
        guard let types, let typeID = arena.exprType(exprID) else { return false }
        switch types.kind(of: typeID) {
        case let .classType(ct):
            guard let sym = types.symbolTable?.symbol(ct.classSymbol) else { return false }
            let coroutinePackages = [
                [interner.intern("kotlin"), interner.intern("coroutines")],
                [interner.intern("kotlinx"), interner.intern("coroutines")],
            ]
            guard coroutinePackages.contains(where: { sym.fqName.starts(with: $0) }) else {
                return false
            }
            let name = interner.resolve(sym.name)
            return name == "CoroutineContext" || name == "CoroutineDispatcher"
                || name == "CoroutineName" || name == "CoroutineExceptionHandler"
        default:
            return false
        }
    }

    private func primitiveRank(for exprID: KIRExprID, arena: KIRArena, types: TypeSystem?) -> Int {
        guard let types, let typeID = arena.exprType(exprID) else { return 0 }
        switch types.kind(of: typeID) {
        case .primitive(.double, _): return 2
        case .primitive(.float, _): return 1
        default: return 0
        }
    }

    private func isUnsignedOperand(_ exprID: KIRExprID, arena: KIRArena, types: TypeSystem?) -> Bool {
        guard let types, let typeID = arena.exprType(exprID) else { return false }
        switch types.kind(of: typeID) {
        case .primitive(.uint, _), .primitive(.ulong, _), .primitive(.ubyte, _), .primitive(.ushort, _):
            return true
        default:
            return false
        }
    }

    private func conversionCallee(fromRank: Int, toRank: Int, interner: StringInterner) -> InternedString {
        if toRank == 1 {
            return interner.intern("kk_int_to_float_bits")
        }
        if fromRank == 1 {
            return interner.intern("__kk_float_to_double_bits")
        }
        return interner.intern("kk_int_to_double_bits")
    }

}
