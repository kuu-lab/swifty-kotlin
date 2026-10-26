
final class OperatorLoweringPass: LoweringPass, ParallelLoweringPass {
    static let name = "OperatorLowering"
    static let requiredStage: KIRStage = .desugared
    static let producedStage: KIRStage = .desugared

    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool {
        _ = ctx
        module.ensureFeaturesScanned()
        return !module.features.isDisjoint(with: [.hasBinaryOp, .hasUnaryOp, .hasNullAssert])
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
        module.arena.transformFunctions { function in
            var updated = function
            var newBody = KIRLoweringEmitContext()
            newBody.instructions.reserveCapacity(function.body.count)
            for (index, instruction) in function.body.enumerated() {
                newBody.currentSourceRange = index < function.instructionLocations.count
                    ? function.instructionLocations[index]
                    : nil
                switch instruction {
                case let .binary(op, lhs, rhs, result):
                    lowerBinaryInstruction(
                        op: op, lhs: lhs, rhs: rhs, result: result,
                        arena: module.arena, interner: ctx.interner,
                        types: ctx.sema?.types, symbols: ctx.sema?.symbols, newBody: &newBody
                    )
                case let .unary(op, operand, result):
                    let callee: InternedString = switch op {
                    case .not: ctx.interner.intern("kk_op_not")
                    case .unaryPlus: ctx.interner.intern("kk_op_uplus")
                    case .unaryMinus: ctx.interner.intern("kk_op_uminus")
                    }
                    newBody.append(.call(callee: callee, arguments: [operand], result: result, canThrow: false))
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
        newBody: inout KIRLoweringEmitContext
    ) {
        let notNullResult = arena.appendTemporary(type: arena.exprType(result))
        newBody.append(
            .call(callee: interner.intern("kk_op_notnull"), arguments: [operand], result: notNullResult, canThrow: true)
        )

        guard let types, let resultType = arena.exprType(result) else {
            newBody.append(.copy(from: notNullResult, to: result))
            return
        }

        if let unboxCallee = unboxCallee(for: types.kind(of: resultType), interner: interner) {
            newBody.append(
                .call(callee: unboxCallee, arguments: [notNullResult], result: result, canThrow: false)
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
        symbols: SymbolTable?,
        newBody: inout KIRLoweringEmitContext
    ) {
        // Preserve source overrides for CoroutineContext's + operator.
        if op == .add, isCoroutineContextType(lhs, arena: arena, types: types, interner: interner)
            || isCoroutineContextType(rhs, arena: arena, types: types, interner: interner)
        {
            let callee = interner.intern("__kk_context_plus_dispatch")
            newBody.append(.call(callee: callee, arguments: [lhs, rhs], result: result, canThrow: true))
            return
        }

        // `P == null` / `P != null` where the non-literal side is statically
        // non-null is a tautology the JVM answers without a runtime check
        // (e.g. a `Long?` local smart-cast to `Long` after `v = Long.MIN_VALUE`,
        // or a plain `x != null` on a non-null primitive). Folding is required
        // for correctness, not just an optimization: unboxing the operand
        // yields raw bits that can equal the null sentinel (Long.MIN_VALUE,
        // -0.0), which a raw kk_op_eq/ne would then misread as `null`.
        // Nullable/platform operands are excluded — those may genuinely hold
        // null and take the sentinel-safe path below.
        if op == .equal || op == .notEqual {
            func isNullLiteral(_ exprID: KIRExprID) -> Bool {
                arena.expr(exprID) == .null
            }
            func isNonNullPrimitiveLike(_ exprID: KIRExprID) -> Bool {
                guard let types, let typeID = arena.exprType(exprID) else { return false }
                let kind = resolveValueClassKind(types.kind(of: typeID), types: types, symbols: symbols)
                if case .primitive(_, .nonNull) = kind { return true }
                return false
            }
            let lhsIsNull = isNullLiteral(lhs)
            let rhsIsNull = isNullLiteral(rhs)
            if lhsIsNull != rhsIsNull,
               isNonNullPrimitiveLike(lhsIsNull ? rhs : lhs)
            {
                newBody.append(.constValue(result: result, value: .boolLiteral(op == .notEqual)))
                return
            }
        }

        // A nullable `Long?`/`ULong?`/`Double?`/`Float?` operand in `==`/`!=`
        // needs a null check that does not guess from the raw bits: those are
        // the only primitives whose full raw (unboxed, never-boxed) value
        // range coincides with the runtime null sentinel (`Long.MIN_VALUE`,
        // `ULong` `2^63`, `-0.0`'s bit pattern), so kk_structural_eq/ne's
        // "raw value equals the sentinel implies null" heuristic cannot tell
        // a genuine null apart from a genuine value that happens to share
        // that bit pattern. kk_nullable_primitive_eq/ne instead determines
        // nullness from each statically-nullable operand's own boxing state
        // (a nullable primitive is null iff it is not a registered boxed
        // handle — see needsBoxingForCopy), which this pass can resolve now
        // from static types but a pure runtime function operating on raw
        // Ints alone cannot recover later. Int?/Boolean?/Char?/UInt?/UByte?/
        // UShort? don't have this ambiguity (their raw range never reaches
        // the sentinel), so they keep using the cheaper kk_structural_eq/ne
        // below via needsStructuralEquality.
        if op == .equal || op == .notEqual {
            let sentinelCollidingKinds: Set<PrimitiveType> = [.long, .ulong, .double, .float]
            let lhsNullableKind = nullablePrimitiveKind(lhs, arena: arena, types: types, symbols: symbols)
            let rhsNullableKind = nullablePrimitiveKind(rhs, arena: arena, types: types, symbols: symbols)
            let lhsNeedsSentinelSafeCompare = (lhsNullableKind.map(sentinelCollidingKinds.contains) ?? false)
                || isNullableSentinelCollidingValueClass(lhs, arena: arena, types: types, symbols: symbols)
            let rhsNeedsSentinelSafeCompare = (rhsNullableKind.map(sentinelCollidingKinds.contains) ?? false)
                || isNullableSentinelCollidingValueClass(rhs, arena: arena, types: types, symbols: symbols)
            if lhsNeedsSentinelSafeCompare || rhsNeedsSentinelSafeCompare {
                let nullableSide: KIRExprID
                let peerSide: KIRExprID
                // peerIsNullable must mean "the peer's static type admits null
                // at runtime" — not "the peer is a nullable primitive". A
                // `null` literal is `Nothing?`, and the peer can also be
                // `Any?`/a nullable reference/`T?`; all of those hold either
                // the null sentinel or a registered heap handle, so the
                // runtime may check their nullness through the object-pointer
                // registry just like the nullable side. Restricting the flag
                // to nullable primitives would mark a `null` literal
                // "provably non-null" and turn `null == null` into false.
                let peerIsNullable: Bool
                if lhsNeedsSentinelSafeCompare {
                    nullableSide = lhs
                    peerSide = rhs
                    peerIsNullable = isNullableOrPlatform(rhs, arena: arena, types: types, symbols: symbols)
                } else {
                    nullableSide = rhs
                    peerSide = lhs
                    peerIsNullable = isNullableOrPlatform(lhs, arena: arena, types: types, symbols: symbols)
                }
                let intType = types?.make(.primitive(.int, .nonNull))
                // The flag encodes the peer's nature, not just nullability:
                //   0 — provably non-null, non-floating peer: structural/value
                //       compare (runtimeNonNullValuesEqual).
                //   1 — peer may hold null and is not a floating-point
                //       primitive: sentinel-check then structural compare.
                //   2/3 — provably non-null raw Double/Float word.
                //   4/5 — a Double?/Float? slot (sentinel still means null).
                // For 2-5 Kotlin `==`/`!=` is IEEE-754 once nullness is ruled
                // out (`-0.0 == 0.0`, `NaN != NaN`) — not the boxed `equals`
                // bit-pattern compare runtimeNonNullValuesEqual applies.
                let flagValue: Int64 = {
                    if peerIsNullable {
                        switch nullablePrimitiveKind(peerSide, arena: arena, types: types, symbols: symbols) {
                        case .double: return 4
                        case .float: return 5
                        default: return 1
                        }
                    }
                    switch nonNullPrimitiveKind(peerSide, arena: arena, types: types, symbols: symbols) {
                    case .double: return 2
                    case .float: return 3
                    default: return 0
                    }
                }()
                let flagExpr = arena.appendExpr(.intLiteral(flagValue), type: intType)
                newBody.append(.constValue(result: flagExpr, value: .intLiteral(flagValue)))
                let callee = interner.intern(op == .equal ? "kk_nullable_primitive_eq" : "kk_nullable_primitive_ne")
                newBody.append(.call(callee: callee, arguments: [nullableSide, peerSide, flagExpr], result: result, canThrow: false))
                return
            }
        }

        // For == / != where either operand is a reference type (Any, class
        // type, type param, String) or a remaining nullable primitive
        // (`Boolean?`/`Int?`/`Char?`/...), equality must go through
        // Any.equals / structural comparison, never the numeric fast path
        // below -- even when the *other* operand is statically Double/Float
        // (e.g. `anyValue == 3.0`). Computing this before the rank-based
        // widening, and forcing rank to 0 when it applies, keeps the
        // reference-typed operand's raw representation (a boxed pointer, or
        // the null sentinel) from being reinterpreted as numeric bits.
        // Nullable primitives also cannot use kk_op_eq/ne: ABI unbox of a
        // null sentinel maps to 0 and would collapse `null == false`.
        let needsStructuralEquality = (op == .equal || op == .notEqual)
            && (isReferenceType(lhs, arena: arena, types: types, symbols: symbols)
                || isReferenceType(rhs, arena: arena, types: types, symbols: symbols)
                || isNullablePrimitive(lhs, arena: arena, types: types) || isNullablePrimitive(rhs, arena: arena, types: types))

        var effectiveLhs = lhs
        var effectiveRhs = rhs
        if needsStructuralEquality {
            effectiveLhs = boxFloatingOperandForReferenceEquality(
                lhs, peer: rhs, arena: arena, interner: interner,
                types: types, symbols: symbols, newBody: &newBody
            )
            effectiveRhs = boxFloatingOperandForReferenceEquality(
                rhs, peer: lhs, arena: arena, interner: interner,
                types: types, symbols: symbols, newBody: &newBody
            )
        }

        let usePrimitiveUpperBounds = [.add, .subtract, .multiply, .divide, .modulo,
                                       .equal, .notEqual,
                                       .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual].contains(op)
        let lhsRank = needsStructuralEquality ? 0 : primitiveRank(
            for: lhs, arena: arena, types: types, symbols: symbols,
            resolveTypeParameterUpperBound: usePrimitiveUpperBounds
        )
        let rhsRank = needsStructuralEquality ? 0 : primitiveRank(
            for: rhs, arena: arena, types: types, symbols: symbols,
            resolveTypeParameterUpperBound: usePrimitiveUpperBounds
        )
        let rank = max(lhsRank, rhsRank)
        let isUnsigned = isUnsignedOperand(lhs, arena: arena, types: types)
            || isUnsignedOperand(rhs, arena: arena, types: types)
        let prefix = switch rank {
        case 2: "d"
        case 1: "f"
        default: ""
        }
        if rank > 0 {
            let convertedType = widenedPrimitiveType(rank: rank, types: types)
            if lhsRank < rank {
                let convCallee = conversionCallee(fromRank: lhsRank, toRank: rank, interner: interner)
                let converted = arena.appendTemporary(type: convertedType)
                emitNonThrowingCall(callee: convCallee, arg: lhs, result: converted, into: &newBody)
                effectiveLhs = converted
            }
            if rhsRank < rank {
                let convCallee = conversionCallee(fromRank: rhsRank, toRank: rank, interner: interner)
                let converted = arena.appendTemporary(type: convertedType)
                emitNonThrowingCall(callee: convCallee, arg: rhs, result: converted, into: &newBody)
                effectiveRhs = converted
            }
        }
        // For unsigned int/long: add/sub/mul/eq/ne use same callees; div/rem/lt/le/gt/ge use u-prefix
        let useUnsignedRank0 = isUnsigned && rank == 0
        let divModCmpPrefix = useUnsignedRank0 ? "u" : prefix
        let divModOp = useUnsignedRank0 ? "rem" : "mod" // unsigned uses urem (LLVM), signed uses mod
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
        newBody.append(.call(callee: callee, arguments: [effectiveLhs, effectiveRhs], result: result, canThrow: false))
    }

    /// A raw Double/Float word has no runtime type tag. Box it before comparing
    /// against a reference value so structural equality cannot mistake the
    /// floating-point bits for an equal boxed integer value.
    private func boxFloatingOperandForReferenceEquality(
        _ operand: KIRExprID,
        peer: KIRExprID,
        arena: KIRArena,
        interner: StringInterner,
        types: TypeSystem?,
        symbols: SymbolTable?,
        newBody: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        guard let types,
              isReferenceType(peer, arena: arena, types: types, symbols: symbols),
              let typeID = arena.exprType(operand),
              case let .primitive(primitive, .nonNull) = types.kind(of: typeID),
              primitive == .double || primitive == .float,
              let boxCallee = BoxingCalleeTable(interner: interner).boxCallee(
                  for: types.kind(of: typeID), requireNonNull: true, preferStaticPrimitive: true
              )
        else {
            return operand
        }

        let boxed = arena.appendTemporary(type: types.nullableAnyType)
        newBody.append(.call(callee: boxCallee, arguments: [operand], result: boxed, canThrow: false))
        return boxed
    }

    /// Returns true when the expression's static type is a nullable primitive
    /// (`Boolean?`, `Int?`, `Char?`, ...). Its raw representation may be the
    /// runtime null sentinel or a boxed pointer, neither of which kk_op_eq/ne
    /// can compare directly against a non-null peer's raw value.
    private func isNullablePrimitive(_ exprID: KIRExprID, arena: KIRArena, types: TypeSystem?) -> Bool {
        nullablePrimitiveKind(exprID, arena: arena, types: types) != nil
    }

    private func nullablePrimitiveKind(
        _ exprID: KIRExprID,
        arena: KIRArena,
        types: TypeSystem?,
        symbols: SymbolTable? = nil
    ) -> PrimitiveType? {
        guard let types, let typeID = arena.exprType(exprID) else { return nil }
        let resolvedType = symbols.flatMap {
            resolvePrimitiveValueUpperBound(of: typeID, types: types, symbols: $0)
        } ?? typeID
        if case let .primitive(primitiveType, .nullable) = types.kind(of: resolvedType) {
            return primitiveType
        }
        return nil
    }

    private func isNullableSentinelCollidingValueClass(
        _ exprID: KIRExprID, arena: KIRArena, types: TypeSystem?, symbols: SymbolTable?
    ) -> Bool {
        guard let types, let typeID = arena.exprType(exprID),
              case let .classType(classType) = types.kind(of: typeID),
              classType.nullability != .nonNull,
              symbols?.symbol(classType.classSymbol)?.flags.contains(.valueType) == true,
              case let .primitive(primitive, .nonNull) = resolveValueClassKind(
                  types.kind(of: types.makeNonNullable(typeID)), types: types, symbols: symbols
              )
        else { return false }
        return primitive.rawValueCollidesWithNullSentinel
    }

    private func nonNullPrimitiveKind(
        _ exprID: KIRExprID,
        arena: KIRArena,
        types: TypeSystem?,
        symbols: SymbolTable?
    ) -> PrimitiveType? {
        guard let types, let typeID = arena.exprType(exprID) else { return nil }
        let resolvedType = symbols.flatMap {
            resolvePrimitiveValueUpperBound(of: typeID, types: types, symbols: $0)
        } ?? typeID
        if case let .primitive(primitiveType, .nonNull) = types.kind(of: resolvedType) {
            return primitiveType
        }
        return nil
    }

    /// True when the expression's static type may hold null at runtime
    /// (`.nullable` or `.platformType`). Any such value is represented as
    /// either the null sentinel or a registered heap handle, so
    /// `kk_nullable_primitive_eq/ne` can determine its nullness via the
    /// object-pointer registry regardless of the specific type kind
    /// (`Nothing?` null literals, `Any?`, nullable references, `T?`).
    private func isNullableOrPlatform(
        _ exprID: KIRExprID,
        arena: KIRArena,
        types: TypeSystem?,
        symbols: SymbolTable?
    ) -> Bool {
        guard let types, let typeID = arena.exprType(exprID) else { return false }
        let resolvedType = symbols.flatMap {
            resolvePrimitiveValueUpperBound(of: typeID, types: types, symbols: $0)
        } ?? typeID
        return types.nullability(of: resolvedType) != .nonNull
    }

    /// String is a compiler aggregate, so pointer comparison is insufficient.
    private func isReferenceType(
        _ exprID: KIRExprID,
        arena: KIRArena,
        types: TypeSystem?,
        symbols: SymbolTable?
    ) -> Bool {
        guard let types, let typeID = arena.exprType(exprID) else { return false }
        switch types.kind(of: typeID) {
        case .stringStruct:
            return true
        case .primitive:
            return false
        case .classType, .any, .functionType:
            return true
        case .typeParam:
            if let symbols,
               let upperBound = resolvePrimitiveArithmeticUpperBound(
                   of: typeID, types: types, symbols: symbols
               ),
               case let .primitive(primitive, .nonNull) = types.kind(of: upperBound),
               primitive == .float || primitive == .double
            {
                return false
            }
            // Type parameters have an Any? upper bound by default, so equality on them
            // must use structural equality (e.g. String values in a generic Map function).
            // A non-null floating-point upper bound is an exception: it uses scalar
            // IEEE equality rather than boxed `Double.equals`/`Float.equals`.
            return true
        default:
            return false
        }
    }

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

    private func primitiveRank(
        for exprID: KIRExprID,
        arena: KIRArena,
        types: TypeSystem?,
        symbols: SymbolTable?,
        resolveTypeParameterUpperBound: Bool
    ) -> Int {
        guard let types, let typeID = arena.exprType(exprID) else { return 0 }
        let resolvedTypeID: TypeID
        if resolveTypeParameterUpperBound,
           let symbols,
           let upperBound = resolvePrimitiveArithmeticUpperBound(
               of: typeID, types: types, symbols: symbols
           )
        {
            resolvedTypeID = upperBound
        } else {
            resolvedTypeID = typeID
        }
        switch types.kind(of: resolvedTypeID) {
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

    /// Used as the KIR type of the conversion call's result -- must not be the
    /// comparison's own Boolean result type, or later ABI lowering misreads the
    /// widened numeric value as a boxed Boolean needing its own unboxing.
    private func widenedPrimitiveType(rank: Int, types: TypeSystem?) -> TypeID? {
        guard let types else { return nil }
        switch rank {
        case 2: return types.make(.primitive(.double, .nonNull))
        case 1: return types.make(.primitive(.float, .nonNull))
        default: return nil
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
