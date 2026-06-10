
extension ABILoweringPass {
    /// Callees whose `typeParam`-typed parameter stores the argument verbatim into a
    /// generic container. Because type parameters are erased to Any at runtime, a
    /// primitive argument to one of these must be boxed so it carries its concrete
    /// type (notably `Char`, which would otherwise be stored as a bare code point and
    /// render as a number). This mirrors the collection-literal lowering path, so an
    /// element inserted via `add`/`set` is boxed identically to one created by
    /// `listOf(...)` / `setOf(...)` / `toMutableList()`.
    static let typeParamBoxingBoundaryCallees: Set<String> = [
        "kk_pair_new",
        "kk_triple_new",
        "kk_mutable_list_add",
        "kk_mutable_list_add_at",
        "kk_mutable_list_set",
        "kk_mutable_set_add",
    ]

    func resolveValueClassKind(
        _ kind: TypeKind,
        types: TypeSystem,
        symbols: SymbolTable?
    ) -> TypeKind {
        guard let symbols else { return kind }
        guard case let .classType(classType) = kind,
              classType.nullability == .nonNull
        else {
            return kind
        }
        guard let sym = symbols.symbol(classType.classSymbol),
              sym.flags.contains(.valueType),
              let underlyingType = symbols.valueClassUnderlyingType(for: classType.classSymbol)
        else {
            return kind
        }
        return types.kind(of: underlyingType)
    }

    func boxingCallee(
        argType: TypeID,
        paramType: TypeID,
        callee: InternedString?,
        types: TypeSystem,
        interner: StringInterner,
        boxCallees: BoxingCalleeNames,
        symbols: SymbolTable? = nil
    ) -> InternedString? {
        let rawArgKind = types.kind(of: argType)
        let argKind = resolveValueClassKind(rawArgKind, types: types, symbols: symbols)
        let paramKind = types.kind(of: paramType)

        // Treat Any/Any?, reference types, and type parameters as boxing boundaries.
        // Type parameters are erased to Any at runtime, so primitives must be boxed.
        let isReferenceBoxingBoundary: Bool = {
            if isAnyOrNullableAny(paramKind) {
                return true
            }
            if case .classType = paramKind {
                return true
            }
            if case .typeParam = paramKind {
                // Type parameters are erased to Any at runtime, so a primitive stored
                // into a generic container must be boxed. Otherwise its raw value is
                // indistinguishable from an Int code point — e.g. a Char added to a
                // MutableList would be stored as a bare code point and print as a
                // number rather than the character. We box for the generic containers
                // whose runtime helpers store the element verbatim (Pair/Triple
                // constructors and the mutable-collection element-insertion helpers),
                // keeping `add`/`set` consistent with how `listOf(...)` / `setOf(...)`
                // / `toMutableList()` already box every element.
                if let callee {
                    let calleeName = interner.resolve(callee)
                    if ABILoweringPass.typeParamBoxingBoundaryCallees.contains(calleeName) {
                        return true
                    }
                }
                return false
            }
            return false
        }()

        guard isReferenceBoxingBoundary else {
            if case let .primitive(paramPrimitive, .nullable) = paramKind,
               case let .primitive(argPrimitive, .nonNull) = argKind,
               paramPrimitive == argPrimitive
            {
                switch argPrimitive {
                case .int:
                    return boxCallees.int
                case .long:
                    return boxCallees.long
                case .boolean:
                    return boxCallees.bool
                case .float:
                    return boxCallees.float
                case .double:
                    return boxCallees.double
                case .char:
                    return boxCallees.char
                case .uint, .ubyte, .ushort:
                    return boxCallees.int
                case .ulong:
                    return boxCallees.long
                default:
                    return nil
                }
            }
            return nil
        }

        switch argKind {
        case .primitive(.int, _):
            return boxCallees.int
        case .primitive(.long, _):
            return boxCallees.long
        case .primitive(.boolean, _):
            return boxCallees.bool
        case .primitive(.float, _):
            return boxCallees.float
        case .primitive(.double, _):
            return boxCallees.double
        case .primitive(.char, _):
            return boxCallees.char
        case .primitive(.uint, _), .primitive(.ubyte, _), .primitive(.ushort, _):
            return boxCallees.int
        case .primitive(.ulong, _):
            return boxCallees.long
        default:
            return nil
        }
    }

    func unboxingCallee(
        sourceKind: TypeKind,
        targetKind: TypeKind,
        unboxCallees: UnboxingCalleeNames,
        types: TypeSystem? = nil,
        symbols: SymbolTable? = nil
    ) -> InternedString? {
        let resolvedTargetKind: TypeKind = if let types, let symbols {
            resolveValueClassKind(targetKind, types: types, symbols: symbols)
        } else {
            targetKind
        }
        guard needsUnboxing(sourceKind: sourceKind, targetKind: resolvedTargetKind, symbols: symbols) else {
            return nil
        }

        switch resolvedTargetKind {
        case .primitive(.int, _):
            return unboxCallees.int
        case .primitive(.long, _):
            return unboxCallees.long
        case .primitive(.boolean, _):
            return unboxCallees.bool
        case .primitive(.float, _):
            return unboxCallees.float
        case .primitive(.double, _):
            return unboxCallees.double
        case .primitive(.char, _):
            return unboxCallees.char
        case .primitive(.uint, _), .primitive(.ubyte, _), .primitive(.ushort, _):
            return unboxCallees.int
        case .primitive(.ulong, _):
            return unboxCallees.long
        default:
            return nil
        }
    }

    func intrinsicArgType(
        _ argExprID: KIRExprID,
        arena: KIRArena,
        types: TypeSystem
    ) -> TypeID? {
        if let kind = arena.expr(argExprID) {
            switch kind {
            case .intLiteral:
                return types.make(.primitive(.int, .nonNull))
            case .longLiteral:
                return types.make(.primitive(.long, .nonNull))
            case .uintLiteral:
                return types.make(.primitive(.uint, .nonNull))
            case .ulongLiteral:
                return types.make(.primitive(.ulong, .nonNull))
            case .floatLiteral:
                return types.make(.primitive(.float, .nonNull))
            case .doubleLiteral:
                return types.make(.primitive(.double, .nonNull))
            case .charLiteral:
                return types.make(.primitive(.char, .nonNull))
            case .boolLiteral:
                return types.make(.primitive(.boolean, .nonNull))
            case .stringLiteral:
                return types.make(.primitive(.string, .nonNull))
            default:
                break
            }
        }
        return arena.exprType(argExprID)
    }

    func isAnyOrNullableAny(_ kind: TypeKind) -> Bool {
        if case .any = kind {
            return true
        }
        return false
    }

    func isNonValueClassReference(_ kind: TypeKind, symbols: SymbolTable?) -> Bool {
        guard case let .classType(classType) = kind else { return false }
        // Exclude value classes — they are unboxed to their underlying primitive.
        if let symbols,
           let sym = symbols.symbol(classType.classSymbol),
           sym.flags.contains(.valueType)
        {
            return false
        }
        return true
    }

    func needsUnboxing(
        sourceKind: TypeKind,
        targetKind: TypeKind,
        symbols: SymbolTable? = nil
    ) -> Bool {
        if isAnyOrNullableAny(sourceKind) {
            if case .primitive(_, .nonNull) = targetKind {
                return true
            }
            return false
        }
        // Non-value-class reference type → primitive: unbox (e.g. interface → value class)
        if isNonValueClassReference(sourceKind, symbols: symbols) {
            if case .primitive(_, .nonNull) = targetKind {
                return true
            }
            return false
        }
        if case .typeParam = sourceKind,
           case .primitive(_, .nonNull) = targetKind
        {
            return true
        }

        if case let .primitive(sourcePrimitive, _) = sourceKind,
           case let .primitive(targetPrimitive, .nonNull) = targetKind,
           sourcePrimitive == targetPrimitive
        {
            return true
        }
        return false
    }

    func needsBoxingForCopy(sourceKind: TypeKind, targetKind: TypeKind) -> Bool {
        if case let .primitive(sourcePrimitive, .nonNull) = sourceKind,
           case let .primitive(targetPrimitive, .nullable) = targetKind,
           sourcePrimitive == targetPrimitive
        {
            return true
        }
        return false
    }

    /// Unbox a binary operand if its intrinsic type is Any/reference but the
    /// result expression expects a primitive (smart-cast scenario).
    func unboxBinaryOperandIfNeeded(
        operand: KIRExprID,
        resultExpr: KIRExprID,
        module: KIRModule,
        types: TypeSystem,
        symbols: SymbolTable?,
        unboxCallees: UnboxingCalleeNames,
        newBody: inout [KIRInstruction]
    ) -> KIRExprID {
        // Literal expressions hold raw (never-boxed) values. Inserting kk_unbox_long
        // on a raw Long.MIN_VALUE literal would hit the null-sentinel path and return 0.
        if let expr = module.arena.expr(operand) {
            switch expr {
            case .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral,
                 .floatLiteral, .doubleLiteral, .charLiteral, .boolLiteral:
                return operand
            default:
                break
            }
        }
        guard let operandType = intrinsicArgType(operand, arena: module.arena, types: types),
              let resultType = module.arena.exprType(resultExpr)
        else {
            return operand
        }
        let operandKind = resolveValueClassKind(types.kind(of: operandType), types: types, symbols: symbols)
        let resultKind = resolveValueClassKind(types.kind(of: resultType), types: types, symbols: symbols)
        guard needsUnboxing(sourceKind: operandKind, targetKind: resultKind, symbols: symbols),
              let callee = unboxingCallee(
                  sourceKind: operandKind, targetKind: resultKind,
                  unboxCallees: unboxCallees, types: types, symbols: symbols
              )
        else {
            return operand
        }
        let unboxed = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: resultType
        )
        newBody.append(.call(
            symbol: nil,
            callee: callee,
            arguments: [operand],
            result: unboxed,
            canThrow: false,
            thrownResult: nil
        ))
        return unboxed
    }

    /// Unbox one operand of an equality/comparison builtin (`kk_op_eq`, etc.).
    ///
    /// These callees return `Bool`, so the normal `unboxBinaryOperandIfNeeded`
    /// (which derives the `kk_unbox_*` callee from the *result* type) would
    /// emit `kk_unbox_bool` — wrong for integer comparisons.
    ///
    /// Two situations are handled:
    ///
    /// * **Primitive operand** — derive the unbox callee from the operand's
    ///   own non-null primitive type.  This is the common lambda-parameter
    ///   case: the parameter is typed `Int` in sema, but at runtime it may
    ///   hold a boxed heap pointer because the caller passed a list element
    ///   via `kk_function_invoke`.  `kk_unbox_int` is a safe passthrough for
    ///   values that are already plain integers.
    ///
    /// * **`Any?`/reference operand** — look at the *peer* operand's type to
    ///   find the primitive target.  This arises after `InlineLowering`
    ///   substitutes a `kk_list_iterator_next` result (type `Any?` in the
    ///   arena) for a lambda parameter that was `Int`-typed at
    ///   `OperatorLowering` time; the generated `kk_op_eq` now has a
    ///   mismatched `Any?` argument.
    ///
    /// Pass the *original* (pre-unboxing) peer operand so peer-type lookup
    /// reflects the source instruction rather than an intermediate result.
    func unboxEqualityOperandIfNeeded(
        operand: KIRExprID,
        peerOperand: KIRExprID,
        module: KIRModule,
        types: TypeSystem,
        symbols: SymbolTable?,
        unboxCallees: UnboxingCalleeNames,
        newBody: inout [KIRInstruction]
    ) -> KIRExprID {
        // Literal expressions hold raw (never-boxed) values — skip.
        if let expr = module.arena.expr(operand) {
            switch expr {
            case .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral,
                 .floatLiteral, .doubleLiteral, .charLiteral, .boolLiteral:
                return operand
            default:
                break
            }
        }
        guard let operandType = intrinsicArgType(operand, arena: module.arena, types: types)
        else {
            return operand
        }
        let operandKind = resolveValueClassKind(
            types.kind(of: operandType), types: types, symbols: symbols
        )

        // Determine the unboxing target:
        // (a) primitive operand → own non-null primitive type
        // (b) Any?/reference operand → peer's primitive type (post-inline
        //     substitution replaced an Int-typed sema param with Any?)
        let targetKind: TypeKind
        if case let .primitive(prim, .nonNull) = operandKind {
            targetKind = TypeKind.primitive(prim, .nonNull)
        } else if isAnyOrNullableAny(operandKind)
                    || isNonValueClassReference(operandKind, symbols: symbols) {
            guard let peerType = intrinsicArgType(
                      peerOperand, arena: module.arena, types: types),
                  case let .primitive(peerPrim, .nonNull) = resolveValueClassKind(
                      types.kind(of: peerType), types: types, symbols: symbols)
            else {
                return operand
            }
            targetKind = TypeKind.primitive(peerPrim, .nonNull)
        } else {
            return operand
        }

        guard needsUnboxing(sourceKind: operandKind, targetKind: targetKind, symbols: symbols),
              let callee = unboxingCallee(
                  sourceKind: operandKind, targetKind: targetKind,
                  unboxCallees: unboxCallees, types: types, symbols: symbols
              )
        else {
            return operand
        }
        let unboxed = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: types.make(targetKind)
        )
        newBody.append(.call(
            symbol: nil, callee: callee, arguments: [operand],
            result: unboxed, canThrow: false, thrownResult: nil
        ))
        return unboxed
    }

    func boxCalleeForPrimitive(
        _ kind: TypeKind,
        boxCallees: BoxingCalleeNames
    ) -> InternedString? {
        switch kind {
        case .primitive(.int, .nonNull):
            boxCallees.int
        case .primitive(.long, .nonNull):
            boxCallees.long
        case .primitive(.boolean, .nonNull):
            boxCallees.bool
        case .primitive(.float, .nonNull):
            boxCallees.float
        case .primitive(.double, .nonNull):
            boxCallees.double
        case .primitive(.char, .nonNull):
            boxCallees.char
        case .primitive(.uint, .nonNull), .primitive(.ubyte, .nonNull), .primitive(.ushort, .nonNull):
            boxCallees.int
        case .primitive(.ulong, .nonNull):
            boxCallees.long
        default:
            nil
        }
    }
}
