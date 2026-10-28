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
        "kk_suspend_function_invoke", "kk_suspend_function_invoke_0", "kk_suspend_function_invoke_2", "kk_suspend_function_invoke_3", "kk_suspend_function_invoke_4", "kk_suspend_function_invoke_5", "kk_suspend_function_invoke_6",
    ]

    /// Imported inline HOF bodies were ABI-lowered before they were serialized.
    /// Their erased selector results remain boxed even when the lambda body is
    /// spliced into the caller. Floating-point operators consume raw bits.
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
            guard isErasedType(module.arena.exprType(argument), ctx: ctx)
                || isErasedInvokeResult else { continue }
            // The boxed result's Any/type-parameter type describes the handle,
            // not the primitive representation required by this operator.
            let targetType = types.make(.primitive(primitive, .nonNull))
            let unboxed = module.arena.appendTemporary(type: targetType)
            body.append(.call(
                callee: ABILoweringPass.primitiveUnboxingCallee(for: primitive, interner: ctx.interner),
                arguments: [argument],
                result: unboxed,
                canThrow: false
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
            // Same scoping as boxPrimitiveArgumentsForErasedParameters: only a
            // concrete primitive arg gets a plain box here; enum/value-class
            // args stay raw so a later nominal-aware boundary keeps their tag.
            guard isErasedType(module.arena.exprType(originalArguments[index]), ctx: ctx),
                  let loweredType = module.arena.exprType(loweredArguments[index]),
                  case let .primitive(primitive, .nonNull) = types.kind(of: loweredType)
            else {
                continue
            }
            let boxedArg = module.arena.appendTemporary(type: types.anyType)
            body.append(.call(
                callee: ABILoweringPass.primitiveBoxingCallee(for: primitive, interner: ctx.interner),
                arguments: [loweredArguments[index]],
                result: boxedArg,
                canThrow: false
            ))
            boxed[index] = boxedArg
        }
        return boxed
    }

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
        invokedParameter: SymbolID?,
        typeSubstitution: InlineTypeSubstitution?,
        ctx: KIRContext
    ) -> TypeID? {
        guard let types = ctx.sema?.types else { return nil }
        let functionParameters = inlineTarget.params.filter {
            if case .functionType = types.kind(of: $0.type) { return true }
            return false
        }
        // Multi-callback HOFs can return different types from each callback.
        // Restore the invoked parameter's type, never the first selector's.
        let parameter = functionParameters.first { $0.symbol == invokedParameter }
            ?? (invokedParameter == nil && functionParameters.count == 1 ? functionParameters.first : nil)
        if let parameter {
            guard case let .functionType(functionType) = types.kind(of: parameter.type) else {
                return nil
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

    /// Both nullabilities of a resolved primitive kind. Nullable parameters of
    /// a spliced lambda still arrive boxed across the erased boundary and need
    /// the sentinel-aware `kk_unbox_*` (which maps null to the primitive's
    /// null sentinel), not a pass-through.
    private static func primitiveKind(of type: TypeID?, ctx: KIRContext) -> PrimitiveType? {
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
        guard case let .primitive(primitive, _) = resolvedKind
        else {
            return nil
        }
        return primitive
    }

    /// Erased function values arrive boxed, and a nullable primitive can also be
    /// narrowed by a surrounding safe call before it reaches a non-null lambda
    /// parameter.
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
            let parameterType = lambdaFunction.params[index].type
            let argumentType = module.arena.exprType(arguments[index])
            // Instructions restored from a library's inline KIR carry no expr
            // types, so inside such an expansion every value is erased.
            let argumentIsErased = argumentType
                .map { isErasedType($0, ctx: ctx) } ?? erasedCallConvention

            if !argumentIsErased,
               let argumentType,
               let types = ctx.sema?.types,
               case let .primitive(sourcePrimitive, .nullable) = types.kind(of: argumentType),
               case let .primitive(targetPrimitive, .nonNull) = types.kind(of: parameterType),
               sourcePrimitive == targetPrimitive
            {
                // A safe-call branch proves this value is present, but its
                // expression still carries the nullable boxed representation.
                // A typed copy lets ABI lowering unbox it for the lambda's
                // non-null primitive parameter.
                let unboxed = module.arena.appendTemporary(type: parameterType)
                body.append(.copy(from: arguments[index], to: unboxed))
                normalized[index] = unboxed
                continue
            }

            if argumentType == nil, erasedCallConvention,
               primitiveKind(of: parameterType, ctx: ctx) == nil
            {
                // Imported inline bodies omit expression types. Preserve the
                // callback parameter's static type on a local copy so later
                // operations can still unbox a smart-cast Any value (for
                // example `it + 1` after `it is Int`).
                let typedArgument = module.arena.appendTemporary(type: parameterType)
                body.append(.copy(from: arguments[index], to: typedArgument))
                normalized[index] = typedArgument
                continue
            }

            guard argumentIsErased,
                  let primitive = primitiveKind(of: parameterType, ctx: ctx)
            else {
                continue
            }
            let unboxed = module.arena.appendTemporary(type: parameterType)
            body.append(.call(
                callee: ABILoweringPass.primitiveUnboxingCallee(for: primitive, interner: ctx.interner),
                arguments: [arguments[index]],
                result: unboxed,
                canThrow: false
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
            sema: sema,
            cache: ctx.nominalDispatchCache,
            into: &body.instructions
        )
    }

    /// Binds a String argument to an erased (type-parameter or `Any`)
    /// parameter of a spliced body by boxing its flat aggregate into the raw
    /// handle the body's erased slots carry. Substituting the aggregate
    /// directly smears its four fields across the argument registers of
    /// erased consumers such as `kk_function_invoke` adapters and
    /// `kk_any_to_string` (KUU-3195) — the same hazard KUU-3234 fixed for
    /// imported bodies in `boxPrimitiveArgumentsForErasedParameters`, which
    /// already boxes `.stringStruct` arguments through this same
    /// `kk_string_from_flat` bridge before the expansion runs.
    static func bindStringArgumentToErasedParameter(
        _ argument: KIRExprID,
        parameterType: TypeID,
        module: KIRModule,
        ctx: KIRContext,
        into body: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        guard isErasedType(parameterType, ctx: ctx),
              let types = ctx.sema?.types,
              let argumentType = module.arena.exprType(argument),
              case let .stringStruct(nullability) = types.kind(of: argumentType)
        else {
            return argument
        }
        if nullability != .nonNull {
            // A typed copy lets the backend preserve the null sentinel while
            // bridging a nullable flat String to an erased slot.
            let boxed = module.arena.appendTemporary(type: types.nullableAnyType)
            body.append(.copy(from: argument, to: boxed))
            return boxed
        }
        let boxed = module.arena.appendTemporary(type: types.anyType)
        body.append(.call(
            callee: ctx.interner.intern("kk_string_from_flat"),
            arguments: [argument],
            result: boxed,
            canThrow: false
        ))
        return boxed
    }

    /// Binds a non-null enum argument to an interface-typed parameter of a
    /// spliced body through a parameter-typed `copy`, so ABILoweringPass boxes
    /// it (`kk_enum_box_ordinal` + itable registration) the way it boxes the
    /// argument of the equivalent non-inline call. Substituting the raw ordinal
    /// directly would leave an interface member call in the body dispatching
    /// on a bare Int, since nothing downstream sees the enum-to-interface edge.
    static func bindEnumArgumentToInterfaceParameter(
        _ argument: KIRExprID,
        parameterType: TypeID,
        module: KIRModule,
        ctx: KIRContext,
        into body: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        guard let sema = ctx.sema,
              let argumentType = module.arena.exprType(argument),
              case let .classType(argumentClass) = sema.types.kind(of: argumentType),
              argumentClass.nullability == .nonNull,
              let argumentInfo = sema.symbols.symbol(argumentClass.classSymbol),
              argumentInfo.kind == .enumClass,
              !argumentInfo.flags.contains(.synthetic),
              case let .classType(parameterClass) = sema.types.kind(of: parameterType),
              sema.symbols.symbol(parameterClass.classSymbol)?.kind == .interface
        else {
            return argument
        }
        let bound = module.arena.appendTemporary(type: parameterType)
        body.append(.copy(from: argument, to: bound))
        return bound
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
            // Only true primitives need the explicit box: enum and value-class
            // arguments keep their nominal expr type, so the erased slots they
            // reach downstream (e.g. the `__kk_sequence_generate` seed bridge)
            // still see the concrete class and emit `kk_enum_box_ordinal` /
            // `kk_tag_value_class_box` instead of a tagless primitive box.
            guard isErasedType(inlineTarget.params[index].type, ctx: ctx),
                  let argType = module.arena.exprType(arguments[index])
            else {
                continue
            }
            switch types.kind(of: argType) {
            case let .primitive(primitive, .nonNull):
                let boxedResult = module.arena.appendTemporary(type: types.anyType)
                body.append(.call(
                    callee: ABILoweringPass.primitiveBoxingCallee(for: primitive, interner: ctx.interner),
                    arguments: [arguments[index]],
                    result: boxedResult,
                    canThrow: false
                ))
                boxed[index] = boxedResult
            case let .stringStruct(nullability):
                // String arguments arrive as flat aggregates, but an erased
                // parameter slot must carry the boxed handle the imported body
                // unwraps (`kk_string_to_flat` inside e.g. `"x".let { ... }`).
                // Substituting the aggregate directly smears its fields across
                // the call's argument registers (KUU-3234). Nullable arguments
                // also need the null-aware aggregate-to-handle bridge.
                if nullability != .nonNull {
                    let boxedResult = module.arena.appendTemporary(type: types.nullableAnyType)
                    body.append(.copy(from: arguments[index], to: boxedResult))
                    boxed[index] = boxedResult
                    continue
                }
                let boxedResult = module.arena.appendTemporary(type: types.anyType)
                body.append(.call(
                    callee: ctx.interner.intern("kk_string_from_flat"),
                    arguments: [arguments[index]],
                    result: boxedResult,
                    canThrow: false
                ))
                boxed[index] = boxedResult
            default:
                continue
            }
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
        // A reified conversion can return a boxed R without any callback.
        // Restore a specialized result whenever the expansion remains erased;
        // already specialized expressions retain their native representation.
        guard isErasedType(inlineTarget.returnType, ctx: ctx),
              let resultType = module.arena.exprType(result),
              let sema = ctx.sema
        else {
            return returnedExpr
        }

        let returnedType = module.arena.exprType(returnedExpr)
        let resultKind = resolveValueClassKind(
            sema.types.kind(of: resultType),
            types: sema.types,
            symbols: sema.symbols
        )
        if case .stringStruct(.nonNull) = resultKind,
           isErasedType(returnedType, ctx: ctx)
        {
            let unboxed = module.arena.appendTemporary(type: resultType)
            body.append(.call(
                callee: ctx.interner.intern("kk_string_to_flat"),
                arguments: [returnedExpr],
                result: unboxed,
                canThrow: false
            ))
            return unboxed
        }

        guard let primitive = nonNullPrimitiveKind(of: resultType, ctx: ctx),
              nonNullPrimitiveKind(of: returnedType, ctx: ctx) == nil
        else {
            return returnedExpr
        }
        let unboxed = module.arena.appendTemporary(type: resultType)
        body.append(.call(
            callee: ABILoweringPass.primitiveUnboxingCallee(for: primitive, interner: ctx.interner),
            arguments: [returnedExpr],
            result: unboxed,
            canThrow: false
        ))
        return unboxed
    }
}
