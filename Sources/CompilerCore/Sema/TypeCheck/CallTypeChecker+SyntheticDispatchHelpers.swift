extension CallTypeChecker {
    func isLambdaLiteralArg(_ exprID: ExprID, ast: ASTModule) -> Bool {
        guard let argExpr = ast.arena.expr(exprID) else { return false }
        if case .lambdaLiteral = argExpr { return true }
        return false
    }

    func isLambdaOrCallableRefArg(_ exprID: ExprID, ast: ASTModule) -> Bool {
        guard let argExpr = ast.arena.expr(exprID) else { return false }
        switch argExpr {
        case .lambdaLiteral, .callableRef:
            return true
        default:
            return false
        }
    }

    func shouldUseBuiltinFlowFactorySpecialHandling(
        calleeName: InternedString,
        ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> Bool {
        if locals[calleeName] != nil {
            return false
        }
        let visibleCandidates = ctx.cachedScopeLookup(calleeName)
        if visibleCandidates.isEmpty {
            return true
        }
        let hasRealCandidate = visibleCandidates.contains { candidate in
            guard let symbol = ctx.cachedSymbol(candidate),
                  symbol.kind == .function
            else {
                return false
            }
            return !symbol.flags.contains(.synthetic)
        }
        return !hasRealCandidate
    }

    func markSourceBackedCoroutineLauncherArguments(
        _ chosen: SymbolID,
        args: [CallArgument],
        ctx: TypeInferenceContext
    ) {
        guard isSourceBackedProducerFlowBuilder(chosen, ctx: ctx) else { return }
        for argument in args where isLambdaLiteralArg(argument.expr, ast: ctx.ast) {
            ctx.sema.bindings.markCoroutineLauncherLambdaExpr(argument.expr)
        }
    }

    func isSourceBackedProducerFlowBuilder(
        _ symbolID: SymbolID,
        ctx: TypeInferenceContext
    ) -> Bool {
        guard let symbol = ctx.sema.symbols.symbol(symbolID),
              symbol.kind == .function,
              ctx.sema.symbols.isSourceBackedSymbol(symbolID)
        else {
            return false
        }
        if let file = ctx.sema.symbols.sourceFileID(for: symbolID) ?? symbol.declSite?.start.file {
            guard ctx.visibilityChecker.sourceManager?.origin(of: file)?.isBundledStdlib == true else { return false }
        } else {
            guard ctx.sema.symbols.isImportedStdlibSymbol(symbolID) else { return false }
        }
        let interner = ctx.interner
        let channelFlow = interner.intern("channelFlow")
        let callbackFlow = interner.intern("callbackFlow")
        if symbol.name == channelFlow || symbol.name == callbackFlow {
            let flowPackage = [
                interner.intern("kotlinx"),
                interner.intern("coroutines"),
                interner.intern("flow"),
            ]
            let expectedLink = symbol.name == channelFlow ? "kk_channel_flow_create" : "kk_callback_flow_create"
            return symbol.fqName == flowPackage + [symbol.name]
                && ctx.sema.symbols.externalLinkName(for: symbolID) == expectedLink
        }
        let produce = interner.intern("produce")
        let actor = interner.intern("actor")
        if symbol.name == produce || symbol.name == actor {
            let channelsPackage = [
                interner.intern("kotlinx"),
                interner.intern("coroutines"),
                interner.intern("channels"),
            ]
            return symbol.fqName == channelsPackage + [symbol.name]
        }
        let runTest = interner.intern("runTest")
        if symbol.name == runTest {
            let testPackage = [
                interner.intern("kotlinx"),
                interner.intern("coroutines"),
                interner.intern("test"),
            ]
            return symbol.fqName == testPackage + [symbol.name]
                && ctx.sema.symbols.externalLinkName(for: symbolID) == "kk_test_run_blocking"
        }
        return false
    }

    func isShadowedByNonSyntheticSymbol(
        _ name: InternedString,
        locals: LocalBindings,
        ctx: TypeInferenceContext,
        argumentCount: Int? = nil
    ) -> Bool {
        if locals[name] != nil { return true }
        return ctx.cachedScopeLookup(name).contains { candidate in
            guard let sym = ctx.cachedSymbol(candidate) else { return false }
            if let argumentCount {
                guard sym.kind == .function,
                      let signature = ctx.sema.symbols.functionSignature(for: candidate),
                      signature.receiverType == nil,
                      signature.parameterTypes.count == argumentCount
                else {
                    return false
                }
            }
            return !sym.flags.contains(.synthetic)
        }
    }



    func syntheticAtomicArrayClassSymbol(
        _ name: InternedString,
        className: String,
        ctx: TypeInferenceContext
    ) -> SymbolID? {
        let interner = ctx.interner
        let kotlin = interner.intern("kotlin")
        let concurrent = interner.intern("concurrent")
        let atomics = interner.intern("atomics")
        let classNameStr = interner.intern(className)
        let legacyFQ = [kotlin, concurrent, classNameStr]
        let atomicsFQ = [kotlin, concurrent, atomics, classNameStr]
        return ctx.cachedScopeLookup(name).first { candidate in
            guard let sym = ctx.cachedSymbol(candidate),
                  sym.kind == .class,
                  sym.flags.contains(.synthetic)
            else { return false }
            return sym.fqName == legacyFQ || sym.fqName == atomicsFQ
        }
    }

    func hasSourceBackedAtomicArrayFactory(
        _ name: InternedString,
        className: String,
        argumentCount: Int,
        ctx: TypeInferenceContext
    ) -> Bool {
        let interner = ctx.interner
        let kotlin = interner.intern("kotlin")
        let concurrent = interner.intern("concurrent")
        let classNameString = interner.intern(className)
        let expectedFQName = [kotlin, concurrent, interner.intern("atomics"), classNameString]
        return ctx.cachedScopeLookup(name).contains { candidate in
            guard let symbol = ctx.cachedSymbol(candidate),
                  symbol.kind == .function,
                  ctx.sema.symbols.isSourceBackedSymbol(candidate),
                  symbol.fqName == expectedFQName,
                  let signature = ctx.sema.symbols.functionSignature(for: candidate),
                  signature.receiverType == nil,
                  signature.parameterTypes.count == argumentCount
            else {
                return false
            }
            return true
        }
    }

    func sourceOrSyntheticStdlibFunctionSymbol(
        _ name: InternedString,
        fqComponents: [String],
        ctx: TypeInferenceContext
    ) -> SymbolID? {
        let internedFQ = fqComponents.map { ctx.interner.intern($0) }
        var stdlibSymbol: SymbolID?
        for candidate in ctx.cachedScopeLookup(name) {
            guard let symbol = ctx.cachedSymbol(candidate),
                  symbol.kind == .function
            else {
                continue
            }
            if symbol.fqName == internedFQ {
                if symbol.flags.contains(.synthetic) {
                    return candidate
                }
                stdlibSymbol = stdlibSymbol ?? candidate
                continue
            }
            if !symbol.flags.contains(.synthetic) {
                return nil
            }
        }
        return stdlibSymbol
    }

    func qualifiedCalleePath(for exprID: ExprID, ast: ASTModule) -> [InternedString]? {
        guard let expr = ast.arena.expr(exprID) else {
            return nil
        }
        switch expr {
        case let .nameRef(name, _):
            return [name]
        case let .memberCall(receiver, member, _, _, _):
            guard let receiverPath = qualifiedCalleePath(for: receiver, ast: ast) else {
                return nil
            }
            return receiverPath + [member]
        case let .callableRef(receiver, member, _):
            // `(D::f)(d)` invokes a callable-reference *value*; it is not the
            // static call `D.f(d)`, so a receiver-qualified reference must not
            // contribute a callee path (it would collect `D.f` as a candidate
            // and reject the dispatch-receiver argument by arity).
            if receiver != nil { return nil }
            return [member]
        default:
            return nil
        }
    }

    func isQualifiedNamespacePath(for exprID: ExprID, ast: ASTModule) -> Bool {
        guard let expr = ast.arena.expr(exprID) else {
            return false
        }
        switch expr {
        case .nameRef:
            return true
        case let .memberCall(receiver, _, _, args, _):
            return args.isEmpty
                && !ast.arena.isExplicitCall(exprID)
                && isQualifiedNamespacePath(for: receiver, ast: ast)
        default:
            return false
        }
    }
}
