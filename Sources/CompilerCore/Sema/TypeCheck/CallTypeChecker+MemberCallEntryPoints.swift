/// Member-call entry points: `inferMemberCallExpr` (including `infix`
/// modifier enforcement for infix-spelled calls) and `inferSafeMemberCallExpr`,
/// both delegating to `inferMemberCallImpl`.
///
/// Split out from `CallTypeChecker.swift`.
extension CallTypeChecker {
    /// Build `List<elementType>` for synthetic stdlib member-call inference.
    /// Falls back to `Any` when `kotlin.collections.List` is not registered.

    func inferMemberCallExpr(
        _ id: ExprID, receiverID: ExprID, calleeName: InternedString,
        args: [CallArgument], range: SourceRange, ctx: TypeInferenceContext,
        locals: inout LocalBindings, expectedType: TypeID?, explicitTypeArgs: [TypeID] = []
    ) -> TypeID {
        let result = inferMemberCallImpl(
            id, receiverID: receiverID, calleeName: calleeName,
            args: args, range: range, ctx: ctx, locals: &locals,
            expectedType: expectedType, explicitTypeArgs: explicitTypeArgs,
            safeCall: false
        )
        guard ctx.ast.arena.isInfixCall(id), result != ctx.sema.types.errorType else {
            return result
        }
        let isInfix: Bool
        if let binding = ctx.sema.bindings.callBindings[id] {
            isInfix = ctx.sema.symbols.symbol(binding.chosenCallee)?.flags.contains(.infixFunction) == true
        } else {
            // Primitive intrinsics have no callable symbol. Only their bitwise
            // and shift functions support infix notation.
            let name = ctx.interner.resolve(calleeName)
            let receiverType = ctx.sema.bindings.exprType(for: receiverID)
            let primitive = receiverType.map { ctx.sema.types.kind(of: $0) }
            switch primitive {
            case .primitive(.int, .nonNull), .primitive(.long, .nonNull):
                isInfix = ["and", "or", "xor", "shl", "shr", "ushr"].contains(name)
            case .primitive(.boolean, .nonNull):
                isInfix = ["and", "or", "xor"].contains(name)
            case .primitive(.uint, .nonNull), .primitive(.ulong, .nonNull),
                 .primitive(.ubyte, .nonNull), .primitive(.ushort, .nonNull):
                isInfix = ["and", "or", "xor", "shl", "shr"].contains(name)
            default:
                isInfix = false
            }
        }
        guard isInfix else {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0307",
                "'infix' modifier is required on '\(ctx.interner.resolve(calleeName))'.",
                range: range
            )
            ctx.sema.bindings.bindExprType(id, type: ctx.sema.types.errorType)
            return ctx.sema.types.errorType
        }
        return result
    }

    func inferSafeMemberCallExpr(
        _ id: ExprID, receiverID: ExprID, calleeName: InternedString,
        args: [CallArgument], range: SourceRange, ctx: TypeInferenceContext,
        locals: inout LocalBindings, expectedType: TypeID?, explicitTypeArgs: [TypeID] = []
    ) -> TypeID {
        inferMemberCallImpl(
            id, receiverID: receiverID, calleeName: calleeName,
            args: args, range: range, ctx: ctx, locals: &locals,
            expectedType: expectedType, explicitTypeArgs: explicitTypeArgs,
            safeCall: true
        )
    }
}
