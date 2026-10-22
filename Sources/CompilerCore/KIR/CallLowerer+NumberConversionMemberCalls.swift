
/// Lowering for `Number.toDouble()`/`toFloat()`/`toLong()`/`toInt()`/`toShort()`/
/// `toByte()`/`toChar()` when the receiver's static type is the abstract
/// `kotlin.Number` class itself (a `Number`-typed local/parameter, or an
/// erased `T : Number` type parameter) rather than a concrete primitive.
///
/// None of the built-in primitive types (Int/Long/Double/Float/Short/Byte)
/// register as a genuine overriding *class* in the symbol table — they
/// conform to `Number` only through the hardcoded subtyping rule in
/// Subtyping.swift, never through a compiled `override fun toDouble()`. So
/// Sema resolves a call like this to the abstract `Number.toDouble`
/// declaration itself (Numbers.kt), and `resolveVtableDispatch` only finds a
/// vtable slot for it once at least one *user-defined* `Number` subtype is
/// visible in the program (`directSubtypes(of:)` is non-empty); with none
/// visible it declines and the call falls through to a direct call on the
/// abstract declaration's own body, which — being abstract — has no real
/// implementation and compiles down to a stub that just returns zero.
///
/// Forcing vtable dispatch unconditionally does not fix this either: the
/// built-in box types (RuntimeIntBox et al.) are hand-written Swift classes
/// with no compiler-synthesized class metadata, so a vtable slot lookup on
/// one of them faults at runtime (KSWIFTK-RUNTIME-0001).
///
/// This intercepts the call before either path and routes it to
/// `kk_number_to_primitive`, mirroring how `kk_compare_any` handles the
/// analogous erased-`Comparable` dispatch problem (BUG-170, PR #5115): check
/// the receiver's runtime tag first and perform the native primitive
/// conversion directly for a recognized box, and only fall back to genuine
/// vtable dispatch for a real user-defined `Number` subclass instance.
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

        // Guard against a concrete-but-unboxed receiver reaching this path
        // with a raw scalar instead of a heap-boxed value: only fire when the
        // receiver's static type is genuinely erased — either `Number` itself
        // or a type parameter — never a resolved concrete class/primitive.
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
            // A successful null check narrows nullable-bound T to T & Any.
            // Preserve erased Number dispatch through that definitely-non-null view.
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
                symbol: nil,
                callee: interner.intern("kk_number_to_primitive"),
                arguments: [receiverID, slotExpr, kindExpr],
                result: callResult,
                canThrow: false,
                thrownResult: nil
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
            symbol: nil,
            callee: interner.intern("kk_number_to_primitive"),
            arguments: [receiverID, slotExpr, kindExpr],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return result
    }
}
