
extension ControlFlowLowerer {
    private func resolvedLoopCallee(
        for binding: CallBinding,
        sema: SemaModule,
        interner: StringInterner,
        fallback: String
    ) -> InternedString {
        if let linkName = sema.symbols.externalLinkName(for: binding.chosenCallee),
           !linkName.isEmpty {
            return interner.intern(linkName)
        }
        if let symbol = sema.symbols.symbol(binding.chosenCallee) {
            return symbol.name
        }
        return interner.intern(fallback)
    }

    /// Emit a member call for a for-loop iterator/hasNext/next invocation.
    /// Uses virtual dispatch when the chosen callee is a non-external member
    /// of an interface or class, falling back to a direct `.call` otherwise.
    private func emitForLoopMemberCall(
        callBinding: CallBinding,
        fallback: String,
        receiverExpr: ExprID?,
        receiverID: KIRExprID,
        runtimeCalleeOverride: String? = nil,
        result: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        if let runtimeCalleeOverride {
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern(runtimeCalleeOverride),
                arguments: [receiverID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return
        }
        let calleeName = resolvedLoopCallee(for: callBinding, sema: sema, interner: interner, fallback: fallback)
        // The lowered receiver ID supplies the static type when a for-loop
        // member call has no source receiver expression (for example,
        // hasNext()/next() on the materialized iterator temporary).
        //
        // Member functions (class/interface/object) receive their `this` through
        // the virtual call receiver; extension functions receive it as the first
        // explicit argument, so tryEmitVirtualDispatch strips it. Pass the
        // argument list that matches this contract to avoid double receivers.
        let isClassMember: Bool
        let chosenCallee = callBinding.chosenCallee
        if let parentSymbolID = sema.symbols.parentSymbol(for: chosenCallee),
           let parentSymbol = sema.symbols.symbol(parentSymbolID) {
            switch parentSymbol.kind {
            case .class, .interface, .object, .enumClass, .annotationClass:
                isClassMember = true
            default:
                isClassMember = false
            }
        } else {
            isClassMember = false
        }
        let virtualArguments: [KIRExprID] = isClassMember ? [] : [receiverID]
        if let virtualInstruction = driver.callLowerer.tryEmitVirtualDispatch(
            chosenCallee: callBinding.chosenCallee,
            calleeName: calleeName,
            receiverExpr: receiverExpr,
            loweredReceiverID: receiverID,
            isSuperCall: false,
            finalArguments: virtualArguments,
            result: result,
            sema: sema,
            arena: arena,
            interner: interner
        ) {
            instructions.append(virtualInstruction)
        } else {
            instructions.append(.call(
                symbol: callBinding.chosenCallee,
                callee: calleeName,
                arguments: [receiverID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
        }
    }

    func lowerForExpr(
        _ exprID: ExprID,
        iterableExpr: ExprID,
        bodyExpr: ExprID,
        label: InternedString? = nil,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        // KSP-678: `for (v in channel)` lowers through the bundled Kotlin
        // `Channel<T>.iterator()` operator (Channels.kt) via the custom-iterator
        // path below, the same way ranges do, instead of a channel-specific
        // structural lowering.
        let iterableType = sema.bindings.exprTypes[iterableExpr] ?? sema.types.anyType
        // ARCH-012: IntRange has a fixed positive step of one, so a proven
        // closed Int range can use an i64 induction variable without changing
        // the progression iterator semantics. Keep the BUG-198 runtime path
        // below for Long/Char/progression and other signed range shapes.
        if isBuiltInIntRange(
            iterableExpr: iterableExpr,
            iterableType: iterableType,
            ast: ast,
            sema: sema,
            interner: interner
        ) {
            return lowerBuiltInIntRangeForExpr(
                exprID,
                iterableExpr: iterableExpr,
                bodyExpr: bodyExpr,
                label: label,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }
        // BUG-198: Keep the KSP-452 source iterator as the semantic contract, but
        // use a direct runtime loop for the closed signed ranges that the compiler
        // can prove are built-in. The generic iterator path allocates a source
        // iterator object and pays two levels of dispatch on every element. This
        // fast path is deliberately restricted to compiler-marked built-in range
        // expressions and nominal range classes, so custom operators and
        // interface-typed iterables retain their semantics.
        if isBuiltInSignedRange(
            iterableExpr: iterableExpr,
            iterableType: iterableType,
            ast: ast,
            sema: sema,
            interner: interner
        ) {
            return lowerBuiltInSignedRangeForExpr(
                exprID,
                iterableExpr: iterableExpr,
                bodyExpr: bodyExpr,
                label: label,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }
        if let loopBinding = sema.bindings.loopIterationBinding(for: exprID) {
            return lowerCustomForExpr(
                exprID,
                iterableExpr: iterableExpr,
                bodyExpr: bodyExpr,
                label: label,
                loopBinding: loopBinding,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }

        // DEBT-KIR-005: Array types (Array<T>, IntArray, ByteArray, etc.) have no
        // real (non-synthetic) `iterator()` member, so bindLoopIterationOperators
        // never produces a LoopIterationBinding for them (see
        // ControlFlowTypeChecker.bindLoopIterationOperators, which filters out
        // `.synthetic` iterator() candidates). Without that binding they would
        // otherwise fall into the range-iterator intrinsics below, which
        // silently misinterpret the array object as a range and never enter
        // the loop body (hasNext reads unrelated memory as the range bound).
        // Lower directly to an index-based loop instead, matching how arrays
        // are already indexed everywhere else (__kk_array_size / kk_array_get_inbounds).
        if ReceiverClassifier(sema: sema, interner: interner)
            .isArrayLikeType(sema.types.makeNonNullable(iterableType))
        {
            return lowerArrayForExpr(
                exprID,
                iterableExpr: iterableExpr,
                bodyExpr: bodyExpr,
                label: label,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }

        // BUG-167: Iterables whose `iterator()` can only be resolved at runtime
        // (see usesDynamicIteratorDispatch) get no LoopIterationBinding from
        // Sema, so — like arrays above — they would fall into the range
        // intrinsics below, which reinterpret the collection object as a range
        // and yield garbage elements (or none at all). Lower them like an
        // explicit `val it = xs.iterator()` loop instead.
        let nonNullIterableType = sema.types.makeNonNullable(iterableType)
        let isIterableInterfaceResult = ReceiverClassifier(sema: sema, interner: interner)
            .isIterableLikeType(nonNullIterableType)
        if usesDynamicIteratorDispatch(iterableType, sema: sema, interner: interner)
            || isIterableInterfaceResult
        {
            return lowerDynamicIteratorForExpr(
                exprID,
                iterableExpr: iterableExpr,
                bodyExpr: bodyExpr,
                label: label,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }

        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let iterableID = driver.lowerExpr(
            iterableExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let isUIntRangeLike = sema.bindings.isUIntRangeExpr(iterableExpr) || nonNullIterableType == sema.types.uintType
        let isULongRangeLike = sema.bindings.isULongRangeExpr(iterableExpr) || nonNullIterableType == sema.types.ulongType

        // STDLIB-OP-032: Resolve custom operator fun iterator() on the iterable type.
        // If the iterable has a user-defined iterator(), dispatch to it instead of
        // the built-in kk_range_iterator runtime function.
        let customIterator = resolveCustomIteratorOperator(
            iterableType: iterableType,
            sema: sema,
            interner: interner
        ) ?? resolveDirectRangeIteratorOperator(
            iterableExpr: iterableExpr,
            iterableType: iterableType,
            ast: ast,
            sema: sema,
            interner: interner
        )

        // KUU-1420: `for (e in map)` elements are Map.Entry/MutableMap.MutableEntry
        // objects, so map iterables drive the mutable-entry iterator bridge
        // directly. The fused `__kk_map_iterator` intrinsics only yield the raw
        // key; they remain in use for `for ((k, v) in map)` destructuring, where
        // component2 lowers to `map[key]`.
        let isMapElementIteration: Bool = {
            guard let (_, mapSymbol) = resolveClassTypeSymbol(nonNullIterableType, sema: sema)
            else { return false }
            return KnownCompilerNames(interner: interner).isMapLikeSymbol(mapSymbol)
        }()
        let defaultIteratorCallee: InternedString
        let defaultHasNextCallee: InternedString
        let defaultNextCallee: InternedString
        if isMapElementIteration {
            defaultIteratorCallee = interner.intern("__kk_mutable_map_iterator")
            defaultHasNextCallee = interner.intern("__kk_mutable_map_iterator_hasNext")
            defaultNextCallee = interner.intern("__kk_mutable_map_iterator_next")
        } else if isULongRangeLike {
            defaultIteratorCallee = interner.intern("__kk_ulong_range_iterator")
            defaultHasNextCallee = interner.intern("__kk_ulong_range_hasNext")
            defaultNextCallee = interner.intern("__kk_ulong_range_next")
        } else if isUIntRangeLike {
            defaultIteratorCallee = interner.intern("__kk_uint_range_iterator")
            defaultHasNextCallee = interner.intern("__kk_uint_range_hasNext")
            defaultNextCallee = interner.intern("__kk_uint_range_next")
        } else {
            defaultIteratorCallee = interner.intern("kk_range_iterator")
            defaultHasNextCallee = interner.intern("kk_range_hasNext")
            defaultNextCallee = interner.intern("kk_range_next")
        }

        // Preserve the iterator() return type so hasNext()/next() can resolve
        // source-backed Iterator dispatch from the lowered temporary.
        let iteratorID = arena.appendTemporary(
            type: customIterator?.iteratorType ?? sema.types.anyType
        )
        if let customIter = customIterator {
            emitForLoopMemberCall(
                callBinding: CallBinding(
                    chosenCallee: customIter.iteratorSymbol,
                    substitutedTypeArguments: [],
                    parameterMapping: [:]
                ),
                fallback: "iterator",
                receiverExpr: iterableExpr,
                receiverID: iterableID,
                result: iteratorID,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        } else {
            instructions.append(.call(
                symbol: nil,
                callee: defaultIteratorCallee,
                arguments: [iterableID],
                result: iteratorID,
                canThrow: false,
                thrownResult: nil
            ))
        }

        let continueLabel = driver.ctx.makeLoopLabel()
        let breakLabel = driver.ctx.makeLoopLabel()
        instructions.append(.label(continueLabel))

        let hasNextID = arena.appendTemporary(type: boolType)
        if let customIter = customIterator {
            emitForLoopMemberCall(
                callBinding: CallBinding(
                    chosenCallee: customIter.hasNextSymbol,
                    substitutedTypeArguments: [],
                    parameterMapping: [:]
                ),
                fallback: "hasNext",
                receiverExpr: nil,
                receiverID: iteratorID,
                result: hasNextID,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        } else {
            instructions.append(.call(
                symbol: nil,
                callee: defaultHasNextCallee,
                arguments: [iteratorID],
                result: hasNextID,
                canThrow: false,
                thrownResult: nil
            ))
        }
        let falseID = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseID, value: .boolLiteral(false)))
        instructions.append(.jumpIfEqual(lhs: hasNextID, rhs: falseID, target: breakLabel))

        let loopVariableSymbol = sema.bindings.identifierSymbols[exprID]
        let previousLoopValue = loopVariableSymbol.flatMap { driver.ctx.localValue(for: $0) }
        let loopVarType = sema.bindings.flowElementType(forExpr: exprID)
            ?? loopVariableSymbol.flatMap { sema.symbols.propertyType(for: $0) }
            ?? sema.types.anyType
        let nextValueID = arena.appendTemporary(type: loopVarType)
        if let customIter = customIterator {
            emitForLoopMemberCall(
                callBinding: CallBinding(
                    chosenCallee: customIter.nextSymbol,
                    substitutedTypeArguments: [],
                    parameterMapping: [:]
                ),
                fallback: "next",
                receiverExpr: nil,
                receiverID: iteratorID,
                result: nextValueID,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        } else {
            // The map-entry bridge carries an outThrown channel so
            // ConcurrentModificationException propagates instead of degrading
            // to a sentinel element (kk_range_next has no thrown channel).
            instructions.append(.call(
                symbol: nil,
                callee: defaultNextCallee,
                arguments: [iteratorID],
                result: nextValueID,
                canThrow: isMapElementIteration,
                thrownResult: nil
            ))
        }
        if let loopVariableSymbol {
            driver.ctx.setLocalValue(nextValueID, for: loopVariableSymbol)
        }

        driver.ctx.pushLoopControl(continueLabel: continueLabel, breakLabel: breakLabel, name: label)
        _ = driver.lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        _ = driver.ctx.popLoopControl()
        instructions.append(.jump(continueLabel))
        instructions.append(.label(breakLabel))

        if let loopVariableSymbol {
            if let previousLoopValue {
                driver.ctx.setLocalValue(previousLoopValue, for: loopVariableSymbol)
            } else {
                driver.ctx.clearLocalValue(for: loopVariableSymbol)
            }
        }

        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    /// ARCH-012: Restrict the LLVM induction-variable loop to the exact
    /// IntRange contract. Direct `..` expressions are represented as an Int
    /// element type plus a semantic range marker, while a value held in an
    /// IntRange variable retains its nominal class type. `until`, `downTo`,
    /// `step`, Long/Char ranges, and unsigned ranges keep their iterator path.
    private func isBuiltInIntRange(
        iterableExpr: ExprID,
        iterableType: TypeID,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let nonNullType = sema.types.makeNonNullable(iterableType)
        guard nonNullType != sema.types.uintType,
              nonNullType != sema.types.ulongType,
              nonNullType != sema.types.charType,
              !sema.bindings.isUIntRangeExpr(iterableExpr),
              !sema.bindings.isULongRangeExpr(iterableExpr),
              !sema.bindings.isCharRangeExpr(iterableExpr),
              !sema.bindings.isFloatingPointRangeExpr(iterableExpr)
        else {
            return false
        }

        if case let .binary(op, _, _, _) = ast.arena.expr(iterableExpr), op == .rangeTo {
            return nonNullType == sema.types.intType
                && (sema.bindings.isRangeExpr(iterableExpr)
                    || ControlFlowTypeChecker.isRangeExpression(iterableExpr, ast: ast))
        }

        guard let (_, symbol) = resolveClassTypeSymbol(nonNullType, sema: sema),
              isRangeLikeClass(symbol, sema: sema, interner: interner)
        else {
            return false
        }
        return symbol.name == KnownCompilerNames(interner: interner).intRange
    }

    /// ARCH-012: Lower a proven IntRange to an induction variable. The range
    /// Direct `Int..Int` operands are lowered without a range object; a typed
    /// IntRange is materialized once and its bounds are read once. The loop
    /// body then uses only native comparison/addition instructions. The
    /// explicit last-element flag avoids incrementing Int.MAX_VALUE and also
    /// makes `continue` terminate correctly on the final element.
    private func lowerBuiltInIntRangeForExpr(
        _ exprID: ExprID,
        iterableExpr: ExprID,
        bodyExpr: ExprID,
        label: InternedString?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let firstID: KIRExprID
        let lastID: KIRExprID
        if case let .binary(op, lhs, rhs, _) = ast.arena.expr(iterableExpr), op == .rangeTo {
            // A direct `Int..Int` expression has no observable range object
            // between evaluating its operands and entering the loop.
            firstID = driver.lowerExpr(
                lhs,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            lastID = driver.lowerExpr(
                rhs,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        } else {
            let iterableID = driver.lowerExpr(
                iterableExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            firstID = arena.appendTemporary(type: intType)
            emitNonThrowingCall(
                callee: interner.intern("__kk_range_first"),
                arg: iterableID,
                result: firstID,
                into: &instructions
            )
            lastID = arena.appendTemporary(type: intType)
            emitNonThrowingCall(
                callee: interner.intern("__kk_range_last"),
                arg: iterableID,
                result: lastID,
                into: &instructions
            )
        }

        let currentSlot = arena.appendTemporary(type: intType)
        instructions.append(.copy(from: firstID, to: currentSlot))
        // Reading a local yields its storage register, so `lastID` would alias
        // `n` in `for (i in 0..n)` and follow mutations in the body. Kotlin
        // evaluates the bound once; snapshot it into a fresh temporary.
        let lastSnapshotID = arena.appendTemporary(type: intType)
        instructions.append(.copy(from: lastID, to: lastSnapshotID))
        let hasMoreSlot = arena.appendTemporary(type: boolType)
        let trueID = arena.appendExpr(.boolLiteral(true), type: boolType)
        instructions.append(.constValue(result: trueID, value: .boolLiteral(true)))
        instructions.append(.copy(from: trueID, to: hasMoreSlot))

        let continueLabel = driver.ctx.makeLoopLabel()
        let breakLabel = driver.ctx.makeLoopLabel()
        let lastValueLabel = driver.ctx.makeLoopLabel()
        let bodyLabel = driver.ctx.makeLoopLabel()
        instructions.append(.label(continueLabel))

        let falseID = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseID, value: .boolLiteral(false)))
        instructions.append(.jumpIfEqual(lhs: hasMoreSlot, rhs: falseID, target: breakLabel))

        // Compiler-internal aliases are lowered by NativeEmitter to LLVM
        // icmp/add instructions and are never emitted as runtime calls.
        let hasMoreID = arena.appendTemporary(type: boolType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("__kk_int_range_induction_le"),
            arguments: [currentSlot, lastSnapshotID],
            result: hasMoreID,
            canThrow: false,
            thrownResult: nil
        ))
        instructions.append(.jumpIfEqual(lhs: hasMoreID, rhs: falseID, target: breakLabel))

        let loopVariableSymbol = sema.bindings.identifierSymbols[exprID]
        let previousLoopValue = loopVariableSymbol.flatMap { driver.ctx.localValue(for: $0) }
        let loopVarType = sema.bindings.flowElementType(forExpr: exprID)
            ?? loopVariableSymbol.flatMap { sema.symbols.propertyType(for: $0) }
            ?? intType
        let elementID = arena.appendTemporary(type: loopVarType)
        instructions.append(.copy(from: currentSlot, to: elementID))

        // Do not increment after the final element. This is the same
        // monotonicity/overflow guard as IntProgressionIterator.next().
        instructions.append(.jumpIfEqual(lhs: currentSlot, rhs: lastSnapshotID, target: lastValueLabel))
        let oneID = arena.appendExpr(.intLiteral(1), type: intType)
        instructions.append(.constValue(result: oneID, value: .intLiteral(1)))
        let nextValueID = arena.appendTemporary(type: intType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("__kk_int_range_induction_add"),
            arguments: [currentSlot, oneID],
            result: nextValueID,
            canThrow: false,
            thrownResult: nil
        ))
        instructions.append(.copy(from: nextValueID, to: currentSlot))
        instructions.append(.jump(bodyLabel))

        instructions.append(.label(lastValueLabel))
        instructions.append(.copy(from: falseID, to: hasMoreSlot))
        instructions.append(.label(bodyLabel))

        if let loopVariableSymbol {
            driver.ctx.setLocalValue(elementID, for: loopVariableSymbol)
        }
        driver.ctx.pushLoopControl(continueLabel: continueLabel, breakLabel: breakLabel, name: label)
        _ = driver.lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        _ = driver.ctx.popLoopControl()
        instructions.append(.jump(continueLabel))
        instructions.append(.label(breakLabel))

        if let loopVariableSymbol {
            if let previousLoopValue {
                driver.ctx.setLocalValue(previousLoopValue, for: loopVariableSymbol)
            } else {
                driver.ctx.clearLocalValue(for: loopVariableSymbol)
            }
        }

        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    /// BUG-198: Lowers a proven built-in signed range directly through a small
    /// runtime iterator. The runtime implementation follows the monotonicity and
    /// overflow behavior of `RangeIterators.kt` without exposing that fast path to
    /// explicit `range.iterator()` calls or dynamically typed iterables.
    private func lowerBuiltInSignedRangeForExpr(
        _ exprID: ExprID,
        iterableExpr: ExprID,
        bodyExpr: ExprID,
        label: InternedString?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let iterableID = driver.lowerExpr(
            iterableExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        let iteratorID = arena.appendTemporary(type: sema.types.anyType)
        emitNonThrowingCall(
            callee: interner.intern("kk_range_for_in_iterator"),
            arg: iterableID,
            result: iteratorID,
            into: &instructions
        )

        let continueLabel = driver.ctx.makeLoopLabel()
        let breakLabel = driver.ctx.makeLoopLabel()
        instructions.append(.label(continueLabel))

        let hasNextID = arena.appendTemporary(type: boolType)
        emitNonThrowingCall(
            callee: interner.intern("kk_range_for_in_hasNext"),
            arg: iteratorID,
            result: hasNextID,
            into: &instructions
        )
        let falseID = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseID, value: .boolLiteral(false)))
        instructions.append(.jumpIfEqual(lhs: hasNextID, rhs: falseID, target: breakLabel))

        let loopVariableSymbol = sema.bindings.identifierSymbols[exprID]
        let previousLoopValue = loopVariableSymbol.flatMap { driver.ctx.localValue(for: $0) }
        let loopVarType = sema.bindings.flowElementType(forExpr: exprID)
            ?? loopVariableSymbol.flatMap { sema.symbols.propertyType(for: $0) }
            ?? sema.types.anyType
        let nextValueID = arena.appendTemporary(type: loopVarType)
        emitNonThrowingCall(
            callee: interner.intern("kk_range_for_in_next"),
            arg: iteratorID,
            result: nextValueID,
            into: &instructions
        )
        if let loopVariableSymbol {
            driver.ctx.setLocalValue(nextValueID, for: loopVariableSymbol)
        }

        driver.ctx.pushLoopControl(continueLabel: continueLabel, breakLabel: breakLabel, name: label)
        _ = driver.lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        _ = driver.ctx.popLoopControl()
        instructions.append(.jump(continueLabel))
        instructions.append(.label(breakLabel))

        if let loopVariableSymbol {
            if let previousLoopValue {
                driver.ctx.setLocalValue(previousLoopValue, for: loopVariableSymbol)
            } else {
                driver.ctx.clearLocalValue(for: loopVariableSymbol)
            }
        }

        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    /// DEBT-KIR-005: Lowers `for (x in array)` to an index-based loop
    /// (`i = 0; while (i < __kk_array_size(array)) { x = kk_array_get_inbounds(array, i); i += 1; ... }`)
    /// rather than the range-iterator intrinsics used by lowerForExpr's
    /// general path, since arrays have no real `iterator()` member for Sema
    /// to bind (see the DEBT-KIR-005 comment at the lowerForExpr call site).
    /// The index is advanced before the body runs (mirroring how the
    /// iterator-based loop's next() call both reads and advances ahead of
    /// the body) so that `continue` — which jumps back to continueLabel —
    /// re-checks the bound against the already-advanced index.
    private func lowerArrayForExpr(
        _ exprID: ExprID,
        iterableExpr: ExprID,
        bodyExpr: ExprID,
        label: InternedString?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let intType = sema.types.make(.primitive(.int, .nonNull))

        let arrayValueID = driver.lowerExpr(
            iterableExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        // Snapshot the array reference: `for (x in arr)` iterates the array
        // evaluated once, even if the `var` is reassigned inside the body.
        let arrayID = arena.appendTemporary(type: sema.types.anyType)
        instructions.append(.copy(from: arrayValueID, to: arrayID))

        let sizeID = arena.appendTemporary(type: intType)
        emitNonThrowingCall(
            callee: interner.intern("__kk_array_size"),
            arg: arrayID,
            result: sizeID,
            into: &instructions
        )

        let indexSlot = arena.appendTemporary(type: intType)
        let zeroID = arena.appendExpr(.intLiteral(0), type: intType)
        instructions.append(.constValue(result: zeroID, value: .intLiteral(0)))
        instructions.append(.copy(from: zeroID, to: indexSlot))

        let continueLabel = driver.ctx.makeLoopLabel()
        let breakLabel = driver.ctx.makeLoopLabel()
        instructions.append(.label(continueLabel))

        let hasMoreID = arena.appendTemporary(type: boolType)
        instructions.append(.binary(op: .lessThan, lhs: indexSlot, rhs: sizeID, result: hasMoreID))
        let falseID = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseID, value: .boolLiteral(false)))
        instructions.append(.jumpIfEqual(lhs: hasMoreID, rhs: falseID, target: breakLabel))

        let loopVariableSymbol = sema.bindings.identifierSymbols[exprID]
        let previousLoopValue = loopVariableSymbol.flatMap { driver.ctx.localValue(for: $0) }
        let loopVarType = sema.bindings.flowElementType(forExpr: exprID)
            ?? loopVariableSymbol.flatMap { sema.symbols.propertyType(for: $0) }
            ?? sema.types.anyType
        let elementID = arena.appendTemporary(type: loopVarType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_get_inbounds"),
            arguments: [arrayID, indexSlot],
            result: elementID,
            canThrow: false,
            thrownResult: nil
        ))

        let oneID = arena.appendExpr(.intLiteral(1), type: intType)
        instructions.append(.constValue(result: oneID, value: .intLiteral(1)))
        let nextIndexID = arena.appendTemporary(type: intType)
        instructions.append(.binary(op: .add, lhs: indexSlot, rhs: oneID, result: nextIndexID))
        instructions.append(.copy(from: nextIndexID, to: indexSlot))

        if let loopVariableSymbol {
            driver.ctx.setLocalValue(elementID, for: loopVariableSymbol)
        }

        driver.ctx.pushLoopControl(continueLabel: continueLabel, breakLabel: breakLabel, name: label)
        _ = driver.lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        _ = driver.ctx.popLoopControl()
        instructions.append(.jump(continueLabel))
        instructions.append(.label(breakLabel))

        if let loopVariableSymbol {
            if let previousLoopValue {
                driver.ctx.setLocalValue(previousLoopValue, for: loopVariableSymbol)
            } else {
                driver.ctx.clearLocalValue(for: loopVariableSymbol)
            }
        }

        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    /// BUG-167: True when `for (x in type)` must resolve `iterator()`
    /// dynamically because neither `bindLoopIterationOperators` nor
    /// `resolveCustomIteratorOperator` can bind it: the `kotlin.collections`
    /// iterable interfaces (whose `iterator()` is only a synthetic stub), and
    /// source-declared classes implementing `Iterable` whose `iterator()`
    /// override carries no `.operatorFunction` flag of its own (it inherits
    /// `operator` from the interface declaration). Types that do bind an
    /// iterator — and the concrete runtime-backed collections, which the
    /// collection-literal pass rewrites to their own iterator intrinsics —
    /// never reach here.
    private func usesDynamicIteratorDispatch(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let nonNullType = sema.types.makeNonNullable(type)
        if sema.types.isSubtype(nonNullType, sema.types.stringType) {
            return false
        }
        if let charSequenceSymbol = sema.types.charSequenceInterfaceSymbol {
            let charSequenceType = sema.types.make(.classType(ClassType(
                classSymbol: charSequenceSymbol,
                args: [],
                nullability: .nonNull
            )))
            if sema.types.isSubtype(nonNullType, charSequenceType) {
                return false
            }
        }
        if ReceiverClassifier(sema: sema, interner: interner).isIterableInterfaceType(nonNullType) {
            return true
        }
        guard let (classType, symbol) = resolveClassTypeSymbol(nonNullType, sema: sema),
              !symbol.flags.contains(.synthetic),
              // KSP-697: List (and other migrated collection shells) are now
              // Kotlin source-backed, so their class symbol no longer carries
              // `.synthetic`. Without this check they would be mistaken for an
              // arbitrary non-synthetic Iterable-implementing class and lose the
              // dedicated kk_list_iterator_next fast path below.
              !KnownCompilerNames(interner: interner).isCollectionLikeSymbol(symbol),
              resolveCustomIteratorOperator(
                  iterableType: nonNullType,
                  sema: sema,
                  interner: interner
              ) == nil,
              let iterableSymbol = sema.symbols.lookup(fqName: [
                  interner.intern("kotlin"),
                  interner.intern("collections"),
                  interner.intern("Iterable"),
              ])
        else {
            return false
        }
        return driver.ctx.nominalDispatchCache.transitiveInterfaceSupertypes(
            of: classType.classSymbol,
            sema: sema
        )
        .contains(iterableSymbol)
    }

    /// BUG-167/KSP-998: Lowers `for (x in iterable)` for an iterable whose
    /// `iterator()` is only known at runtime. The throwing Iterable bridge keeps
    /// iterator acquisition lazy and preserves source exceptions for the
    /// enclosing Kotlin try/catch. `hasNext()`/`next()` go through the generic
    /// `kk_iterator_*` intrinsics, which handle every iterator representation.
    private func lowerDynamicIteratorForExpr(
        _ exprID: ExprID,
        iterableExpr: ExprID,
        bodyExpr: ExprID,
        label: InternedString?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let iterableID = driver.lowerExpr(
            iterableExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        let iteratorID = arena.appendTemporary(type: sema.types.anyType)
        let thrownResult = arena.appendTemporary(type: sema.types.nullableAnyType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_iterable_iterator"),
            arguments: [iterableID],
            result: iteratorID,
            canThrow: true,
            thrownResult: thrownResult
        ))
        let continueAfterIteratorLabel = driver.ctx.makeLoopLabel()
        let rethrowIteratorLabel = driver.ctx.makeLoopLabel()
        instructions.append(.jumpIfNotNull(value: thrownResult, target: rethrowIteratorLabel))
        instructions.append(.jump(continueAfterIteratorLabel))
        instructions.append(.label(rethrowIteratorLabel))
        instructions.append(.rethrow(value: thrownResult))
        instructions.append(.label(continueAfterIteratorLabel))

        let continueLabel = driver.ctx.makeLoopLabel()
        let breakLabel = driver.ctx.makeLoopLabel()
        instructions.append(.label(continueLabel))

        let hasNextID = arena.appendTemporary(type: boolType)
        emitThrowingCall(
            callee: interner.intern("kk_iterator_hasNext"),
            arg: iteratorID,
            result: hasNextID,
            into: &instructions
        )
        let falseID = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseID, value: .boolLiteral(false)))
        instructions.append(.jumpIfEqual(lhs: hasNextID, rhs: falseID, target: breakLabel))

        let loopVariableSymbol = sema.bindings.identifierSymbols[exprID]
        let previousLoopValue = loopVariableSymbol.flatMap { driver.ctx.localValue(for: $0) }
        let loopVarType = sema.bindings.flowElementType(forExpr: exprID)
            ?? loopVariableSymbol.flatMap { sema.symbols.propertyType(for: $0) }
            ?? sema.types.anyType
        let nextValueID = arena.appendTemporary(type: loopVarType)
        if let unboxCallee = BoxingCalleeTable(interner: interner).unboxCallee(
            for: loopVarType,
            types: sema.types,
            requireNonNull: true
        ) {
            let boxedID = arena.appendTemporary(type: sema.types.anyType)
            emitThrowingCall(
                callee: interner.intern("kk_iterator_next"),
                arg: iteratorID,
                result: boxedID,
                into: &instructions
            )
            emitNonThrowingCall(
                callee: unboxCallee,
                arg: boxedID,
                result: nextValueID,
                into: &instructions
            )
        } else {
            emitThrowingCall(
                callee: interner.intern("kk_iterator_next"),
                arg: iteratorID,
                result: nextValueID,
                into: &instructions
            )
        }
        if let loopVariableSymbol {
            driver.ctx.setLocalValue(nextValueID, for: loopVariableSymbol)
        }

        driver.ctx.pushLoopControl(continueLabel: continueLabel, breakLabel: breakLabel, name: label)
        _ = driver.lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        _ = driver.ctx.popLoopControl()
        instructions.append(.jump(continueLabel))
        instructions.append(.label(breakLabel))

        if let loopVariableSymbol {
            if let previousLoopValue {
                driver.ctx.setLocalValue(previousLoopValue, for: loopVariableSymbol)
            } else {
                driver.ctx.clearLocalValue(for: loopVariableSymbol)
            }
        }

        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    private func lowerCustomForExpr(
        _ exprID: ExprID,
        iterableExpr: ExprID,
        bodyExpr: ExprID,
        label: InternedString?,
        loopBinding: LoopIterationBinding,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let iterableID = driver.lowerExpr(
            iterableExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let iteratorID: KIRExprID
        if let iteratorCall = loopBinding.iteratorCall {
            let iteratorTemp = arena.appendTemporary(type: loopBinding.iteratorType)
            emitForLoopMemberCall(
                callBinding: iteratorCall,
                fallback: "iterator",
                receiverExpr: iterableExpr,
                receiverID: iterableID,
                result: iteratorTemp,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            iteratorID = iteratorTemp
        } else {
            // The iterable value is itself an Iterator; no iterator() call is needed.
            iteratorID = iterableID
        }
        let listIteratorFastPath = concreteListIteratorFastPath(
            loopBinding: loopBinding,
            iterableType: sema.bindings.exprTypes[iterableExpr] ?? sema.types.anyType,
            sema: sema,
            interner: interner
        )

        let continueLabel = driver.ctx.makeLoopLabel()
        let breakLabel = driver.ctx.makeLoopLabel()
        instructions.append(.label(continueLabel))

        let hasNextID = arena.appendTemporary(type: boolType)
        emitForLoopMemberCall(
            callBinding: loopBinding.hasNextCall,
            fallback: "hasNext",
            receiverExpr: nil,
            receiverID: iteratorID,
            runtimeCalleeOverride: listIteratorFastPath?.hasNext,
            result: hasNextID,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        let falseID = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseID, value: .boolLiteral(false)))
        instructions.append(.jumpIfEqual(lhs: hasNextID, rhs: falseID, target: breakLabel))

        let loopVariableSymbol = sema.bindings.identifierSymbols[exprID]
        let previousLoopValue = loopVariableSymbol.flatMap { driver.ctx.localValue(for: $0) }
        let nextValueID = arena.appendTemporary(type: loopBinding.elementType)
        emitForLoopMemberCall(
            callBinding: loopBinding.nextCall,
            fallback: "next",
            receiverExpr: nil,
            receiverID: iteratorID,
            runtimeCalleeOverride: listIteratorFastPath?.next,
            result: nextValueID,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        // The erased Iterator<T>.next ABI may return a boxed Int for Byte and
        // Short elements. Normalize it before arithmetic in source-backed
        // Iterable loops; kk_unbox_int also accepts an already-raw scalar.
        let loopElementID: KIRExprID
        switch sema.types.kind(of: loopBinding.elementType) {
        case .primitive(.byte, .nonNull), .primitive(.short, .nonNull):
            let scalar = arena.appendTemporary(type: loopBinding.elementType)
            emitNonThrowingCall(
                callee: interner.intern("kk_unbox_int"),
                arg: nextValueID,
                result: scalar,
                into: &instructions
            )
            loopElementID = scalar
        default:
            loopElementID = nextValueID
        }
        if let loopVariableSymbol {
            driver.ctx.setLocalValue(loopElementID, for: loopVariableSymbol)
        }

        driver.ctx.pushLoopControl(continueLabel: continueLabel, breakLabel: breakLabel, name: label)
        _ = driver.lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        _ = driver.ctx.popLoopControl()
        instructions.append(.jump(continueLabel))
        instructions.append(.label(breakLabel))

        if let loopVariableSymbol {
            if let previousLoopValue {
                driver.ctx.setLocalValue(previousLoopValue, for: loopVariableSymbol)
            } else {
                driver.ctx.clearLocalValue(for: loopVariableSymbol)
            }
        }

        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    /// Preserve the concrete List for-loop fast path after Collection.iterator
    /// becomes source-backed. Collection/Iterable receivers must keep the
    /// generic iterator ABI because their runtime box can be list- or set-backed.
    private func concreteListIteratorFastPath(
        loopBinding: LoopIterationBinding,
        iterableType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> (hasNext: String, next: String)? {
        guard let iteratorCall = loopBinding.iteratorCall,
              interner.resolve(
                  resolvedLoopCallee(
                      for: iteratorCall,
                      sema: sema,
                      interner: interner,
                      fallback: "iterator"
                  )
              ) == "kk_list_iterator",
              MemberRuntimeDispatch.collectionReceiverKind(
                  receiverType: iterableType,
                  sema: sema,
                  interner: interner
              ) == .list
        else {
            return nil
        }
        return ("kk_list_iterator_hasNext", "kk_list_iterator_next")
    }

    func lowerForDestructuringExpr(
        _ exprID: ExprID,
        names: [InternedString?],
        iterableExpr: ExprID,
        bodyExpr: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        if let loopBinding = sema.bindings.loopIterationBinding(for: exprID) {
            return lowerCustomForDestructuringExpr(
                exprID,
                names: names,
                iterableExpr: iterableExpr,
                bodyExpr: bodyExpr,
                loopBinding: loopBinding,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let iterableID = driver.lowerExpr(
            iterableExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        // STDLIB-OP-032: Resolve custom operator fun iterator() on the iterable type.
        let iterableType = sema.bindings.exprTypes[iterableExpr] ?? sema.types.anyType
        let customIterator = resolveCustomIteratorOperator(
            iterableType: iterableType,
            sema: sema,
            interner: interner
        )
        // BUG-167: `kk_range_*` only understands range and list iterators, so a
        // dynamically resolved `iterator()` needs the generic intrinsics.
        let dynamicIterator = customIterator == nil
            && usesDynamicIteratorDispatch(iterableType, sema: sema, interner: interner)

        // Preserve the iterator() return type so hasNext()/next() can resolve
        // source-backed Iterator dispatch from the lowered temporary.
        let iteratorID = arena.appendTemporary(
            type: customIterator?.iteratorType ?? sema.types.anyType
        )
        if let customIter = customIterator {
            emitForLoopMemberCall(
                callBinding: CallBinding(
                    chosenCallee: customIter.iteratorSymbol,
                    substitutedTypeArguments: [],
                    parameterMapping: [:]
                ),
                fallback: "iterator",
                receiverExpr: iterableExpr,
                receiverID: iterableID,
                result: iteratorID,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        } else {
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_range_iterator"),
                arguments: [iterableID],
                result: iteratorID,
                canThrow: true,
                thrownResult: nil
            ))
        }

        let continueLabel = driver.ctx.makeLoopLabel()
        let breakLabel = driver.ctx.makeLoopLabel()
        instructions.append(.label(continueLabel))

        let hasNextID = arena.appendTemporary(type: boolType)
        if let customIter = customIterator {
            emitForLoopMemberCall(
                callBinding: CallBinding(
                    chosenCallee: customIter.hasNextSymbol,
                    substitutedTypeArguments: [],
                    parameterMapping: [:]
                ),
                fallback: "hasNext",
                receiverExpr: nil,
                receiverID: iteratorID,
                result: hasNextID,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        } else {
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern(dynamicIterator ? "kk_iterator_hasNext" : "kk_range_hasNext"),
                arguments: [iteratorID],
                result: hasNextID,
                canThrow: dynamicIterator,
                thrownResult: nil
            ))
        }
        let falseID = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseID, value: .boolLiteral(false)))
        instructions.append(.jumpIfEqual(lhs: hasNextID, rhs: falseID, target: breakLabel))

        // Get next element
        let nextValueID = arena.appendTemporary(type: sema.types.anyType)
        if let customIter = customIterator {
            emitForLoopMemberCall(
                callBinding: CallBinding(
                    chosenCallee: customIter.nextSymbol,
                    substitutedTypeArguments: [],
                    parameterMapping: [:]
                ),
                fallback: "next",
                receiverExpr: nil,
                receiverID: iteratorID,
                result: nextValueID,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        } else {
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern(dynamicIterator ? "kk_iterator_next" : "kk_range_next"),
                arguments: [iteratorID],
                result: nextValueID,
                canThrow: dynamicIterator,
                thrownResult: nil
            ))
        }

        // Destructure: call componentN on the element
        // Determine the element type so we can resolve external link names (e.g. __kk_pair_first)
        let isRangeExpr = ControlFlowTypeChecker.isRangeExpression(iterableExpr, ast: ast)
        let elementType: TypeID = TypeCheckHelpers().iterableElementType(
            for: iterableType, isRangeExpr: isRangeExpr, sema: sema, interner: interner
        ) ?? sema.types.anyType
        let nonNullElementType = sema.types.makeNonNullable(elementType)

        // Detect if iterating over a Map type. The map iterator yields keys, so
        // for destructuring we need special handling: component1 = key (from next),
        // component2 = kk_map_get(map, key). HashMap and LinkedHashMap are
        // concrete MutableMap subtypes, so use the shared map path for them too.
        let isMapIteration: Bool = {
            guard let (_, sym) = resolveClassTypeSymbol(iterableType, sema: sema),
                  KnownCompilerNames(interner: interner).isMapLikeSymbol(sym)
            else { return false }
            return true
        }()

        var previousValues: [(SymbolID, KIRExprID?)] = []
        for (index, name) in names.enumerated() {
            guard let name else {
                continue
            }
            let componentIndex = index + 1
            let componentName = interner.intern("component\(componentIndex)")

            // Look up the symbol first so we can use the per-component type
            let candidates = sema.symbols.lookupAll(fqName: [
                interner.intern("__for_destructuring_\(exprID.rawValue)"),
                name,
            ])
            let componentType = candidates.first.flatMap { sema.symbols.propertyType(for: $0) } ?? sema.types.anyType
            let componentResult = arena.appendTemporary(type: componentType)

            if isMapIteration, componentIndex == 1 {
                // Map destructuring component1 = key, which is the iterator next value
                instructions.append(.copy(from: nextValueID, to: componentResult))
            } else if isMapIteration, componentIndex == 2 {
                // Map destructuring component2 = value, obtained via __kk_map_get(map, key)
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("__kk_map_get"),
                    arguments: [iterableID, nextValueID],
                    result: componentResult,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                // Resolve componentN to externalLinkName when available (Pair, Triple, etc.)
                let resolved = resolveDestructuringComponentCallee(
                    componentName: componentName,
                    receiverType: nonNullElementType,
                    sema: sema,
                    interner: interner
                )
                driver.callLowerer.emitDestructuringComponentCall(
                    candidate: resolved.candidate,
                    symbol: resolved.symbol,
                    callee: resolved.callee,
                    receiverExpr: nil,
                    receiverID: nextValueID,
                    result: componentResult,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
            }

            if let symbol = candidates.first {
                previousValues.append((symbol, driver.ctx.localValue(for: symbol)))
                driver.ctx.setLocalValue(componentResult, for: symbol)
            }
        }

        let loopLabel = ast.arena.loopLabel(for: exprID)
        driver.ctx.pushLoopControl(continueLabel: continueLabel, breakLabel: breakLabel, name: loopLabel)
        _ = driver.lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        _ = driver.ctx.popLoopControl()
        instructions.append(.jump(continueLabel))
        instructions.append(.label(breakLabel))

        // Restore previous values
        for (symbol, previous) in previousValues {
            if let previous {
                driver.ctx.setLocalValue(previous, for: symbol)
            } else {
                driver.ctx.clearLocalValue(for: symbol)
            }
        }

        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    private func lowerCustomForDestructuringExpr(
        _ exprID: ExprID,
        names: [InternedString?],
        iterableExpr: ExprID,
        bodyExpr: ExprID,
        loopBinding: LoopIterationBinding,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let iterableID = driver.lowerExpr(
            iterableExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let iteratorID: KIRExprID
        if let iteratorCall = loopBinding.iteratorCall {
            let iteratorTemp = arena.appendTemporary(type: loopBinding.iteratorType)
            emitForLoopMemberCall(
                callBinding: iteratorCall,
                fallback: "iterator",
                receiverExpr: iterableExpr,
                receiverID: iterableID,
                result: iteratorTemp,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            iteratorID = iteratorTemp
        } else {
            // The iterable value is itself an Iterator; no iterator() call is needed.
            iteratorID = iterableID
        }
        let listIteratorFastPath = concreteListIteratorFastPath(
            loopBinding: loopBinding,
            iterableType: sema.bindings.exprTypes[iterableExpr] ?? sema.types.anyType,
            sema: sema,
            interner: interner
        )

        let continueLabel = driver.ctx.makeLoopLabel()
        let breakLabel = driver.ctx.makeLoopLabel()
        instructions.append(.label(continueLabel))

        let hasNextID = arena.appendTemporary(type: boolType)
        emitForLoopMemberCall(
            callBinding: loopBinding.hasNextCall,
            fallback: "hasNext",
            receiverExpr: nil,
            receiverID: iteratorID,
            runtimeCalleeOverride: listIteratorFastPath?.hasNext,
            result: hasNextID,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        let falseID = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseID, value: .boolLiteral(false)))
        instructions.append(.jumpIfEqual(lhs: hasNextID, rhs: falseID, target: breakLabel))

        let nextValueID = arena.appendTemporary(type: loopBinding.elementType)
        emitForLoopMemberCall(
            callBinding: loopBinding.nextCall,
            fallback: "next",
            receiverExpr: nil,
            receiverID: iteratorID,
            runtimeCalleeOverride: listIteratorFastPath?.next,
            result: nextValueID,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )

        let nonNullElementType = sema.types.makeNonNullable(loopBinding.elementType)
        var previousValues: [(SymbolID, KIRExprID?)] = []
        for (index, name) in names.enumerated() {
            guard let name else {
                continue
            }
            let componentIndex = index + 1
            let componentName = interner.intern("component\(componentIndex)")
            let candidates = sema.symbols.lookupAll(fqName: [
                interner.intern("__for_destructuring_\(exprID.rawValue)"),
                name,
            ])
            let componentType = candidates.first.flatMap { sema.symbols.propertyType(for: $0) } ?? sema.types.anyType
            let componentResult = arena.appendTemporary(type: componentType)

            let resolved = resolveDestructuringComponentCallee(
                componentName: componentName,
                receiverType: nonNullElementType,
                sema: sema,
                interner: interner
            )
            driver.callLowerer.emitDestructuringComponentCall(
                candidate: resolved.candidate,
                symbol: resolved.symbol,
                callee: resolved.callee,
                receiverExpr: nil,
                receiverID: nextValueID,
                result: componentResult,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )

            if let symbol = candidates.first {
                previousValues.append((symbol, driver.ctx.localValue(for: symbol)))
                driver.ctx.setLocalValue(componentResult, for: symbol)
            }
        }

        let loopLabel = ast.arena.loopLabel(for: exprID)
        driver.ctx.pushLoopControl(continueLabel: continueLabel, breakLabel: breakLabel, name: loopLabel)
        _ = driver.lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        _ = driver.ctx.popLoopControl()
        instructions.append(.jump(continueLabel))
        instructions.append(.label(breakLabel))

        for (symbol, previous) in previousValues {
            if let previous {
                driver.ctx.setLocalValue(previous, for: symbol)
            } else {
                driver.ctx.clearLocalValue(for: symbol)
            }
        }

        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }
}
