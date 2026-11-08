extension CallTypeChecker {
    /// Member operators precede receiver-scoped extensions, which precede
    /// extensions found in the current lexical/import scope.
    func nominalCallablePropertyInvokeCandidates(
        _ type: TypeID, request: MemberCallInferenceRequest, argTypes: [TypeID], locals: LocalBindings
    ) -> [SymbolID] {
        let invoke = request.ctx.interner.intern("invoke")
        let visibleOperator: (SymbolID) -> Bool = { candidate in
            guard let symbol = request.sema.symbols.symbol(candidate) else { return false }
            return symbol.flags.contains(.operatorFunction)
                && request.ctx.visibilityChecker.isAccessible(symbol, fromFile: request.ctx.currentFileID, enclosingClass: request.ctx.enclosingClassSymbol)
        }
        let members = driver.helpers.collectMemberFunctionCandidates(
            named: invoke, receiverType: type, sema: request.sema, interner: request.ctx.interner
        ).filter(visibleOperator)
        let nonNullType = request.sema.types.makeNonNullable(type)
        let dispatchExtensions = collectDispatchReceiverMemberExtensionCandidates(
            named: invoke, extensionReceiverType: nonNullType, ctx: request.ctx
        ).filter(visibleOperator)
        let scopedExtensions = request.ctx.cachedScopeLookup(invoke).filter { candidate in
            guard visibleOperator(candidate),
                  let signature = request.sema.symbols.functionSignature(for: candidate),
                  let declaredReceiver = signature.receiverType
            else { return false }
            return extensionSyntheticFallbackReceiverMatches(
                callSiteReceiver: nonNullType, declaredReceiver: declaredReceiver, sema: request.sema
            )
        }

        var firstCandidateTier: [SymbolID]?
        for candidates in [members, dispatchExtensions, scopedExtensions] where !candidates.isEmpty {
            if firstCandidateTier == nil { firstCandidateTier = candidates }
            if nominalCallablePropertyCandidatesAcceptArgumentShape(
                candidates, receiverType: type, request: request, argTypes: argTypes, locals: locals
            ) {
                return candidates
            }
        }
        // Preserve the best diagnostic when every tier has candidates but none
        // accepts this call shape.
        return firstCandidateTier ?? []
    }

    /// Probe member invoke signatures without checking a losing lambda body.
    /// Defaults, named arguments, varargs and type arguments retain the ordinary
    /// overload resolver's mapping and constraints.
    func nominalCallablePropertyAcceptsArgumentShape(
        _ type: TypeID, request: MemberCallInferenceRequest, argTypes: [TypeID], locals: LocalBindings
    ) -> Bool {
        !nominalCallablePropertyInvokeCandidates(
            type, request: request, argTypes: argTypes, locals: locals
        ).isEmpty
    }

    func nominalCallablePropertyCandidatesAcceptArgumentShape(
        _ candidates: [SymbolID], receiverType: TypeID, request: MemberCallInferenceRequest,
        argTypes: [TypeID], locals: LocalBindings
    ) -> Bool {
        let invoke = request.ctx.interner.intern("invoke")
        let callArgs = zip(request.args, argTypes).map { argument, type in
            CallArg.source(argument, type: type, callRange: request.range, ast: request.ctx.ast)
        }
        for candidate in candidates {
            guard let signature = request.sema.symbols.functionSignature(for: candidate),
                  let mapping = request.ctx.resolver.buildParameterMapping(
                    signature: signature, callArgs: callArgs, symbols: request.sema.symbols, typeSystem: request.sema.types,
                    isCallableArgument: { self.isLambdaOrCallableRefArg(request.args[$0].expr, ast: request.ctx.ast) }
                  ) else { continue }
            var replacements: [Int: TypeID] = [:]
            var matches = true
            for (index, argument) in request.args.enumerated() {
                guard let parameterIndex = mapping[index], parameterIndex < signature.parameterTypes.count else {
                    matches = false
                    break
                }
                var parameter = signature.parameterTypes[parameterIndex]
                if let owner = request.sema.symbols.parentSymbol(for: candidate) {
                    parameter = driver.helpers.resolveMemberPropertyType(
                        parameter, receiverType: receiverType, ownerSymbol: owner, sema: request.sema
                    )
                }
                switch request.ctx.ast.arena.expr(argument.expr) {
                case let .lambdaLiteral(params, _, _, _):
                    if let function = callableArgumentFunctionType(parameter, ctx: request.ctx) {
                        if params.isEmpty ? function.params.count > 1 : params.count != function.params.count {
                            matches = false
                        }
                    } else if !callableArgumentAcceptsUnknownArity(parameter, isReference: false, ctx: request.ctx) {
                        matches = false
                    }
                    replacements[index] = parameter
                case .callableRef:
                    matches = matches && callableReferenceAcceptsArgumentType(
                        argument.expr, parameter: parameter, ctx: request.ctx, locals: locals
                    )
                    replacements[index] = parameter
                default:
                    if integerLiteralFitsParameter(argument.expr, parameterType: parameter, ctx: request.ctx) {
                        replacements[index] = parameter
                    }
                }
            }
            guard matches else { continue }
            let probe = request.ctx.resolver.probeCall(
                candidates: [candidate],
                call: CallExpr(range: request.range, calleeName: invoke, args: callArgs, explicitTypeArgs: request.explicitTypeArgs),
                expectedType: nil, implicitReceiverType: receiverType,
                candidateArgumentTypes: [candidate: replacements], ctx: request.ctx.sema
            )
            if !probe.viableCandidates.isEmpty { return true }
        }
        return false
    }
}
