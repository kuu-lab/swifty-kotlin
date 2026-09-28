
extension CallLowerer {
    // MARK: - Binary Operations

    func lowerBinaryExpr(
        _ exprID: ExprID,
        op: BinaryOp,
        lhs: ExprID,
        rhs: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boolType = sema.types.booleanType
        // `&&` / `||` must short-circuit: rhs may only be evaluated once lhs's
        // value doesn't already pin down the result. The generic path below
        // evaluates both operands unconditionally before combining them, which
        // is correct for ordinary binary operators but would run rhs's side
        // effects/exceptions even when they must not fire, so these two get
        // their own control-flow lowering instead of falling through.
        if op == .logicalAnd || op == .logicalOr {
            return lowerShortCircuitLogicalExpr(
                op: op,
                lhs: lhs,
                rhs: rhs,
                boolType: boolType,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }
        // BUG-206: `?:` short-circuits for the same reason `&&`/`||` do — rhs is
        // the fallback, so it must not run when lhs is already non-null.
        if op == .elvis {
            return lowerShortCircuitElvisExpr(
                exprID,
                lhs: lhs,
                rhs: rhs,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }
        let boundType: TypeID? = switch op {
        case .equal, .notEqual, .identityEqual, .notIdentityEqual, .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
            boolType
        case .logicalAnd, .logicalOr:
            boolType
        default:
            sema.bindings.exprTypes[exprID]
        }
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let stringType = sema.types.stringType
        let lhsID = driver.lowerExpr(
            lhs,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let rhsID = driver.lowerExpr(
            rhs,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let result = arena.appendTemporary(type: boundType)
        if (op == .rangeTo || op == .rangeUntil),
           let floatingPointElementType = sema.bindings.floatingPointRangeElementType(forExpr: exprID)
        {
            let callee = floatingPointElementType == sema.types.floatType
                ? interner.intern(op == .rangeTo ? "__kk_float_rangeTo" : "__kk_float_rangeUntil")
                : interner.intern(op == .rangeTo ? "__kk_double_rangeTo" : "__kk_double_rangeUntil")
            instructions.append(.call(
                symbol: nil,
                callee: callee,
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        let isKClassEquality = (op == .equal || op == .notEqual)
            && (
                isKClassReceiverType(
                    sema.bindings.exprTypes[lhs] ?? sema.types.anyType,
                    sema: sema,
                    interner: interner
                )
                || isKClassReceiverType(
                    sema.bindings.exprTypes[rhs] ?? sema.types.anyType,
                    sema: sema,
                    interner: interner
                )
            )
        if isKClassEquality {
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern(op == .equal ? "kk_structural_eq" : "kk_structural_ne"),
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        let isRangeEquality = (op == .equal || op == .notEqual)
            && (sema.bindings.isRangeExpr(lhs) || sema.bindings.isRangeExpr(rhs))
        if isRangeEquality {
            // Range expressions are duck-typed as their scalar element type
            // during semantic analysis. Their raw values are still heap
            // handles, so the scalar kk_op_eq path would unbox the handle and
            // compare pointer bits. Preserve Kotlin's nominal range value
            // equality through the runtime structural bridge instead.
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern(op == .equal ? "kk_structural_eq" : "kk_structural_ne"),
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        // Resolve String operators before the generic call-binding path. The
        // bundled stdlib exposes `String` APIs as ordinary Kotlin wrappers,
        // so Sema may bind `+`/`==` to those source declarations. String is a
        // flat runtime aggregate, however, and the generic member-call path
        // would emit a bare `plus`/`equals` call (or compare raw words) rather
        // than the corresponding flat runtime ABI.
        let lhsType = sema.bindings.exprTypes[lhs]
        let rhsType = sema.bindings.exprTypes[rhs]
        let nullableStringType = sema.types.makeNullable(stringType)
        let lhsIsString = lhsType == stringType || lhsType == nullableStringType
        let rhsIsString = rhsType == stringType || rhsType == nullableStringType
        // Null literals get type nothing(.nullable), not stringStruct. Detect
        // them so the flat-string equality ABI receives a typed null aggregate.
        let lhsIsNullLiteral: Bool = {
            guard let t = lhsType, case .nothing = sema.types.kind(of: t) else { return false }
            return true
        }()
        let rhsIsNullLiteral: Bool = {
            guard let t = rhsType, case .nothing = sema.types.kind(of: t) else { return false }
            return true
        }()
        let isStringOperand = (lhsIsString && (rhsIsString || rhsIsNullLiteral))
            || (rhsIsString && lhsIsNullLiteral)
        let isStringComparison: Bool = if isStringOperand {
            switch op {
            case .equal, .notEqual, .identityEqual, .notIdentityEqual,
                 .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
                true
            default:
                false
            }
        } else {
            false
        }
        // `String.plus(Any?)` is itself a member, so a String-receiver `+`
        // always keeps the flat string-concat ABI below regardless of which
        // (bundled-source) symbol Sema bound it to. Only a *non*-String
        // receiver whose `+` resolved to a genuine operator candidate (e.g. a
        // user's `operator fun Int.plus(s: String): String` extension) should
        // defer to the resolved callee instead of this String-result
        // shortcut; a non-String receiver with no such binding is the
        // unresolved lenient built-in concatenation path, which keeps using
        // this ABI too.
        let isStringAdd = op == .add
            && sema.bindings.exprTypes[exprID] == stringType
            && (lhsIsString || isStringOperand || sema.bindings.callBindings[exprID] == nil)
        // Detect whether this is a compareTo-desugared comparison operator.
        // If so, the call binding targets compareTo (returns Int) and we must
        // wrap the result with a comparison against 0 to produce Bool.
        let isCompareToDesugaring: Bool = switch op {
        case .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
            sema.bindings.callBindings[exprID] != nil
        default:
            false
        }
        // STDLIB-OP-031: Detect != desugaring to equals() call + negation.
        let isEqualsDesugaring: Bool = op == .notEqual
            && sema.bindings.callBindings[exprID] != nil
        if let callBinding = sema.bindings.callBindings[exprID],
           !isStringAdd,
           !isStringComparison,
           let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee)
        {
            let isNominalMemberOperator = if let owner = sema.symbols.parentSymbol(for: callBinding.chosenCallee),
                                            let ownerSymbol = sema.symbols.symbol(owner)
            {
                switch ownerSymbol.kind {
                case .class, .interface, .object, .enumClass, .annotationClass:
                    true
                default:
                    false
                }
            } else {
                false
            }
            if signature.receiverType != nil || isNominalMemberOperator {
                // For compareTo desugaring, the call result is Int, not Bool.
                // For != (equals desugaring), the call result is Bool that needs negation.
                // We allocate a separate temporary for both cases.
                let callResult: KIRExprID = if isCompareToDesugaring {
                    arena.appendTemporary(type: intType)
                } else if isEqualsDesugaring {
                    arena.appendTemporary(type: boolType)
                } else {
                    result
                }
                // String keeps its flat comparison ABI; source-backed
                // Comparable.compareTo uses its explicit runtime bridge through
                // the ordinary member-call lowering below.
                if isCompareToDesugaring {
                    let lhsTypeForCompare = sema.bindings.exprTypes[lhs]
                    let rhsTypeForCompare = sema.bindings.exprTypes[rhs]
                    let nullableString = sema.types.makeNullable(stringType)
                    let lhsIsString = lhsTypeForCompare == stringType || lhsTypeForCompare == nullableString
                    let rhsIsString = rhsTypeForCompare == stringType || rhsTypeForCompare == nullableString
                    if lhsIsString, rhsIsString {
                        instructions.append(.call(
                            symbol: nil,
                            callee: interner.intern("kk_string_compareTo_flat"),
                            arguments: [lhsID, rhsID],
                            result: callResult,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        let zeroExpr = arena.appendExpr(.intLiteral(0), type: intType)
                        instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                        let cmpOp: KIRBinaryOp
                        switch op {
                        case .lessThan: cmpOp = .lessThan
                        case .lessOrEqual: cmpOp = .lessOrEqual
                        case .greaterThan: cmpOp = .greaterThan
                        case .greaterOrEqual: cmpOp = .greaterOrEqual
                        default: fatalError("Unreachable: compareTo desugaring only applies to comparison operators")
                        }
                        instructions.append(.binary(op: cmpOp, lhs: callResult, rhs: zeroExpr, result: result))
                        return result
                    }
                }
                let normalizedResult = driver.callSupportLowerer.normalizedCallArguments(
                    providedArguments: [rhsID],
                    callBinding: callBinding,
                    chosenCallee: callBinding.chosenCallee,
                    spreadFlags: [false],
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                var finalArguments = normalizedResult.arguments
                finalArguments.insert(lhsID, at: 0)
                if !signature.reifiedTypeParameterIndices.isEmpty {
                    for index in signature.reifiedTypeParameterIndices.sorted() {
                        let concreteType = index < callBinding.substitutedTypeArguments.count
                            ? callBinding.substitutedTypeArguments[index]
                            : sema.types.anyType
                        let encodedToken = RuntimeTypeCheckToken.encode(type: concreteType, sema: sema, interner: interner)
                        let tokenExpr = arena.appendExpr(
                            .intLiteral(encodedToken),
                            type: intType
                        )
                        instructions.append(.constValue(result: tokenExpr, value: .intLiteral(encodedToken)))
                        finalArguments.append(tokenExpr)
                    }
                }
                if normalizedResult.defaultMask != 0,
                   sema.symbols.externalLinkName(for: callBinding.chosenCallee)?.isEmpty ?? true
                {
                    let maskExpr = arena.appendExpr(.intLiteral(Int64(normalizedResult.defaultMask)), type: intType)
                    instructions.append(.constValue(result: maskExpr, value: .intLiteral(Int64(normalizedResult.defaultMask))))
                    finalArguments.append(maskExpr)
                    let stubName = interner.intern(
                        (sema.symbols.symbol(callBinding.chosenCallee).map { interner.resolve($0.name) } ?? "unknown") + "$default"
                    )
                    // KUU-655: an override that inherits its defaults never
                    // has its own stub; resolve to the base declaration's
                    // stub instead (see `defaultStubOwnerSymbol`). Operators
                    // have no `super.`-qualified call syntax, so there is no
                    // mask "super call" bit to set here.
                    let stubOwner = driver.callSupportLowerer.defaultStubOwnerSymbol(for: callBinding.chosenCallee, sema: sema)
                    let stubSym = driver.callSupportLowerer.defaultStubSymbol(for: stubOwner)
                    instructions.append(.call(
                        symbol: stubSym,
                        callee: stubName,
                        arguments: finalArguments,
                        result: callResult,
                        canThrow: false,
                        thrownResult: nil
                    ))
                } else {
                    let sourceBackedHashSetEquality = (op == .equal || op == .notEqual)
                        && isSourceBackedHashSetType(
                            sema.bindings.exprTypes[lhs] ?? sema.types.anyType,
                            sema: sema,
                            interner: interner
                        )
                    let loweredCalleeName: InternedString = if sourceBackedHashSetEquality {
                        // Source-backed HashSet values are RuntimeSetBox handles, so operator equality must use the structural runtime bridge instead of the inherited AbstractMutableSet.equals body.
                        interner.intern("kk_structural_eq")
                    } else if let externalLinkName = sema.symbols.externalLinkName(for: callBinding.chosenCallee),
                                                               !externalLinkName.isEmpty
                    {
                        interner.intern(externalLinkName)
                    } else if let symbol = sema.symbols.symbol(callBinding.chosenCallee) {
                        symbol.name
                    } else {
                        interner.intern(op.kotlinFunctionName)
                    }
                    instructions.append(.call(
                        symbol: sourceBackedHashSetEquality ? nil : callBinding.chosenCallee,
                        callee: loweredCalleeName,
                        arguments: finalArguments,
                        result: callResult,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }
                // compareTo desugaring: emit `compareTo(a,b) <op> 0` to produce Bool
                if isCompareToDesugaring {
                    let zeroExpr = arena.appendExpr(.intLiteral(0), type: intType)
                    instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    let cmpOp: KIRBinaryOp
                    switch op {
                    case .lessThan: cmpOp = .lessThan
                    case .lessOrEqual: cmpOp = .lessOrEqual
                    case .greaterThan: cmpOp = .greaterThan
                    case .greaterOrEqual: cmpOp = .greaterOrEqual
                    default: fatalError("Unreachable: isCompareToDesugaring should only be true for comparison operators")
                    }
                    instructions.append(.binary(op: cmpOp, lhs: callResult, rhs: zeroExpr, result: result))
                }
                // STDLIB-OP-031: != desugaring: negate the equals() result
                if isEqualsDesugaring {
                    instructions.append(.unary(op: .not, operand: callResult, result: result))
                }
                return result
            }
        }
        // STDLIB-561/562: Sequence plus/minus operators.
        if isSequenceLikeType(sema.bindings.exprTypes[lhs] ?? sema.types.anyType, sema: sema, interner: interner) {
            let callees = SequencePlusMinusRuntimeCallees(interner: interner)
            if op == .add {
                emitSequencePlusMinusRewrite(
                    operation: .plus,
                    receiver: lhsID,
                    argument: rhsID,
                    argumentIsCollection: sema.bindings.isCollectionExpr(rhs),
                    result: result,
                    arena: arena,
                    callees: callees,
                    instructions: &instructions
                )
                return result
            }
            if op == .subtract {
                let rewriteResult = emitSequencePlusMinusRewrite(
                    operation: .minus,
                    receiver: lhsID,
                    argument: rhsID,
                    argumentIsCollection: sema.bindings.isCollectionExpr(rhs),
                    result: result,
                    arena: arena,
                    callees: callees,
                    instructions: &instructions
                )
                if case .emitted = rewriteResult {
                    return result
                }
                // Collection-removal is not yet supported at the ABI level.
                // Return the LHS unchanged rather than falling through to
                // the generic arithmetic path which would miscompile.
                instructions.append(.copy(from: lhsID, to: result))
                return result
            }
        }
        if case .add = op, sema.bindings.exprTypes[exprID] == stringType {
            // Kotlin String.plus(other: Any?) calls toString() on the RHS
            // when it is not already a String. Insert a kk_any_to_string
            // coercion so that __kk_string_concat_flat always receives two string
            // aggregate values.
            let rhsExprType = sema.bindings.exprTypes[rhs]
            let effectiveRHS: KIRExprID
            if rhsExprType == stringType {
                effectiveRHS = rhsID
            } else {
                effectiveRHS = emitAnyToStringWithNullGuard(
                    valueID: rhsID,
                    valueType: rhsExprType ?? sema.types.anyType,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
            }
            // Similarly coerce LHS if it is not a String (e.g. Any + String).
            let lhsExprType = sema.bindings.exprTypes[lhs]
            let effectiveLHS: KIRExprID
            if lhsExprType == stringType {
                effectiveLHS = lhsID
            } else {
                effectiveLHS = emitAnyToStringWithNullGuard(
                    valueID: lhsID,
                    valueType: lhsExprType ?? sema.types.anyType,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
            }
            instructions.append(
                .call(
                    symbol: nil,
                    callee: interner.intern("__kk_string_concat_flat"),
                    arguments: [effectiveLHS, effectiveRHS],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                )
            )
            return result
        }
        // String comparison desugaring: route <, <=, >, >= on String operands
        // through kk_string_compareTo_flat (content comparison) instead of the default
        // kk_op_lt/le/gt/ge path which compares raw pointer addresses.
        if isStringOperand {
            // When one side is a null literal, we need an expression typed as
            // nullableStringType so the flat-string codegen generates a null string
            // aggregate (nullptr, 0, 0, 0) instead of a raw i64 null sentinel.
            func resolvedStringID(for id: KIRExprID, isNull: Bool) -> KIRExprID {
                guard isNull else { return id }
                let nullStringID = arena.appendTemporary(type: nullableStringType)
                instructions.append(.constValue(result: nullStringID, value: .null))
                return nullStringID
            }
            switch op {
            // `===`/`!==` fold into the same content-equality codegen as `==`/`!=`
            // here: String is a "flat" by-value aggregate (data/length/byteCount/hash)
            // in this runtime, not a heap reference, so there is no separate pointer
            // identity to compare — `kk_op_eq`/`kk_op_ne` also cannot accept it
            // (their ABI takes one word per operand, not a 4-word aggregate).
            case .equal, .identityEqual:
                let actualLhsID = resolvedStringID(for: lhsID, isNull: lhsIsNullLiteral)
                let actualRhsID = resolvedStringID(for: rhsID, isNull: rhsIsNullLiteral)
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("__kk_string_equals_flat"),
                    arguments: [actualLhsID, actualRhsID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            case .notEqual, .notIdentityEqual:
                let actualLhsID = resolvedStringID(for: lhsID, isNull: lhsIsNullLiteral)
                let actualRhsID = resolvedStringID(for: rhsID, isNull: rhsIsNullLiteral)
                let eqResult = arena.appendTemporary(type: boolType)
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("__kk_string_equals_flat"),
                    arguments: [actualLhsID, actualRhsID],
                    result: eqResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                instructions.append(.unary(op: .not, operand: eqResult, result: result))
                return result
            case .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
                let compareResult = arena.appendTemporary(type: intType)
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_compareTo_flat"),
                    arguments: [lhsID, rhsID],
                    result: compareResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                let cmpOp: KIRBinaryOp
                switch op {
                case .lessThan: cmpOp = .lessThan
                case .lessOrEqual: cmpOp = .lessOrEqual
                case .greaterThan: cmpOp = .greaterThan
                case .greaterOrEqual: cmpOp = .greaterOrEqual
                default: fatalError("Unreachable: unexpected comparison operator for string operands")
                }
                instructions.append(.binary(op: cmpOp, lhs: compareResult, rhs: zeroExpr, result: result))
                return result
            default:
                break
            }
        }
        // SPEC-NUM-0003: IEEE-754 path for Double/Float relational and inequality operators
        // must run before builtinBinaryRuntimeCallee, which maps them to integer ops
        // (kk_op_lt/le/gt/ge/ne) that use total ordering where NaN is the maximum value.
        // IEEE-754 requires comparisons involving NaN to return false, and NaN != NaN
        // to return true.  The typed kk_op_d*/kk_op_f* runtime functions use Swift
        // operators that are IEEE-754 compliant.
        switch op {
        // .notEqual reaches here only with matching floating-point operands
        // in practice -- a mixed Double/Int `!=` is rejected by real kotlinc
        // (this compiler currently accepts it too; tracked separately as
        // BUG-262), so the widening below is a no-op for legal `!=` sources.
        case .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual, .notEqual:
            let lhsTypeID = arena.exprType(lhsID) ?? sema.bindings.exprTypes[lhs]
            let rhsTypeID = arena.exprType(rhsID) ?? sema.bindings.exprTypes[rhs]
            let lhsIsFloatingPoint = lhsTypeID.map { isFloatingPointPrimitiveType($0, types: sema.types) } ?? false
            let rhsIsFloatingPoint = rhsTypeID.map { isFloatingPointPrimitiveType($0, types: sema.types) } ?? false
            // `!=` on a *nullable* Double?/Float? must stay null-aware: a
            // null operand can never be IEEE-compared, and the runtime null
            // sentinel's bit pattern equals -0.0, so kk_op_dne/fne's fixed
            // IEEE comparison would treat a genuine null as -0.0. Defer to
            // the generic `.binary` path below (op == .notEqual falls through
            // this switch unchanged), which OperatorLoweringPass routes
            // through the null-aware kk_nullable_primitive_ne instead.
            let isNullableFloatingPointNotEqual = op == .notEqual
                && ((lhsTypeID.map { isNullableFloatingPointType($0, types: sema.types) } ?? false)
                    || (rhsTypeID.map { isNullableFloatingPointType($0, types: sema.types) } ?? false))
            if (lhsIsFloatingPoint || rhsIsFloatingPoint), !isNullableFloatingPointNotEqual {
                // BUG-258: a mixed comparison (e.g. `aDouble <= 1`) must widen
                // the non-floating-point side to the same floating-point type
                // before comparing -- kk_op_d*/kk_op_f* interpret both
                // arguments as that type's raw IEEE-754 bit pattern, so an
                // un-widened Int/Long operand's bit pattern gets misread as
                // an unrelated (near-zero denormal) double/float value
                // instead of the numeric value it actually holds.
                let isDouble = [lhsTypeID, rhsTypeID].contains { typeID in
                    guard let typeID else { return false }
                    if case .primitive(.double, _) = sema.types.kind(of: typeID) { return true }
                    return false
                }
                let effectiveLhsID = widenIntegerOperandToFloatingPoint(
                    lhsID, operandTypeID: lhsTypeID, isFloatingPoint: lhsIsFloatingPoint, toDouble: isDouble,
                    sema: sema, arena: arena, interner: interner, instructions: &instructions
                )
                let effectiveRhsID = widenIntegerOperandToFloatingPoint(
                    rhsID, operandTypeID: rhsTypeID, isFloatingPoint: rhsIsFloatingPoint, toDouble: isDouble,
                    sema: sema, arena: arena, interner: interner, instructions: &instructions
                )
                let prefix = isDouble ? "d" : "f"
                let suffix: String = switch op {
                case .lessThan: "lt"
                case .lessOrEqual: "le"
                case .greaterThan: "gt"
                case .greaterOrEqual: "ge"
                case .notEqual: "ne"
                default: fatalError("Unreachable: switch only reached for relational ops and notEqual")
                }
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_op_\(prefix)\(suffix)"),
                    arguments: [effectiveLhsID, effectiveRhsID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        default:
            break
        }
        // Unsigned-aware path for UInt/ULong/UByte/UShort relational operators.
        // builtinBinaryRuntimeCallee below maps <,<=,>,>= to kk_op_lt/le/gt/ge,
        // which reinterpret both operands as signed Int64 — wrong for ULong once
        // the value's high bit is set (any ULong >= 2^63, e.g. UInt64.MAX_VALUE),
        // since e.g. `17663719463477156090uL > 5uL` would compare a negative
        // signed reinterpretation against 5. Route unsigned operands through the
        // dedicated kk_op_u{lt,le,gt,ge} entry points, which compare the raw bit
        // pattern via UInt(bitPattern:) instead.
        switch op {
        case .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
            let unsignedTypeID = arena.exprType(lhsID) ?? sema.bindings.exprTypes[lhs]
                              ?? arena.exprType(rhsID) ?? sema.bindings.exprTypes[rhs]
            if let typeID = unsignedTypeID, sema.types.isUnsigned(typeID) {
                let suffix: String = switch op {
                case .lessThan: "ult"
                case .lessOrEqual: "ule"
                case .greaterThan: "ugt"
                case .greaterOrEqual: "uge"
                default: fatalError("Unreachable: switch only reached for relational ops")
                }
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_op_\(suffix)"),
                    arguments: [lhsID, rhsID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        default:
            break
        }
        // KSP-466 / PEC-NUM-0002: Unsigned-aware path for UInt/ULong/UByte/UShort
        // division and remainder. The kk_op_div/kk_op_mod path below (reached via
        // the .divide/.modulo cases further down) performs plain signed Int64
        // division, which is wrong for ULong once the value's high bit is set
        // (any ULong >= 2^63) — e.g. 17663719463477156090uL / 2uL would divide the
        // negative signed reinterpretation instead of the actual unsigned value.
        // UInt/UByte/UShort are always zero-extended into the shared 64-bit
        // container, so signed and unsigned division already agree for them, but
        // routing them through kk_op_udiv/kk_op_urem too is harmless and keeps this
        // check a single isUnsigned test. kk_op_udiv/kk_op_urem reinterpret both
        // operands via UInt(bitPattern:) and still throw ArithmeticException on
        // zero divisor via outThrown, matching kk_op_div/kk_op_mod.
        switch op {
        case .divide, .modulo:
            let unsignedTypeID = arena.exprType(lhsID) ?? sema.bindings.exprTypes[lhs]
                              ?? arena.exprType(rhsID) ?? sema.bindings.exprTypes[rhs]
            if let typeID = unsignedTypeID, sema.types.isUnsigned(typeID) {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern(op == .divide ? "kk_op_udiv" : "kk_op_urem"),
                    arguments: [lhsID, rhsID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        default:
            break
        }
        if let runtimeCallee = driver.callSupportLowerer.builtinBinaryRuntimeCallee(for: op, interner: interner) {
            instructions.append(
                .call(
                    symbol: nil,
                    callee: runtimeCallee,
                    arguments: [lhsID, rhsID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                )
            )
            return result
        }
        let kirOp: KIRBinaryOp
        switch op {
        case .add:
            kirOp = .add
        case .subtract:
            kirOp = .subtract
        case .multiply:
            kirOp = .multiply
        case .divide:
            // PEC-NUM-0002: Integer division must throw ArithmeticException("/ by zero") on zero divisor.
            // Float/Double division falls through to .binary so OperatorLoweringPass emits kk_op_fdiv/ddiv.
            // Unsigned operands (UInt/ULong/UByte/UShort) already returned via kk_op_udiv above.
            if let bt = boundType, case let .primitive(prim, _) = sema.types.kind(of: bt),
               prim == .float || prim == .double {
                kirOp = .divide
            } else {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_op_div"),
                    arguments: [lhsID, rhsID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        case .modulo:
            if let bt = boundType, case let .primitive(prim, _) = sema.types.kind(of: bt),
               prim == .float || prim == .double {
                kirOp = .modulo
            } else {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_op_mod"),
                    arguments: [lhsID, rhsID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        case .equal:
            kirOp = .equal
        case .notEqual:
            kirOp = .notEqual
        case .identityEqual, .notIdentityEqual:
            // Always resolved earlier: builtinBinaryRuntimeCallee (kk_op_eq/kk_op_ne)
            // for ordinary operands, or the string content-equality path above for
            // String operands. Neither falls through to this raw KIRBinaryOp path.
            preconditionFailure("=== / !== must be lowered before reaching the raw KIRBinaryOp path")
        case .lessThan:
            kirOp = .lessThan
        case .lessOrEqual:
            kirOp = .lessOrEqual
        case .greaterThan:
            kirOp = .greaterThan
        case .greaterOrEqual:
            kirOp = .greaterOrEqual
        case .logicalAnd:
            kirOp = .logicalAnd
        case .logicalOr:
            kirOp = .logicalOr
        case .elvis:
            preconditionFailure("?: must be lowered through lowerShortCircuitElvisExpr")
        case .rangeTo:
            // Range expressions are duck-typed to their scalar element type,
            // but the runtime needs the exact nominal range class for equality
            // and hashCode semantics.
            let rangeToCallee: InternedString
            let lhsType = sema.bindings.exprTypes[lhs] ?? sema.types.anyType
            let rhsType = sema.bindings.exprTypes[rhs] ?? sema.types.anyType
            if sema.bindings.isCharRangeExpr(exprID)
                || lhsType == sema.types.charType
                || rhsType == sema.types.charType
            {
                rangeToCallee = interner.intern("__kk_char_rangeTo")
            } else if lhsType == sema.types.longType || rhsType == sema.types.longType {
                rangeToCallee = interner.intern("__kk_long_rangeTo")
            } else if sema.bindings.isFloatingPointRangeExpr(exprID) {
                if lhsType == sema.types.floatType || rhsType == sema.types.floatType {
                    rangeToCallee = interner.intern("__kk_float_rangeTo")
                } else {
                    rangeToCallee = interner.intern("__kk_double_rangeTo")
                }
            } else if sema.bindings.isULongRangeExpr(exprID) {
                rangeToCallee = interner.intern("__kk_ulong_rangeTo")
            } else if sema.bindings.isUIntRangeExpr(exprID) {
                rangeToCallee = interner.intern("__kk_uint_rangeTo")
            } else if sema.bindings.isULongRangeExpr(exprID) {
                rangeToCallee = interner.intern("__kk_ulong_rangeTo")
            } else {
                rangeToCallee = interner.intern("kk_op_rangeTo")
            }
            instructions.append(.call(
                symbol: nil,
                callee: rangeToCallee,
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        case .rangeUntil:
            let lhsType = sema.bindings.exprTypes[lhs] ?? sema.types.anyType
            let rhsType = sema.bindings.exprTypes[rhs] ?? sema.types.anyType
            let rangeUntilCallee: InternedString
            if sema.bindings.isFloatingPointRangeExpr(exprID) {
                let elementType = sema.bindings.floatingPointRangeElementType(forExpr: exprID)
                if elementType == sema.types.floatType {
                    rangeUntilCallee = interner.intern("__kk_float_rangeUntil")
                } else {
                    rangeUntilCallee = interner.intern("__kk_double_rangeUntil")
                }
            } else if sema.bindings.isCharRangeExpr(exprID)
                || lhsType == sema.types.charType
                || rhsType == sema.types.charType
            {
                rangeUntilCallee = interner.intern("__kk_char_rangeUntil")
            } else if lhsType == sema.types.longType || rhsType == sema.types.longType {
                rangeUntilCallee = interner.intern("__kk_long_rangeUntil")
            } else if sema.bindings.isULongRangeExpr(exprID) {
                rangeUntilCallee = interner.intern("__kk_op_ulong_rangeUntil")
            } else if sema.bindings.isUIntRangeExpr(exprID) {
                rangeUntilCallee = interner.intern("__kk_uint_rangeUntil")
            } else {
                rangeUntilCallee = interner.intern("__kk_op_rangeUntil")
            }
            instructions.append(.call(
                symbol: nil,
                callee: rangeUntilCallee,
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        case .downTo:
            let downToCallee: InternedString
            if sema.bindings.isULongRangeExpr(exprID) {
                downToCallee = interner.intern("__kk_ulong_downTo")
            } else if sema.bindings.isUIntRangeExpr(exprID) {
                downToCallee = interner.intern("__kk_uint_downTo")
            } else {
                downToCallee = interner.intern("__kk_op_downTo")
            }
            instructions.append(.call(
                symbol: nil,
                callee: downToCallee,
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        case .step:
            let stepCallee: InternedString
            if sema.bindings.isCharRangeExpr(exprID) {
                stepCallee = interner.intern("__kk_char_range_step")
            } else if sema.bindings.isULongRangeExpr(exprID) {
                stepCallee = interner.intern("__kk_ulong_step")
            } else if sema.bindings.isUIntRangeExpr(exprID) {
                stepCallee = interner.intern("__kk_uint_step")
            } else {
                stepCallee = interner.intern("__kk_op_step")
            }
            // __kk_op_step carries an outThrown ABI channel for invalid step values;
            // the unsigned helpers do not. Mark it throwable so the backend passes the
            // thrown channel and can short-circuit on an invalid step.
            let stepCanThrow = stepCallee == interner.intern("__kk_op_step")
            instructions.append(.call(
                symbol: nil,
                callee: stepCallee,
                arguments: [lhsID, rhsID],
                result: result,
                canThrow: stepCanThrow,
                thrownResult: nil
            ))
            return result
        case .bitwiseAnd, .bitwiseOr, .bitwiseXor, .shl, .shr, .ushr:
            preconditionFailure("Bitwise/shift binary operators must be lowered through member-call special handling")
        }
        if op == .equal || op == .notEqual {
            // A values()/entries element read out of an Any-erased array is a
            // boxed ordinal, while a direct enum reference (e.g.
            // Direction.NORTH) is a raw one -- normalize both operands so the
            // comparison isn't a boxed-handle-vs-raw-ordinal mismatch. See
            // unboxIfEnumTyped.
            let normalizedLhsID = unboxIfEnumTyped(
                lhsID, staticType: sema.bindings.exprTypes[lhs],
                sema: sema, arena: arena, interner: interner, into: &instructions
            )
            let normalizedRhsID = unboxIfEnumTyped(
                rhsID, staticType: sema.bindings.exprTypes[rhs],
                sema: sema, arena: arena, interner: interner, into: &instructions
            )
            instructions.append(.binary(op: kirOp, lhs: normalizedLhsID, rhs: normalizedRhsID, result: result))
            return result
        }
        instructions.append(.binary(op: kirOp, lhs: lhsID, rhs: rhsID, result: result))
        return result
    }

    /// Lowers `&&`/`||` with proper short-circuit control flow.
    ///
    /// `lhs && rhs` behaves like `if (lhs) rhs else false`; `lhs || rhs`
    /// behaves like `if (lhs) true else rhs`. Either way, rhs is only lowered
    /// (and its instructions only emitted) behind a branch that is skipped
    /// once lhs already equals `shortCircuitsOn` (false for `&&`, true for
    /// `||`), matching the desugarings above.
    private func lowerShortCircuitLogicalExpr(
        op: BinaryOp,
        lhs: ExprID,
        rhs: ExprID,
        boolType: TypeID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let lhsID = driver.lowerExpr(
            lhs,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let shortCircuitsOn = op == .logicalOr
        let shortCircuitLabel = driver.ctx.makeLoopLabel()
        let endLabel = driver.ctx.makeLoopLabel()
        let result = arena.appendTemporary(type: boolType)
        let shortCircuitLiteral = arena.appendExpr(.boolLiteral(shortCircuitsOn), type: boolType)
        instructions.append(.constValue(result: shortCircuitLiteral, value: .boolLiteral(shortCircuitsOn)))
        instructions.append(.jumpIfEqual(lhs: lhsID, rhs: shortCircuitLiteral, target: shortCircuitLabel))
        let rhsID = driver.lowerExpr(
            rhs,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        if !driver.controlFlowLowerer.isTerminatedExpr(rhsID, arena: arena, sema: sema) {
            instructions.append(.copy(from: rhsID, to: result))
            instructions.append(.jump(endLabel))
        }
        instructions.append(.label(shortCircuitLabel))
        instructions.append(.copy(from: shortCircuitLiteral, to: result))
        instructions.append(.label(endLabel))
        return result
    }

    /// Lowers `?:` with proper short-circuit control flow.
    ///
    /// `lhs ?: rhs` behaves like `if (lhs != null) lhs else rhs`, so rhs is
    /// only lowered behind a branch that is skipped when lhs is non-null. The
    /// previous strict lowering handed both operands to `kk_op_elvis`, which
    /// evaluated the fallback unconditionally: `x ?: return -1` always
    /// returned, `x ?: throw e` always threw, and any fallback with side
    /// effects always ran (BUG-206).
    ///
    /// A `String`-typed result keeps the `kk_any_to_string` conversion the
    /// strict lowering applied to `kk_op_elvis`'s result -- both operands reach
    /// here as single-word values, while the result is the flat aggregate --
    /// but now applies it per branch.
    private func lowerShortCircuitElvisExpr(
        _ exprID: ExprID,
        lhs: ExprID,
        rhs: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boundType = sema.bindings.exprTypes[exprID]
        let result = arena.appendTemporary(type: boundType)
        let producesString = boundType == sema.types.stringType
        let lhsID = driver.lowerExpr(
            lhs,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let notNullLabel = driver.ctx.makeLoopLabel()
        let endLabel = driver.ctx.makeLoopLabel()
        instructions.append(.jumpIfNotNull(value: lhsID, target: notNullLabel))

        let rhsID = driver.lowerExpr(
            rhs,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        if !driver.controlFlowLowerer.isTerminatedExpr(rhsID, arena: arena, sema: sema) {
            emitElvisBranchResult(
                rhsID, into: result, producesString: producesString,
                sema: sema, arena: arena, interner: interner, instructions: &instructions
            )
            instructions.append(.jump(endLabel))
        }

        instructions.append(.label(notNullLabel))
        emitElvisBranchResult(
            lhsID, into: result, producesString: producesString,
            sema: sema, arena: arena, interner: interner, instructions: &instructions
        )
        instructions.append(.label(endLabel))
        return result
    }

    private func emitElvisBranchResult(
        _ valueID: KIRExprID,
        into result: KIRExprID,
        producesString: Bool,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        guard producesString else {
            instructions.append(.copy(from: valueID, to: result))
            return
        }
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let stringTag = arena.appendExpr(.intLiteral(3), type: intType)
        instructions.append(.constValue(result: stringTag, value: .intLiteral(3)))
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_any_to_string"),
            arguments: [valueID, stringTag],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
    }

    private func isFloatingPointPrimitiveType(_ typeID: TypeID, types: TypeSystem) -> Bool {
        switch types.kind(of: typeID) {
        case .primitive(.double, _), .primitive(.float, _): return true
        default: return false
        }
    }

    private func isNullableFloatingPointType(_ typeID: TypeID, types: TypeSystem) -> Bool {
        switch types.kind(of: typeID) {
        case .primitive(.double, .nullable), .primitive(.float, .nullable): return true
        default: return false
        }
    }

    /// BUG-258: widens an integer-typed comparison operand to the raw
    /// IEEE-754 bit pattern of `toDouble: true ? Double : Float` so it can be
    /// compared against a genuine floating-point operand by `kk_op_d*`/
    /// `kk_op_f*` -- both interpret their arguments as that type's bit
    /// pattern, so an un-widened Int/Long/Short/Byte value would otherwise be
    /// misread as an unrelated floating-point value. A value that is already
    /// the target floating-point type (or of unknown type) passes through
    /// unchanged.
    private func widenIntegerOperandToFloatingPoint(
        _ operandID: KIRExprID,
        operandTypeID: TypeID?,
        isFloatingPoint: Bool,
        toDouble: Bool,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        guard let operandTypeID else { return operandID }
        let types = sema.types
        let nonNullType = types.makeNonNullable(operandTypeID)
        if isFloatingPoint {
            // Already floating-point; a Float still needs widening when
            // compared against a Double (real Kotlin defines
            // Float.compareTo(Double)), since kk_op_d* reads its arguments
            // as Double bit patterns.
            guard toDouble, nonNullType == types.floatType else { return operandID }
            let widened = arena.appendTemporary(type: types.doubleType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("__kk_float_to_double_bits"),
                arguments: [operandID],
                result: widened,
                canThrow: false,
                thrownResult: nil
            ))
            return widened
        }
        let calleeName: InternedString
        if nonNullType == types.longType {
            calleeName = interner.intern(toDouble ? "kk_long_to_double" : "kk_long_to_float")
        } else if nonNullType == types.intType || nonNullType == types.shortType || nonNullType == types.byteType {
            calleeName = interner.intern(toDouble ? "kk_int_to_double_bits" : "kk_int_to_float_bits")
        } else {
            // Not a recognized integer primitive (e.g. already the other
            // floating-point width, or a non-numeric type reached via the
            // `Any`-erasure fallback below) -- leave it unchanged.
            return operandID
        }
        let widened = arena.appendTemporary(type: toDouble ? types.doubleType : types.floatType)
        instructions.append(.call(
            symbol: nil,
            callee: calleeName,
            arguments: [operandID],
            result: widened,
            canThrow: false,
            thrownResult: nil
        ))
        return widened
    }

    // MARK: - Array Operations

    func lowerIndexedAccessExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        indices: [ExprID],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boundType = sema.bindings.exprTypes[exprID]
        let receiverID = driver.lowerExpr(
            receiverExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let callBinding = recoverMemberCallBinding(
            exprID: exprID,
            receiverExpr: receiverExpr,
            calleeName: interner.intern("get"),
            argumentExprs: indices,
            sema: sema
        ) ?? sema.bindings.callBindings[exprID]
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        let receiverUsesFlatStringABI = sema.types.isSubtype(nonNullReceiverType, sema.types.stringType)
        let chosenGetIsSourceBacked = if let chosenGet = callBinding?.chosenCallee {
            sema.symbols.isSourceBackedSymbol(chosenGet)
        } else {
            false
        }
        if indices.count == 1,
           receiverUsesFlatStringABI,
           !chosenGetIsSourceBacked
        {
            let indexID = driver.lowerExpr(
                indices[0],
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let thrownExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
            instructions.append(.constValue(result: thrownExpr, value: .intLiteral(0)))
            let result = arena.appendTemporary(type: boundType ?? sema.types.anyType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("__kk_string_get_flat"),
                arguments: [receiverID, indexID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }
        if let chosenGet = callBinding?.chosenCallee,
           chosenGet != .invalid,
           let signature = sema.symbols.functionSignature(for: chosenGet),
           signature.receiverType != nil
        {
            let loweredIndices = indices.map { indexExpr in
                driver.lowerExpr(
                    indexExpr,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            }
            let result = arena.appendTemporary(type: boundType ?? sema.types.anyType)
            emitMemberCallInstruction(
                normalized: driver.callSupportLowerer.normalizedCallArguments(
                    providedArguments: loweredIndices,
                    callBinding: callBinding,
                    chosenCallee: chosenGet,
                    spreadFlags: Array(repeating: false, count: loweredIndices.count),
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                ),
                callBinding: callBinding,
                chosenCallee: chosenGet,
                calleeName: interner.intern("get"),
                receiver: MemberCallReceiver(expr: receiverExpr, loweredID: receiverID),
                result: result,
                isSuperCall: sema.bindings.isSuperCallExpr(exprID),
                qualifiedSuperType: nil,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions,
                arguments: [receiverID] + loweredIndices
            )
            return result
        }
        // Built-in array get only supports a single Int index
        assert(!indices.isEmpty, "indices must not be empty for indexed access")
        let indexID = driver.lowerExpr(
            indices[0],
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let result = arena.appendTemporary(type: boundType ?? sema.types.anyType)
        // Array<T>'s backing store holds boxed elements for primitive T (mirroring
        // listOf/kk_list_get), unlike IntArray/CharArray/... which store raw
        // primitives directly. Unbox right after the raw read so this result carries
        // the same raw-primitive representation any other primitive-typed KIR value
        // does; otherwise the boxed pointer gets misread as a raw value downstream
        // (e.g. re-boxed a second time at the next Any boundary).
        let receiverIsGenericArray = isGenericArrayReceiverType(nonNullReceiverType, sema: sema, interner: interner)
        if receiverIsGenericArray,
           let elementType = boundType,
           let unboxCallee = BoxingCalleeTable(interner: interner).unboxCallee(
               for: elementType,
               types: sema.types,
               requireNonNull: true
           )
        {
            let boxedResult = arena.appendTemporary(type: sema.types.anyType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_get"),
                arguments: [receiverID, indexID],
                result: boxedResult,
                canThrow: false,
                thrownResult: nil
            ))
            emitNonThrowingCall(
                callee: unboxCallee,
                arg: boxedResult,
                result: result,
                into: &instructions
            )
            return result
        }
        if TypeCheckHelpers().arrayElementType(
            for: nonNullReceiverType,
            sema: sema,
            interner: interner
        ) == sema.types.ubyteType {
            // ByteArray.asUByteArray() preserves signed storage, so normalize
            // the raw byte to UByte at the typed read boundary.
            let rawResult = arena.appendTemporary(type: sema.types.intType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_get"),
                arguments: [receiverID, indexID],
                result: rawResult,
                canThrow: false,
                thrownResult: nil
            ))
            emitNonThrowingCall(
                callee: interner.intern("kk_int_to_ubyte"),
                arg: rawResult,
                result: result,
                into: &instructions
            )
            return result
        }
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_get"),
            arguments: [receiverID, indexID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return result
    }

    func lowerIndexedAssignExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        indices: [ExprID],
        valueExpr: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let receiverID = driver.lowerExpr(
            receiverExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        // Built-in array set only supports a single Int index
        assert(!indices.isEmpty, "indices must not be empty for indexed assign")
        let indexID = driver.lowerExpr(
            indices[0],
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let valueID = driver.lowerExpr(
            valueExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        // A cast to Array<Any?> can make Sema bind the generic `Array.set`
        // member, but indexed assignment still has to use the array runtime
        // entry point. Emitting the source-backed member call here drops the
        // write from the KIR body and leaves the original array unchanged.
        let assignReceiverType = sema.types.makeNonNullable(
            sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        )
        let assignReceiverIsArrayLike = isConcreteArrayLikeType(
            assignReceiverType,
            sema: sema,
            interner: interner
        )
        if let callBinding = sema.bindings.callBindings[exprID], !assignReceiverIsArrayLike {
            let chosenSet = callBinding.chosenCallee
            var loweredIndices: [KIRExprID] = []
            for (i, indexExpr) in indices.enumerated() {
                if i == 0 {
                    loweredIndices.append(indexID)
                } else {
                    let loweredIndex = driver.lowerExpr(
                        indexExpr,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &instructions
                    )
                    loweredIndices.append(loweredIndex)
                }
            }
            let loweredArgs = loweredIndices + [valueID]
            let callResult = arena.appendTemporary(type: sema.types.unitType)
            emitMemberCallInstruction(
                normalized: driver.callSupportLowerer.normalizedCallArguments(
                    providedArguments: loweredArgs,
                    callBinding: callBinding,
                    chosenCallee: chosenSet,
                    spreadFlags: Array(repeating: false, count: loweredArgs.count),
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                ),
                callBinding: callBinding,
                chosenCallee: chosenSet,
                calleeName: interner.intern("set"),
                receiver: MemberCallReceiver(expr: receiverExpr, loweredID: receiverID),
                result: callResult,
                isSuperCall: sema.bindings.isSuperCallExpr(exprID),
                qualifiedSuperType: nil,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions,
                arguments: [receiverID] + loweredArgs
            )
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit
        }
        // arr[i] = value on a generic Array<T> must box a primitive value before
        // storing it, matching how arrayOf(...) boxes elements at construction time
        // (packVarargArguments) and how arr[i] unboxes on read (above). Leaving this
        // unboxed would corrupt the array with a mix of boxed and raw elements.
        let assignReceiverIsGenericArray = isGenericArrayReceiverType(
            sema.bindings.exprTypes[receiverExpr],
            sema: sema,
            interner: interner
        )
        let storedValueID: KIRExprID
        if assignReceiverIsGenericArray, let valueType = arena.exprType(valueID) {
            storedValueID = boxValueForAnySlot(
                valueID,
                sourceType: valueType,
                types: sema.types,
                symbols: sema.symbols,
                interner: interner,
                arena: arena,
                into: &instructions
            )
        } else {
            storedValueID = valueID
        }
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_set"),
            arguments: [receiverID, indexID, storedValueID],
            result: nil,
            canThrow: false,
            thrownResult: nil
        ))
        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    func lowerIndexedCompoundAssignExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        indices: [ExprID],
        valueExpr: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        guard let expr = ast.arena.expr(exprID),
              case let .indexedCompoundAssign(op, _, _, _, _) = expr
        else {
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit
        }

        // Conceptual desugaring: a[i] += v
        //   1) t = kk_array_get(a, i)
        //   2) t' = kk_op_*(t, v)      // appropriate kk_op_* for the compound operator
        //   3) kk_array_set(a, i, t')
        let receiverID = driver.lowerExpr(
            receiverExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        // KSWIFTK-BUG: when Sema resolved a custom (or source-backed member,
        // e.g. MutableList) get()/set() pair for this compound assign, both
        // halves must dispatch through those member calls instead of the raw
        // array runtime below — otherwise the write silently lands on the
        // receiver's own raw memory layout instead of the container it
        // actually indexes into (bindIndexedCompoundAssignSetOperator only
        // binds this for a non-array-like receiver, so genuine
        // Array<T>/IntArray/... always fall through to the raw path).
        if let getCallBinding = sema.bindings.callBinding(for: exprID),
           let operatorBinding = sema.bindings.indexedCompoundAssignOperatorBinding(for: exprID)
        {
            return lowerIndexedCompoundAssignExprViaCustomOperator(
                exprID,
                op: op,
                receiverExpr: receiverExpr,
                indices: indices,
                valueExpr: valueExpr,
                receiverID: receiverID,
                getCallBinding: getCallBinding,
                operatorBinding: operatorBinding,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }

        // Built-in array compound assign only supports a single Int index
        assert(!indices.isEmpty, "indices must not be empty for indexed compound assign")
        let indexID = driver.lowerExpr(
            indices[0],
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let valueID = driver.lowerExpr(
            valueExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        // Derive element type from the receiver's array type.
        // Mirrors TypeCheckHelpers.arrayElementType logic.
        let receiverBoundType = sema.bindings.exprTypes[receiverExpr]
        // Array<T>'s backing store holds boxed elements for primitive T (mirroring
        // lowerIndexedAccessExpr / lowerIndexedAssignExpr); IntArray/CharArray/...
        // keep storing raw primitives directly. Without unbox-before-op and
        // box-before-store here, a[i] += v on Array<Double>/Array<Boolean>/... reads
        // a boxed pointer as if it were a raw primitive and corrupts the slot with a
        // raw value, breaking every later boxed-aware read of that element.
        let compoundReceiverIsGenericArray = isGenericArrayReceiverType(receiverBoundType, sema: sema, interner: interner)
        let boxingTable = BoxingCalleeTable(interner: interner)
        // Prefer the receiver's own type argument (Array<T>'s T) over the RHS
        // value's type: the RHS may be a narrower type that gets implicitly
        // widened (e.g. an Int literal assigned into an Array<Long> slot), and
        // boxing/unboxing must use the slot's actual element type, not the
        // operand's.
        let compoundPrimitiveElementType: TypeID? = compoundReceiverIsGenericArray
            ? (genericArrayElementType(of: receiverBoundType, sema: sema) ?? arena.exprType(valueID))
            : nil

        let rawGetResult = arena.appendTemporary(type: sema.types.anyType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_get"),
            arguments: [receiverID, indexID],
            result: rawGetResult,
            canThrow: false,
            thrownResult: nil
        ))
        let getResult: KIRExprID
        if let elementType = compoundPrimitiveElementType,
           let unboxCallee = boxingTable.unboxCallee(for: elementType, types: sema.types, requireNonNull: true)
        {
            getResult = emitNonThrowingCall(
                callee: unboxCallee,
                arg: rawGetResult,
                resultType: elementType,
                arena: arena,
                into: &instructions
            )
        } else {
            getResult = rawGetResult
        }
        let opResult = arena.appendTemporary(type: sema.types.anyType)
        // Determine the runtime op stub.
        // Use __kk_string_concat_flat for String += String (matching lowerBinaryExpr pattern),
        // otherwise use the appropriate numeric op stub.
        // Note: exprID's bound type is always unitType for compound assign, so we
        // derive the element type from the receiver's array type instead.
        let stringType = sema.types.stringType
        let receiverElementType = receiverBoundType.flatMap {
            TypeCheckHelpers().arrayElementType(for: $0, sema: sema, interner: interner)
        }
        let isStringElement = receiverElementType == stringType
        let isUnsignedElement = receiverElementType.map { sema.types.isUnsigned($0) } ?? false
        let floatingPointPrefix: String? = if let receiverElementType {
            switch sema.types.kind(of: receiverElementType) {
            case .primitive(.double, _): "d"
            case .primitive(.float, _): "f"
            default: nil
            }
        } else {
            nil
        }
        let opName = if op == .plusAssign, isStringElement {
            "__kk_string_concat_flat"
        } else if let floatingPointPrefix {
            // Compound assignment on Array<Double>/Array<Float> must use the
            // floating-point runtime ABI. The generic integer stubs reinterpret
            // the bit-encoded operands as signed integers and corrupt the result.
            switch op {
            case .plusAssign: "kk_op_\(floatingPointPrefix)add"
            case .minusAssign: "kk_op_\(floatingPointPrefix)sub"
            case .timesAssign: "kk_op_\(floatingPointPrefix)mul"
            case .divAssign: "kk_op_\(floatingPointPrefix)div"
            case .modAssign: "kk_op_\(floatingPointPrefix)mod"
            }
        } else {
            switch op {
            case .plusAssign: "kk_op_add"
            case .minusAssign: "kk_op_sub"
            case .timesAssign: "kk_op_mul"
            case .divAssign: isUnsignedElement ? "kk_op_udiv" : "kk_op_div"
            case .modAssign: isUnsignedElement ? "kk_op_urem" : "kk_op_mod"
            }
        }
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern(opName),
            arguments: [getResult, valueID],
            result: opResult,
            canThrow: false,
            thrownResult: nil
        ))
        let storedOpResult: KIRExprID
        if let elementType = compoundPrimitiveElementType,
           let boxCallee = boxingTable.boxCallee(for: elementType, types: sema.types, requireNonNull: false)
        {
            storedOpResult = emitNonThrowingCall(
                callee: boxCallee,
                arg: opResult,
                resultType: sema.types.anyType,
                arena: arena,
                into: &instructions
            )
        } else {
            storedOpResult = opResult
        }
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_set"),
            arguments: [receiverID, indexID, storedOpResult],
            result: nil,
            canThrow: false,
            thrownResult: nil
        ))
        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    /// Lowers `a[i] op= v` / `a[i]++`/`a[i]--` through the custom (or
    /// source-backed member, e.g. MutableList) get()/set() pair resolved by
    /// LocalDeclTypeChecker+IndexedCompoundAssignAndLocalFunctions.swift's
    /// bindIndexedCompoundAssignSetOperator, instead of the raw array
    /// runtime used by the fallback path in lowerIndexedCompoundAssignExpr:
    ///   1) t = receiver.get(i...)
    ///   2) t' = kk_op_*(t, v)
    ///   3) receiver.set(i..., t')
    /// emitMemberCallInstruction derives each call's own throwing ABI from
    /// its resolved callee, so a throwing custom get()/set() propagates
    /// correctly without special-casing here.
    private func lowerIndexedCompoundAssignExprViaCustomOperator(
        _ exprID: ExprID,
        op: CompoundAssignOp,
        receiverExpr: ExprID,
        indices: [ExprID],
        valueExpr: ExprID,
        receiverID: KIRExprID,
        getCallBinding: CallBinding,
        operatorBinding: IndexedCompoundAssignOperatorBinding,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let loweredIndices = indices.map { indexExpr in
            driver.lowerExpr(
                indexExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }
        let valueID = driver.lowerExpr(
            valueExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        let isSuperCall = sema.bindings.isSuperCallExpr(exprID)
        let elementType = operatorBinding.elementType

        let getResult = arena.appendTemporary(type: elementType)
        emitMemberCallInstruction(
            normalized: driver.callSupportLowerer.normalizedCallArguments(
                providedArguments: loweredIndices,
                callBinding: getCallBinding,
                chosenCallee: getCallBinding.chosenCallee,
                spreadFlags: Array(repeating: false, count: loweredIndices.count),
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            ),
            callBinding: getCallBinding,
            chosenCallee: getCallBinding.chosenCallee,
            calleeName: interner.intern("get"),
            receiver: MemberCallReceiver(expr: receiverExpr, loweredID: receiverID),
            result: getResult,
            isSuperCall: isSuperCall,
            qualifiedSuperType: nil,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions,
            arguments: [receiverID] + loweredIndices
        )

        // Determine the runtime op stub from the get() result's own element
        // type — mirroring the raw-array path below, but keyed off the
        // custom operator's actual return type rather than the receiver's
        // array element type (the receiver here isn't array-shaped).
        let stringType = sema.types.stringType
        let isStringElement = elementType == stringType
        let isUnsignedElement = sema.types.isUnsigned(elementType)
        let floatingPointPrefix: String? = switch sema.types.kind(of: elementType) {
        case .primitive(.double, _): "d"
        case .primitive(.float, _): "f"
        default: nil
        }
        let opName = if op == .plusAssign, isStringElement {
            "__kk_string_concat_flat"
        } else if let floatingPointPrefix {
            switch op {
            case .plusAssign: "kk_op_\(floatingPointPrefix)add"
            case .minusAssign: "kk_op_\(floatingPointPrefix)sub"
            case .timesAssign: "kk_op_\(floatingPointPrefix)mul"
            case .divAssign: "kk_op_\(floatingPointPrefix)div"
            case .modAssign: "kk_op_\(floatingPointPrefix)mod"
            }
        } else {
            switch op {
            case .plusAssign: "kk_op_add"
            case .minusAssign: "kk_op_sub"
            case .timesAssign: "kk_op_mul"
            case .divAssign: isUnsignedElement ? "kk_op_udiv" : "kk_op_div"
            case .modAssign: isUnsignedElement ? "kk_op_urem" : "kk_op_mod"
            }
        }
        let opResult = arena.appendTemporary(type: elementType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern(opName),
            arguments: [getResult, valueID],
            result: opResult,
            canThrow: false,
            thrownResult: nil
        ))

        let setCallBinding = operatorBinding.setCall
        let setArguments = loweredIndices + [opResult]
        let setResult = arena.appendTemporary(type: sema.types.unitType)
        emitMemberCallInstruction(
            normalized: driver.callSupportLowerer.normalizedCallArguments(
                providedArguments: setArguments,
                callBinding: setCallBinding,
                chosenCallee: setCallBinding.chosenCallee,
                spreadFlags: Array(repeating: false, count: setArguments.count),
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            ),
            callBinding: setCallBinding,
            chosenCallee: setCallBinding.chosenCallee,
            calleeName: interner.intern("set"),
            receiver: MemberCallReceiver(expr: receiverExpr, loweredID: receiverID),
            result: setResult,
            isSuperCall: isSuperCall,
            qualifiedSuperType: nil,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions,
            arguments: [receiverID] + setArguments
        )

        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    // NOTE: isSequenceLikeType is defined once in CallLowerer+MemberCalls.swift
    // and shared across all CallLowerer extensions.

    /// True when `receiverType` is the generic `Array<T>` class specifically, as
    /// opposed to one of the specialized primitive array types (IntArray,
    /// CharArray, ...). Array<T>'s backing store holds boxed elements for
    /// primitive T (mirroring List<T>); the primitive-specialized array types
    /// share the same "kk_array_of"/"kk_array_get"/"kk_array_set" runtime entry
    /// points but store raw values and must never be boxed/unboxed.
    func isGenericArrayReceiverType(_ receiverType: TypeID?, sema: SemaModule, interner: StringInterner) -> Bool {
        guard let receiverType,
              let (_, symbol) = resolveClassTypeSymbol(sema.types.makeNonNullable(receiverType), sema: sema)
        else {
            return false
        }
        return interner.resolve(symbol.name) == "Array"
    }

    /// Extracts `T` from a `classType`'s first (invariant/out/in) type
    /// argument, e.g. `Array<T>` or `MutableList<T>`. Returns nil for a star
    /// projection or a non-generic/non-class receiver type.
    func genericArrayElementType(of receiverType: TypeID?, sema: SemaModule) -> TypeID? {
        guard let receiverType,
              case let .classType(classType) = sema.types.kind(of: receiverType),
              let firstArg = classType.args.first
        else {
            return nil
        }
        switch firstArg {
        case let .invariant(t), let .out(t), let .in(t): return t
        case .star: return nil
        }
    }
}
