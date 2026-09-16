/// ABI corrections needed while expanding inline bodies that cross an erased
/// function-value boundary.
///
/// Imported inline KIR was ABI-lowered before it was serialized.  Its erased
/// type-parameter and `Any` slots therefore carry boxed values, while the
/// in-process expansion can expose the concrete primitive representation that
/// was inferred at the call site.  This namespace owns only the adapters that
/// restore that contract at the inline boundary; the general ABI lowering pass
/// remains responsible for ordinary calls and copies.
enum InlineErasedLambdaABI {
    /// Runtime entry points that call a function value: the value is an adapter
    /// with the erased convention, so every argument arrives boxed and the
    /// result comes back boxed.
    static let erasedFunctionInvokeCallees: Set<String> = [
        "kk_function_invoke", "kk_function_invoke_0",
        "kk_function_invoke_2", "kk_function_invoke_3",
        "kk_suspend_function_invoke", "kk_suspend_function_invoke_0", "kk_suspend_function_invoke_2",
    ]

    /// Imported inline HOF bodies were ABI-lowered before they were serialized.
    /// Their erased selector results therefore remain boxed when a lowered
    /// floating-point operator consumes them in the caller.
    static func unboxErasedArithmeticArgumentsIfNeeded(
        callee: InternedString,
        arguments: [KIRExprID],
        module: KIRModule,
        ctx: KIRContext,
        into body: inout KIRLoweringEmitContext
    ) -> [KIRExprID] {
        let primitive: PrimitiveType? = switch ctx.interner.resolve(callee) {
        case "kk_op_fadd", "kk_op_fsub", "kk_op_fmul", "kk_op_fdiv": .float
        case "kk_op_dadd", "kk_op_dsub", "kk_op_dmul", "kk_op_ddiv": .double
        default: nil
        }
        guard let primitive, let types = ctx.sema?.types else {
            return arguments
        }
        var normalized = arguments
        for index in arguments.indices {
            let argument = arguments[index]
            let isErasedInvokeResult = body.reversed().contains { instruction in
                guard case let .call(_, invokeCallee, _, callResult, _, _, _, _) = instruction else {
                    return false
                }
                return callResult == argument
                    && Self.erasedFunctionInvokeCallees.contains(ctx.interner.resolve(invokeCallee))
            }
            guard isErasedInvokeResult else { continue }
            let targetType = module.arena.exprType(argument)
                ?? types.make(.primitive(primitive, .nonNull))
            let unboxed = module.arena.appendTemporary(type: targetType)
            body.append(.call(
                symbol: nil,
                callee: ABILoweringPass.primitiveUnboxingCallee(for: primitive, interner: ctx.interner),
                arguments: [argument],
                result: unboxed,
                canThrow: false,
                thrownResult: nil
            ))
            normalized[index] = unboxed
        }
        return normalized
    }

    /// Box the arguments an inline expansion passes to an erased function-value
    /// invoke: type substitution replaced the callee body's erased slots with
    /// concrete primitives, which the adapter would misread as boxed pointers.
    static func boxSubstitutedErasedArguments(
        originalArguments: [KIRExprID],
        loweredArguments: [KIRExprID],
        module: KIRModule,
        ctx: KIRContext,
        into body: inout KIRLoweringEmitContext
    ) -> [KIRExprID] {
        guard originalArguments.count == loweredArguments.count, let types = ctx.sema?.types else {
            return loweredArguments
        }
        var boxed = loweredArguments
        for index in loweredArguments.indices.dropFirst() {
            guard isErasedType(module.arena.exprType(originalArguments[index]), ctx: ctx),
                  let primitive = nonNullPrimitiveKind(
                      of: module.arena.exprType(loweredArguments[index]), ctx: ctx
                  )
            else {
                continue
            }
            let boxedArg = module.arena.appendTemporary(type: types.anyType)
            body.append(.call(
                symbol: nil,
                callee: ABILoweringPass.primitiveBoxingCallee(for: primitive, interner: ctx.interner),
                arguments: [loweredArguments[index]],
                result: boxedArg,
                canThrow: false,
                thrownResult: nil
            ))
            boxed[index] = boxedArg
        }
        return boxed
    }

    /// Counterpart of `boxSubstitutedErasedArguments` for the invoke's result.
    static func substitutedErasedResultUnboxingCallee(
        originalResult: KIRExprID,
        loweredResult: KIRExprID,
        expectedType: TypeID?,
        module: KIRModule,
        ctx: KIRContext
    ) -> InternedString? {
        guard isErasedType(module.arena.exprType(originalResult), ctx: ctx) || expectedType != nil,
              let primitive = nonNullPrimitiveKind(
                  of: expectedType ?? module.arena.exprType(loweredResult),
                  ctx: ctx
              )
        else {
            return nil
        }
        return ABILoweringPass.primitiveUnboxingCallee(for: primitive, interner: ctx.interner)
    }

    static func importedLambdaInvokeReturnType(
        inlineTarget: KIRFunction,
        typeSubstitution: InlineTypeSubstitution?,
        ctx: KIRContext
    ) -> TypeID? {
        guard let types = ctx.sema?.types else { return nil }
        for parameter in inlineTarget.params {
            guard case let .functionType(functionType) = types.kind(of: parameter.type) else {
                continue
            }
            return typeSubstitution?.applying(to: functionType.returnType, in: ctx) ?? functionType.returnType
        }
        return nil
    }

    /// An imported generic higher-order function: its body was ABI-lowered when
    /// the library was built and invokes its lambda through the erased
    /// `kk_function_create_N` convention, so every value that meets an erased
    /// slot in the expansion must be boxed. Imported non-HOF declarations keep
    /// the raw representation their callers already pass.
    static func usesErasedLambdaABI(_ inlineTarget: KIRFunction, ctx: KIRContext) -> Bool {
        guard ctx.sema?.symbols.symbol(inlineTarget.symbol)?.flags.contains(.importedLibrary) == true,
              let types = ctx.sema?.types
        else {
            return false
        }
        return inlineTarget.params.contains { param in
            if case .functionType = types.kind(of: param.type) { return true }
            return false
        }
    }

    /// A type whose values are carried as boxed references once erased: an
    /// unsubstituted type parameter or `Any`.
    private static func isErasedType(_ type: TypeID?, ctx: KIRContext) -> Bool {
        guard let type, let types = ctx.sema?.types else { return false }
        switch types.kind(of: type) {
        case .typeParam, .any:
            return true
        default:
            return false
        }
    }

    private static func nonNullPrimitiveKind(of type: TypeID?, ctx: KIRContext) -> PrimitiveType? {
        guard let type, let types = ctx.sema?.types,
              let symbols = ctx.sema?.symbols
        else {
            return nil
        }
        let resolvedKind = resolveValueClassKind(
            types.kind(of: type),
            types: types,
            symbols: symbols
        )
        guard case let .primitive(primitive, .nonNull) = resolvedKind
        else {
            return nil
        }
        return primitive
    }

    /// Return the concrete primitive type used by an erased lambda ABI slot.
    /// Value-class parameters still retain their nominal type in KIR after
    /// `ValueClassUnboxingPass`; at an erased callback boundary their runtime
    /// representation is nevertheless the underlying primitive.
    private static func nonNullPrimitiveType(of type: TypeID?, ctx: KIRContext) -> TypeID? {
        guard let type, let types = ctx.sema?.types,
              let symbols = ctx.sema?.symbols
        else {
            return nil
        }
        let resolvedKind = resolveValueClassKind(
            types.kind(of: type),
            types: types,
            symbols: symbols
        )
        guard case let .primitive(primitive, .nonNull) = resolvedKind else {
            return nil
        }
        return types.make(.primitive(primitive, .nonNull))
    }

    /// Unbox arguments when a lambda is reached through an erased function
    /// value.  Concrete lambda parameter types determine the required primitive
    /// unboxing callee; nullable and reference values stay boxed.
    static func unboxErasedLambdaArguments(
        arguments: [KIRExprID],
        lambdaFunction: KIRFunction,
        module: KIRModule,
        ctx: KIRContext,
        erasedCallConvention: Bool = false,
        into body: inout KIRLoweringEmitContext
    ) -> [KIRExprID] {
        guard arguments.count == lambdaFunction.params.count else {
            return arguments
        }
        var normalized = arguments
        for index in arguments.indices {
            // Instructions restored from a library's inline KIR carry no expr
            // types, so inside such an expansion every value is erased.
            let argumentIsErased = module.arena.exprType(arguments[index])
                .map { isErasedType($0, ctx: ctx) } ?? erasedCallConvention
            guard argumentIsErased,
                  let primitive = nonNullPrimitiveKind(of: lambdaFunction.params[index].type, ctx: ctx),
                  let unboxedType = nonNullPrimitiveType(of: lambdaFunction.params[index].type, ctx: ctx)
            else {
                continue
            }
            let unboxed = module.arena.appendTemporary(type: unboxedType)
            body.append(.call(
                symbol: nil,
                callee: ABILoweringPass.primitiveUnboxingCallee(for: primitive, interner: ctx.interner),
                arguments: [arguments[index]],
                result: unboxed,
                canThrow: false,
                thrownResult: nil
            ))
            normalized[index] = unboxed
        }
        return normalized
    }

    /// Counterpart of `unboxErasedLambdaArguments`: when the invocation's result
    /// feeds an erased slot, the concrete value the lambda body produced must be
    /// boxed again, preserving a value-class nominal tag when present.
    static func boxErasedLambdaResultIfNeeded(
        returnedExpr: KIRExprID,
        result: KIRExprID,
        module: KIRModule,
        ctx: KIRContext,
        erasedCallConvention: Bool = false,
        into body: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let resultType = module.arena.exprType(result)
        let resultIsErased = resultType.map { isErasedType($0, ctx: ctx) } ?? erasedCallConvention
        guard resultIsErased,
              let sema = ctx.sema,
              let returnedType = module.arena.exprType(returnedExpr)
        else {
            return returnedExpr
        }
        return boxValueForAnySlot(
            returnedExpr,
            sourceType: returnedType,
            types: sema.types,
            symbols: sema.symbols,
            interner: ctx.interner,
            arena: module.arena,
            resultType: resultType ?? sema.types.anyType,
            requireNonNull: true,
            into: &body.instructions
        )
    }

    static func boxPrimitiveArgumentsForErasedParameters(
        arguments: [KIRExprID],
        inlineTarget: KIRFunction,
        module: KIRModule,
        ctx: KIRContext,
        into body: inout KIRLoweringEmitContext
    ) -> [KIRExprID] {
        guard arguments.count == inlineTarget.params.count, let types = ctx.sema?.types else {
            return arguments
        }
        var boxed = arguments
        for index in arguments.indices {
            guard isErasedType(inlineTarget.params[index].type, ctx: ctx),
                  let primitive = nonNullPrimitiveKind(
                      of: module.arena.exprType(arguments[index]), ctx: ctx
                  )
            else {
                continue
            }
            let boxedResult = module.arena.appendTemporary(type: types.anyType)
            body.append(.call(
                symbol: nil,
                callee: ABILoweringPass.primitiveBoxingCallee(for: primitive, interner: ctx.interner),
                arguments: [arguments[index]],
                result: boxedResult,
                canThrow: false,
                thrownResult: nil
            ))
            boxed[index] = boxedResult
        }
        return boxed
    }

    static func unboxErasedInlineResultIfNeeded(
        returnedExpr: KIRExprID,
        result: KIRExprID,
        inlineTarget: KIRFunction,
        module: KIRModule,
        ctx: KIRContext,
        into body: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        guard usesErasedLambdaABI(inlineTarget, ctx: ctx),
              isErasedType(inlineTarget.returnType, ctx: ctx),
              let resultType = module.arena.exprType(result),
              let primitive = nonNullPrimitiveKind(of: resultType, ctx: ctx),
              nonNullPrimitiveKind(of: module.arena.exprType(returnedExpr), ctx: ctx) == nil
        else {
            return returnedExpr
        }
        let unboxed = module.arena.appendTemporary(type: resultType)
        body.append(.call(
            symbol: nil,
            callee: ABILoweringPass.primitiveUnboxingCallee(for: primitive, interner: ctx.interner),
            arguments: [returnedExpr],
            result: unboxed,
            canThrow: false,
            thrownResult: nil
        ))
        return unboxed
    }
}
