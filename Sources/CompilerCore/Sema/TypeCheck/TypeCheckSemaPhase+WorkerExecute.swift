extension TypeCheckSemaPhase {
    /// Kotlin/Native executes producer on the caller, but sends only a static
    /// job entry to the worker. Validate after all lambda captures are known.
    func validateWorkerExecuteJobs(ast: ASTModule, sema: SemaModule, ctx: CompilationContext) {
        let fqName = ["kotlin", "native", "concurrent", "execute"].map(ctx.interner.intern)
        for (exprID, binding) in sema.bindings.callBindings.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            guard let symbol = sema.symbols.symbol(binding.chosenCallee),
                  symbol.fqName == fqName,
                  sema.symbols.isSourceBackedSymbol(binding.chosenCallee)
            else { continue }
            if let file = symbol.declSite?.start.file,
               ctx.sourceManager.origin(of: file) != .bundledStdlib {
                continue
            }
            guard let receiver = sema.symbols.functionSignature(for: binding.chosenCallee)?.receiverType,
                  case let .classType(worker) = sema.types.kind(of: sema.types.makeNonNullable(receiver)),
                  sema.symbols.symbol(worker.classSymbol)?.fqName
                    == Array(fqName.dropLast()) + [ctx.interner.intern("Worker")]
            else { continue }
            sema.bindings.markWorkerExecuteCallee(binding.chosenCallee)
            let args: [CallArgument]
            switch ast.arena.expr(exprID) {
            case let .call(_, _, arguments, _),
                 let .memberCall(_, _, _, arguments, _),
                 let .safeMemberCall(_, _, _, arguments, _):
                args = arguments
            default:
                continue
            }
            guard let jobIndex = args.indices.first(where: { (binding.parameterMapping[$0] ?? $0) == 2 })
            else { continue }
            let job = args[jobIndex].expr
            if let range = ast.arena.exprRange(job) {
                sema.bindings.bindWorkerExecuteJobRange(job, range: range)
            }
            let isStaticCallable: Bool
            switch ast.arena.expr(job) {
            case .lambdaLiteral:
                // Local function dependencies are checked using their actual
                // closure environment in KIR, rather than counting code as state.
                isStaticCallable = sema.bindings.captureSymbols(for: job).allSatisfy {
                    sema.symbols.symbol($0)?.kind == .function
                }
            case let .callableRef(receiver, _, _):
                isStaticCallable = sema.bindings.captureSymbols(for: job).isEmpty
                    && sema.bindings.implicitReceiverMemberNames[job] == nil
                    && (receiver == nil || sema.bindings.isUnboundCallableRef(job))
            default:
                isStaticCallable = false
            }
            if !isStaticCallable {
                ctx.diagnostics.error(
                    "KSWIFTK-SEMA-0430",
                    "Worker.execute job must be a non-capturing lambda or an unbound callable reference.",
                    range: ast.arena.exprRange(job)
                )
            }
        }
    }
}
