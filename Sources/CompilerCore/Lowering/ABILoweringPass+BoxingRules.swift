
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
        "kk_mutable_map_put",
        "kk_mutable_map_putAll",
        "kk_mutable_map_getOrPut",
        "kk_mutable_map_plusAssign_pair",
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

        // Nullable → non-null always needs unboxing (box pointer or null sentinel).
        if case let .primitive(sourcePrimitive, .nullable) = sourceKind,
           case let .primitive(targetPrimitive, .nonNull) = targetKind,
           sourcePrimitive == targetPrimitive
        {
            return true
        }
        // Non-null → non-null: skip unboxing only for Double and Float.
        // kk_unbox_double/kk_unbox_float treat the null sentinel (Int.min) as null
        // and return 0, which corrupts -0.0 whose bit pattern equals Int.min.
        // Boolean, Int, Long, Char do not share a valid value with the null sentinel,
        // so their non-null → non-null unboxing is still safe and necessary.
        if case let .primitive(sourcePrimitive, .nonNull) = sourceKind,
           case let .primitive(targetPrimitive, .nonNull) = targetKind,
           sourcePrimitive == targetPrimitive,
           sourcePrimitive != .double, sourcePrimitive != .float
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
        let unboxed = emitNonThrowingCall(
            callee: callee,
            arg: operand,
            resultType: resultType,
            arena: module.arena,
            into: &newBody
        )
        return unboxed
    }

    /// Unbox an operand to its own declared primitive type.
    /// Used for comparison operators (==, !=, <, etc.) where the result type is
    /// Boolean and cannot be used to infer the unboxing target.  If the operand's
    /// declared type is `.primitive(.int, .nonNull)` we emit `kk_unbox_int`;
    /// `kk_unbox_int` is idempotent for already-unboxed values (it checks the
    /// object-pointer registry and returns the raw value unchanged if not found).
    ///
    /// When the operand has no type info in the arena (e.g. the result of an
    /// arithmetic sub-expression whose Sema type was not recorded), `hint` is
    /// used as the target primitive kind instead.  This covers patterns like
    /// `x + 0 == x` where the `+` result has nil arena type but the `x` parameter
    /// has a known Int type.
    func unboxOperandToOwnType(
        _ operand: KIRExprID,
        hint: TypeKind? = nil,
        module: KIRModule,
        types: TypeSystem,
        symbols: SymbolTable?,
        unboxCallees: UnboxingCalleeNames,
        newBody: inout [KIRInstruction]
    ) -> KIRExprID {
        if let expr = module.arena.expr(operand) {
            switch expr {
            case .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral,
                 .floatLiteral, .doubleLiteral, .charLiteral, .boolLiteral:
                return operand
            default:
                break
            }
        }
        let operandType = intrinsicArgType(operand, arena: module.arena, types: types)
        let rawOperandKind: TypeKind? = operandType.map { types.kind(of: $0) }
        let operandKind: TypeKind? = rawOperandKind.map {
            resolveValueClassKind($0, types: types, symbols: symbols)
        }
        // Determine the target kind:
        //   1. Use the operand's own concrete primitive type if available.
        //   2. Fall back to the hint (type of a sibling operand) when the
        //      operand has no type info — this handles arithmetic results whose
        //      Sema type was not recorded in the arena.
        let targetKind: TypeKind
        if let opKind = operandKind, case .primitive(_, .nonNull) = opKind {
            targetKind = opKind
        } else if let hintKind = hint, case .primitive(_, .nonNull) = hintKind {
            targetKind = hintKind
        } else if let opKind = operandKind {
            targetKind = opKind
        } else {
            return operand
        }
        let sourceKind = operandKind ?? targetKind
        guard needsUnboxing(sourceKind: sourceKind, targetKind: targetKind, symbols: symbols),
              let callee = unboxingCallee(
                  sourceKind: sourceKind, targetKind: targetKind,
                  unboxCallees: unboxCallees, types: types, symbols: symbols
              )
        else {
            return operand
        }
        let resultType = operandType ?? types.make(targetKind)
        let unboxed = emitNonThrowingCall(
            callee: callee,
            arg: operand,
            resultType: resultType,
            arena: module.arena,
            into: &newBody
        )
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
