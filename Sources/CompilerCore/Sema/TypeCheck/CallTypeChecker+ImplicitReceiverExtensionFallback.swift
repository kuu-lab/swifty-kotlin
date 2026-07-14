extension CallTypeChecker {
    func tryBindImplicitReceiverSyntheticExtensionCall(
        _ id: ExprID,
        calleeName: InternedString,
        receiverType: TypeID,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID]
    ) -> TypeID? {
        let sema = ctx.sema
        let nonNullReceiver = sema.types.makeNonNullable(receiverType)
        var seen: Set<SymbolID> = []

        func matches(_ candidate: SymbolID, requireSynthetic: Bool) -> Bool {
            guard seen.insert(candidate).inserted,
                  let symbol = ctx.cachedSymbol(candidate),
                  symbol.kind == .function,
                  requireSynthetic == false || symbol.flags.contains(.synthetic),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  let receiver = signature.receiverType
            else { return false }
            if let parentID = sema.symbols.parentSymbol(for: candidate),
               let parent = sema.symbols.symbol(parentID),
               parent.kind == .property
            {
                return false
            }
            return extensionSyntheticFallbackReceiverMatches(
                callSiteReceiver: nonNullReceiver,
                declaredReceiver: receiver,
                sema: sema
            )
        }

        var candidates = ctx.cachedScopeLookup(calleeName).filter {
            matches($0, requireSynthetic: false)
        }
        candidates.append(contentsOf: sema.symbols.lookupByShortName(calleeName).filter {
            matches($0, requireSynthetic: true)
        })
        guard !candidates.isEmpty else { return nil }

        let argTypes = args.map { argument in
            driver.inferExpr(argument.expr, ctx: ctx, locals: &locals)
        }
        let resolvedArgs = zip(args, argTypes).map { argument, type in
            CallArg(label: argument.label, isSpread: argument.isSpread, type: type)
        }
        let resolved = ctx.resolver.resolveCall(
            candidates: candidates,
            call: CallExpr(
                range: range,
                calleeName: calleeName,
                args: resolvedArgs,
                explicitTypeArgs: explicitTypeArgs
            ),
            expectedType: expectedType,
            implicitReceiverType: nonNullReceiver,
            ctx: ctx.semaCtx
        )
        if let diagnostic = resolved.diagnostic {
            ctx.semaCtx.diagnostics.emit(diagnostic)
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        guard let chosen = resolved.chosenCallee else { return nil }

        let resultType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
        sema.bindings.markImplicitReceiverMember(id, name: calleeName)
        sema.bindings.bindExprType(id, type: resultType)
        return resultType
    }
}
