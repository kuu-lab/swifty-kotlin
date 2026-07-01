
extension CallLowerer {
    func lowerComparisonSpecialCallExpr(
        _ exprID: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        let callBinding = sema.bindings.callBindings[exprID]
        guard let chosenCallee = callBinding?.chosenCallee,
              chosenCallee != .invalid,
              let chosenSymbol = sema.symbols.symbol(chosenCallee)
        else {
            return nil
        }

        let isStdlibComparisonsFn = chosenSymbol.fqName.count >= 3
            && chosenSymbol.fqName[0] == interner.intern("kotlin")
            && chosenSymbol.fqName[1] == interner.intern("comparisons")
        let chosenCalleeName = interner.resolve(chosenSymbol.name)
        let isStdlibMaxOfCall = isStdlibComparisonsFn && chosenCalleeName == "maxOf"
        let isStdlibMinOfCall = isStdlibComparisonsFn && chosenCalleeName == "minOf"

        guard let specialKind = sema.bindings.stdlibSpecialCallKind(for: exprID) else {
            if isStdlibMaxOfCall || isStdlibMinOfCall {
                return lowerRemainingComparisonCallExpr(
                    exprID,
                    args: args,
                    callBinding: callBinding,
                    chosenCallee: chosenCallee,
                    isMin: isStdlibMinOfCall,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            }
            return nil
        }

        let comparisonOp: KIRBinaryOp
        // Float/Double route through the kk_min_float/kk_max_float/kk_min_double/
        // kk_max_double runtime helpers instead of a plain `<`/`>` comparison so
        // that NaN propagation and signed-zero ordering match Kotlin's actual
        // minOf/maxOf semantics (see RuntimeNumericCompat.swift for details).
        let floatingPointRuntimeCallee: String?
        switch specialKind {
        case .maxOfInt, .maxOfLong:
            guard args.count == 2 else { return nil }
            comparisonOp = .greaterThan
            floatingPointRuntimeCallee = nil
        case .maxOfDouble:
            guard args.count == 2 else { return nil }
            comparisonOp = .greaterThan
            floatingPointRuntimeCallee = "kk_max_double"
        case .maxOfFloat:
            guard args.count == 2 else { return nil }
            comparisonOp = .greaterThan
            floatingPointRuntimeCallee = "kk_max_float"
        case .minOfInt, .minOfLong:
            guard args.count == 2 else { return nil }
            comparisonOp = .lessThan
            floatingPointRuntimeCallee = nil
        case .minOfDouble:
            guard args.count == 2 else { return nil }
            comparisonOp = .lessThan
            floatingPointRuntimeCallee = "kk_min_double"
        case .minOfFloat:
            guard args.count == 2 else { return nil }
            comparisonOp = .lessThan
            floatingPointRuntimeCallee = "kk_min_float"
        case .maxOfInt3, .maxOfLong3:
            guard args.count == 3 else { return nil }
            comparisonOp = .greaterThan
            floatingPointRuntimeCallee = nil
        case .maxOfDouble3:
            guard args.count == 3 else { return nil }
            comparisonOp = .greaterThan
            floatingPointRuntimeCallee = "kk_max_double"
        case .maxOfFloat3:
            guard args.count == 3 else { return nil }
            comparisonOp = .greaterThan
            floatingPointRuntimeCallee = "kk_max_float"
        case .minOfInt3, .minOfLong3:
            guard args.count == 3 else { return nil }
            comparisonOp = .lessThan
            floatingPointRuntimeCallee = nil
        case .minOfDouble3:
            guard args.count == 3 else { return nil }
            comparisonOp = .lessThan
            floatingPointRuntimeCallee = "kk_min_double"
        case .minOfFloat3:
            guard args.count == 3 else { return nil }
            comparisonOp = .lessThan
            floatingPointRuntimeCallee = "kk_min_float"
        default:
            return nil
        }

        let boolType = sema.types.booleanType
        let resultType = sema.bindings.exprType(for: exprID)
            ?? sema.bindings.exprType(for: args[0].expr)
            ?? sema.types.intType

        if args.count == 2 {
            return lowerTwoArgComparison(
                args: args,
                comparisonOp: comparisonOp,
                floatingPointRuntimeCallee: floatingPointRuntimeCallee,
                boolType: boolType,
                resultType: resultType,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        } else {
            return lowerThreeArgComparison(
                args: args,
                comparisonOp: comparisonOp,
                floatingPointRuntimeCallee: floatingPointRuntimeCallee,
                boolType: boolType,
                resultType: resultType,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }
    }

    /// Lowers the vararg / generic `maxOf` and `minOf` overloads that are not
    /// covered by the fixed-arity primitive special-call kinds. `isMin` selects
    /// the comparison direction (`<` for `minOf`, `>` for `maxOf`).
    private func lowerRemainingComparisonCallExpr(
        _ exprID: ExprID,
        args: [CallArgument],
        callBinding: CallBinding?,
        chosenCallee: SymbolID,
        isMin: Bool,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard let signature = sema.symbols.functionSignature(for: chosenCallee),
              !args.isEmpty
        else {
            return nil
        }

        let resultType = sema.bindings.exprType(for: exprID)
            ?? sema.bindings.exprType(for: args[0].expr)
            ?? sema.types.anyType
        let boolType = sema.types.booleanType
        let intType = sema.types.intType
        // The element comparison: pick the candidate when it is strictly less
        // (minOf) / greater (maxOf) than the running result.
        let primitiveOp: KIRBinaryOp = isMin ? .lessThan : .greaterThan

        let isGenericComparable = signature.typeParameterUpperBoundsList.contains(where: { upperBounds in
            upperBounds.contains(where: { bound in
                isComparableUpperBound(bound, sema: sema)
            })
        })
        let isComparatorOverload = !isGenericComparable
            && signature.parameterTypes.contains(where: { paramType in
                isComparatorType(paramType, sema: sema, interner: interner)
            })
        let isPrimitiveOverload = !isGenericComparable
            && !isComparatorOverload
            && signature.typeParameterSymbols.isEmpty
            && signature.parameterTypes.allSatisfy({ isPrimitiveComparisonType($0, sema: sema) })

        guard isGenericComparable || isComparatorOverload || isPrimitiveOverload else {
            return nil
        }

        let loweredArgIDs = args.map { argument in
            driver.lowerExpr(
                argument.expr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }

        var comparisonArgIndices = Array(args.indices)
        let zeroExpr = arena.appendExpr(.intLiteral(0), type: intType)
        instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
        let falseExpr = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseExpr, value: .boolLiteral(false)))

        func selectCandidate(lhs: KIRExprID, rhs: KIRExprID, conditionExpr: KIRExprID) -> KIRExprID {
            let useRightLabel = driver.ctx.makeLoopLabel()
            let endLabel = driver.ctx.makeLoopLabel()
            let resultExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)

            instructions.append(.jumpIfEqual(lhs: conditionExpr, rhs: falseExpr, target: useRightLabel))
            instructions.append(.copy(from: lhs, to: resultExpr))
            instructions.append(.jump(endLabel))
            instructions.append(.label(useRightLabel))
            instructions.append(.copy(from: rhs, to: resultExpr))
            instructions.append(.label(endLabel))
            return resultExpr
        }

        enum ComparisonStrategy {
            case primitive
            /// Float/Double: dispatches to kk_min_float/kk_max_float/kk_min_double/
            /// kk_max_double instead of a plain `<`/`>` so NaN propagation and
            /// signed-zero ordering match Kotlin's minOf/maxOf (see lowerTwoArgComparison).
            case floatingPoint(runtimeCallee: InternedString)
            case genericComparable
            case comparator(comparatorArgIndex: Int, trampolineCallee: InternedString)
        }

        let comparisonStrategy: ComparisonStrategy
        if isPrimitiveOverload,
           let firstParamType = signature.parameterTypes.first,
           let floatingPointCallee = floatingPointMinMaxRuntimeCallee(for: firstParamType, sema: sema, isMin: isMin)
        {
            comparisonStrategy = .floatingPoint(runtimeCallee: interner.intern(floatingPointCallee))
        } else if isPrimitiveOverload {
            comparisonStrategy = .primitive
        } else if isGenericComparable {
            comparisonStrategy = .genericComparable
        } else {
            guard let callBinding else {
                return nil
            }
            guard let comparatorParamIndex = signature.parameterTypes.indices.last else {
                return nil
            }
            let comparatorArgIndex = callBinding.parameterMapping.first(where: { $0.value == comparatorParamIndex })?.key
                ?? (args.count - 1)
            guard comparatorArgIndex >= 0, comparatorArgIndex < loweredArgIDs.count else {
                return nil
            }
            guard let trampolineName = comparatorTrampolineName(
                comparatorExprID: args[comparatorArgIndex].expr,
                loweredComparatorID: loweredArgIDs[comparatorArgIndex],
                sema: sema,
                interner: interner,
                instructions: instructions
            ) else {
                return nil
            }
            let trampolineCallee = interner.intern(trampolineName)
            comparisonArgIndices = args.indices.filter { $0 != comparatorArgIndex }
            comparisonStrategy = .comparator(
                comparatorArgIndex: comparatorArgIndex,
                trampolineCallee: trampolineCallee
            )
        }

        guard !comparisonArgIndices.isEmpty else {
            return nil
        }

        var currentExpr = loweredArgIDs[comparisonArgIndices[0]]
        guard comparisonArgIndices.count > 1 else {
            return currentExpr
        }

        for argIndex in comparisonArgIndices.dropFirst() {
            let candidateExpr = loweredArgIDs[argIndex]
            if case let .floatingPoint(runtimeCallee) = comparisonStrategy {
                let newCurrent = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
                instructions.append(.call(
                    symbol: nil,
                    callee: runtimeCallee,
                    arguments: [candidateExpr, currentExpr],
                    result: newCurrent,
                    canThrow: false,
                    thrownResult: nil
                ))
                currentExpr = newCurrent
                continue
            }
            let conditionExpr: KIRExprID
            switch comparisonStrategy {
            case .primitive:
                conditionExpr = arena.appendExpr(
                    .temporary(Int32(arena.expressions.count)),
                    type: boolType
                )
                instructions.append(.binary(op: primitiveOp, lhs: candidateExpr, rhs: currentExpr, result: conditionExpr))
            case .floatingPoint:
                fatalError("unreachable: floatingPoint handled above via early continue")
            case .genericComparable:
                let compareResultExpr = arena.appendExpr(
                    .temporary(Int32(arena.expressions.count)),
                    type: intType
                )
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_compare_any"),
                    arguments: [candidateExpr, currentExpr],
                    result: compareResultExpr,
                    canThrow: false,
                    thrownResult: nil
                ))
                conditionExpr = arena.appendExpr(
                    .temporary(Int32(arena.expressions.count)),
                    type: boolType
                )
                instructions.append(.binary(
                    op: primitiveOp,
                    lhs: compareResultExpr,
                    rhs: zeroExpr,
                    result: conditionExpr
                ))
            case let .comparator(comparatorArgIndex, trampolineCallee):
                let compareResultExpr = arena.appendExpr(
                    .temporary(Int32(arena.expressions.count)),
                    type: intType
                )
                instructions.append(.call(
                    symbol: nil,
                    callee: trampolineCallee,
                    arguments: [loweredArgIDs[comparatorArgIndex], candidateExpr, currentExpr],
                    result: compareResultExpr,
                    canThrow: true,
                    thrownResult: nil
                ))
                conditionExpr = arena.appendExpr(
                    .temporary(Int32(arena.expressions.count)),
                    type: boolType
                )
                instructions.append(.binary(
                    op: primitiveOp,
                    lhs: compareResultExpr,
                    rhs: zeroExpr,
                    result: conditionExpr
                ))
            }
            currentExpr = selectCandidate(lhs: candidateExpr, rhs: currentExpr, conditionExpr: conditionExpr)
        }
        return currentExpr
    }

    private func isComparableUpperBound(
        _ type: TypeID,
        sema: SemaModule
    ) -> Bool {
        guard let comparableSymbol = sema.types.comparableInterfaceSymbol else {
            return false
        }
        switch sema.types.kind(of: type) {
        case let .classType(classType):
            return classType.classSymbol == comparableSymbol
        default:
            return false
        }
    }

    private func isComparatorType(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard case let .classType(classType) = sema.types.kind(of: type),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return interner.resolve(symbol.name) == "Comparator"
    }

    /// True for the numeric primitive types whose ordering can be lowered to a
    /// direct `<` / `>` comparison: the signed primitives (Int/Long/Float/Double,
    /// which Byte/Short widen into) plus the unsigned primitives. Used by the
    /// vararg `minOf` / `maxOf` lowering to fold the arguments inline.
    private func isPrimitiveComparisonType(
        _ type: TypeID,
        sema: SemaModule
    ) -> Bool {
        switch sema.types.kind(of: type) {
        case .primitive(.int, .nonNull),
             .primitive(.long, .nonNull),
             .primitive(.float, .nonNull),
             .primitive(.double, .nonNull),
             .primitive(.ubyte, .nonNull),
             .primitive(.ushort, .nonNull),
             .primitive(.uint, .nonNull),
             .primitive(.ulong, .nonNull):
            return true
        default:
            return false
        }
    }

    /// Returns the NaN/signed-zero-aware runtime helper for a Float/Double
    /// `minOf`/`maxOf` element type, or nil for other primitive types (Int,
    /// Long, unsigned types) which have no NaN/signed-zero distinction and
    /// can keep using a plain `<`/`>` comparison.
    private func floatingPointMinMaxRuntimeCallee(
        for type: TypeID,
        sema: SemaModule,
        isMin: Bool
    ) -> String? {
        switch sema.types.kind(of: type) {
        case .primitive(.float, .nonNull):
            return isMin ? "kk_min_float" : "kk_max_float"
        case .primitive(.double, .nonNull):
            return isMin ? "kk_min_double" : "kk_max_double"
        default:
            return nil
        }
    }

    /// Lowers maxOf(a, b) / minOf(a, b) as: if (a > b) a else b
    /// When `floatingPointRuntimeCallee` is set (Float/Double overloads), the
    /// comparison instead dispatches to a `kk_min_float`/`kk_max_float`/
    /// `kk_min_double`/`kk_max_double` runtime call, which implements NaN
    /// propagation and signed-zero ordering that a plain `<`/`>` cannot.
    private func lowerTwoArgComparison(
        args: [CallArgument],
        comparisonOp: KIRBinaryOp,
        floatingPointRuntimeCallee: String?,
        boolType: TypeID,
        resultType: TypeID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let lhsExpr = driver.lowerExpr(
            args[0].expr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let rhsExpr = driver.lowerExpr(
            args[1].expr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        if let floatingPointRuntimeCallee {
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern(floatingPointRuntimeCallee),
                arguments: [lhsExpr, rhsExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        let falseExpr = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseExpr, value: .boolLiteral(false)))

        let conditionExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boolType)
        instructions.append(.binary(
            op: comparisonOp,
            lhs: lhsExpr,
            rhs: rhsExpr,
            result: conditionExpr
        ))

        let useRightLabel = driver.ctx.makeLoopLabel()
        let endLabel = driver.ctx.makeLoopLabel()
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)

        instructions.append(.jumpIfEqual(lhs: conditionExpr, rhs: falseExpr, target: useRightLabel))
        instructions.append(.copy(from: lhsExpr, to: result))
        instructions.append(.jump(endLabel))
        instructions.append(.label(useRightLabel))
        instructions.append(.copy(from: rhsExpr, to: result))
        instructions.append(.label(endLabel))
        return result
    }

    /// Lowers maxOf(a, b, c) / minOf(a, b, c) as: val tmp = maxOf(a, b); maxOf(tmp, c)
    /// When `floatingPointRuntimeCallee` is set (Float/Double overloads), both
    /// steps dispatch to the runtime min/max helper instead of a plain `<`/`>`
    /// comparison; see `lowerTwoArgComparison` for why.
    private func lowerThreeArgComparison(
        args: [CallArgument],
        comparisonOp: KIRBinaryOp,
        floatingPointRuntimeCallee: String?,
        boolType: TypeID,
        resultType: TypeID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let aExpr = driver.lowerExpr(
            args[0].expr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let bExpr = driver.lowerExpr(
            args[1].expr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let cExpr = driver.lowerExpr(
            args[2].expr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        if let floatingPointRuntimeCallee {
            let calleeID = interner.intern(floatingPointRuntimeCallee)
            let tmp = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: calleeID,
                arguments: [aExpr, bExpr],
                result: tmp,
                canThrow: false,
                thrownResult: nil
            ))
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: calleeID,
                arguments: [tmp, cExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        let falseExpr = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseExpr, value: .boolLiteral(false)))

        let cond1 = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boolType)
        instructions.append(.binary(op: comparisonOp, lhs: aExpr, rhs: bExpr, result: cond1))

        let useBLabel = driver.ctx.makeLoopLabel()
        let afterFirstLabel = driver.ctx.makeLoopLabel()
        let tmp = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)

        instructions.append(.jumpIfEqual(lhs: cond1, rhs: falseExpr, target: useBLabel))
        instructions.append(.copy(from: aExpr, to: tmp))
        instructions.append(.jump(afterFirstLabel))
        instructions.append(.label(useBLabel))
        instructions.append(.copy(from: bExpr, to: tmp))
        instructions.append(.label(afterFirstLabel))

        let cond2 = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boolType)
        instructions.append(.binary(op: comparisonOp, lhs: tmp, rhs: cExpr, result: cond2))

        let useCLabel = driver.ctx.makeLoopLabel()
        let endLabel = driver.ctx.makeLoopLabel()
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)

        instructions.append(.jumpIfEqual(lhs: cond2, rhs: falseExpr, target: useCLabel))
        instructions.append(.copy(from: tmp, to: result))
        instructions.append(.jump(endLabel))
        instructions.append(.label(useCLabel))
        instructions.append(.copy(from: cExpr, to: result))
        instructions.append(.label(endLabel))
        return result
    }
}
