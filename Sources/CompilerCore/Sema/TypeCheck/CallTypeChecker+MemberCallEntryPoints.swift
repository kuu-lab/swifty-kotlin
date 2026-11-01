extension CallTypeChecker {
    func inferMemberCallExpr(
        _ id: ExprID, receiverID: ExprID, calleeName: InternedString,
        args: [CallArgument], range: SourceRange, ctx: TypeInferenceContext,
        locals: inout LocalBindings, expectedType: TypeID?, explicitTypeArgs: [TypeID] = []
    ) -> TypeID {
        // Same foreign-typeParam guard as `inferCallExpr`: an enclosing
        // call's own inference variable must not reach the callee as a
        // same-symbol pin target (e.g. `xs.listOf(x.listOf(y))`).
        var memberExpectedType = expectedType
        if let expected = expectedType {
            memberExpectedType = dropForeignTypeParamExpectedType(expected, ctx: ctx)
        }
        let result = inferMemberCallImpl(
            id, receiverID: receiverID, calleeName: calleeName,
            args: args, range: range, ctx: ctx, locals: &locals,
            expectedType: memberExpectedType, explicitTypeArgs: explicitTypeArgs,
            safeCall: false
        )
        guard ctx.ast.arena.isInfixCall(id), result != ctx.sema.types.errorType else {
            return result
        }
        let isPrimitiveIntrinsic = isInfixPrimitiveIntrinsic(
            calleeName, receiverType: ctx.sema.bindings.exprType(for: receiverID), ctx: ctx
        )
        let isInfix: Bool
        if let binding = ctx.sema.bindings.callBindings[id] {
            let isUnsignedComparableCompareTo = isPrimitiveIntrinsic
                && ctx.interner.resolve(calleeName) == "compareTo"
                && ctx.sema.symbols.parentSymbol(for: binding.chosenCallee) == ctx.sema.types.comparableInterfaceSymbol
            isInfix = ctx.sema.symbols.symbol(binding.chosenCallee)?.flags.contains(.infixFunction) == true
                || isUnsignedComparableCompareTo
        } else {
            isInfix = isPrimitiveIntrinsic
        }
        guard isInfix else {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0307",
                "'infix' modifier is required on '\(ctx.interner.resolve(calleeName))'.",
                range: range
            )
            ctx.sema.bindings.bindExprType(id, type: ctx.sema.types.errorType)
            return ctx.sema.types.errorType
        }
        return result
    }

    /// Only Kotlin-approved primitive bitwise/shift members and UInt/ULong
    /// compareTo have infix eligibility; arithmetic names must resolve extensions.
    func isInfixPrimitiveIntrinsic(
        _ calleeName: InternedString, receiverType: TypeID?, ctx: TypeInferenceContext
    ) -> Bool {
        let name = ctx.interner.resolve(calleeName)
        switch receiverType.map({ ctx.sema.types.kind(of: $0) }) {
        case .primitive(.int, .nonNull), .primitive(.long, .nonNull):
            return ["and", "or", "xor", "shl", "shr", "ushr"].contains(name)
        case .primitive(.boolean, .nonNull):
            return ["and", "or", "xor"].contains(name)
        case .primitive(.uint, .nonNull), .primitive(.ulong, .nonNull):
            return ["and", "or", "xor", "shl", "shr"].contains(name)
                || name == "compareTo"
        case .primitive(.ubyte, .nonNull), .primitive(.ushort, .nonNull):
            return ["and", "or", "xor", "shl", "shr"].contains(name)
        default:
            return false
        }
    }

    func inferSafeMemberCallExpr(
        _ id: ExprID, receiverID: ExprID, calleeName: InternedString,
        args: [CallArgument], range: SourceRange, ctx: TypeInferenceContext,
        locals: inout LocalBindings, expectedType: TypeID?, explicitTypeArgs: [TypeID] = []
    ) -> TypeID {
        inferMemberCallImpl(
            id, receiverID: receiverID, calleeName: calleeName,
            args: args, range: range, ctx: ctx, locals: &locals,
            expectedType: expectedType.flatMap {
                dropForeignTypeParamExpectedType($0, ctx: ctx)
            }, explicitTypeArgs: explicitTypeArgs,
            safeCall: true
        )
    }
}
