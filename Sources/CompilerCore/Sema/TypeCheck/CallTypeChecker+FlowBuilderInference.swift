final class FlowBuilderInferenceSession {
    let expectedElementType: TypeID?
    /// The implicit `this` symbol in scope at the `flow { }` call site.
    /// Receivers introduced inside the builder lambda (e.g. `with(x) { }`)
    /// replace `this` with their own symbol, so a bare `emit` bound to an
    /// enclosing receiver keeps the same symbol as the boundary.
    let outerThisSymbol: SymbolID?
    var emittedTypes: [TypeID] = []

    init(expectedElementType: TypeID?, outerThisSymbol: SymbolID?) {
        self.expectedElementType = expectedElementType
        self.outerThisSymbol = outerThisSymbol
    }

    func elementType(types: TypeSystem) -> TypeID {
        expectedElementType ?? (emittedTypes.isEmpty ? types.anyType : types.lub(emittedTypes))
    }
}

extension CallTypeChecker {
    func flowBuilderEmitHasReceiverMember(ctx: TypeInferenceContext, locals: LocalBindings) -> Bool {
        // Only a receiver introduced inside the builder lambda shadows the
        // FlowCollector. When `this` is still the receiver from the `flow { }`
        // boundary — e.g. the enclosing class, which
        // `syncingImplicitReceiver` can restore over the synthetic Any
        // placeholder — its `emit` member does not take precedence.
        if let session = ctx.flowBuilderInference,
           locals[ctx.interner.intern("this")]?.symbol == session.outerThisSymbol
        {
            return false
        }
        guard let receiverType = ctx.implicitReceiverType else { return false }
        return !driver.helpers.collectMemberFunctionCandidates(
            named: ctx.interner.intern("emit"),
            receiverType: ctx.sema.types.makeNonNullable(receiverType),
            sema: ctx.sema,
            interner: ctx.interner
        ).isEmpty
    }

    func isFlowCollectorType(_ type: TypeID, ctx: TypeInferenceContext) -> Bool {
        guard let classType = resolveClassType(type, sema: ctx.sema),
              let symbol = ctx.sema.symbols.symbol(classType.classSymbol)
        else { return false }
        return symbol.fqName == [
            ctx.interner.intern("kotlinx"), ctx.interner.intern("coroutines"),
            ctx.interner.intern("flow"), ctx.interner.intern("FlowCollector"),
        ]
    }

    func flowBuilderElementType(_ type: TypeID?, ctx: TypeInferenceContext) -> TypeID? {
        guard let type,
              case let .classType(classType) = ctx.sema.types.kind(of: type),
              let symbol = ctx.sema.symbols.symbol(classType.classSymbol),
              symbol.fqName == ["kotlinx", "coroutines", "flow", "Flow"].map(ctx.interner.intern),
              let argument = classType.args.first
        else { return nil }
        switch argument {
        case let .invariant(type), let .in(type), let .out(type):
            return type
        case .star:
            return nil
        }
    }

    func recordFlowBuilderEmission(_ type: TypeID, range: SourceRange?, ctx: TypeInferenceContext) {
        guard let session = ctx.flowBuilderInference,
              type != ctx.sema.types.errorType
        else { return }
        session.emittedTypes.append(type)
        if let expectedType = session.expectedElementType {
            driver.emitSubtypeConstraint(
                left: type, right: expectedType, range: range,
                solver: ConstraintSolver(), sema: ctx.sema,
                diagnostics: ctx.sema.diagnostics,
                diagnosticCode: "KSWIFTK-SEMA-0473",
                failureMessage: "Argument type mismatch."
            )
        }
    }

    func recordFlowBuilderEmitAll(_ id: ExprID, args: [CallArgument], ctx: TypeInferenceContext) {
        guard ctx.flowBuilderInference != nil,
              let binding = ctx.sema.bindings.callBinding(for: id),
              let symbol = ctx.sema.symbols.symbol(binding.chosenCallee),
              symbol.fqName == ["kotlinx", "coroutines", "flow", "emitAll"].map(ctx.interner.intern),
              ctx.sema.symbols.functionSignature(for: symbol.id)?.receiverType == nil,
              let argumentIndex = binding.parameterMapping.first(where: { $0.value == 0 })?.key,
              args.indices.contains(argumentIndex),
              let elementType = flowBuilderElementType(
                  ctx.sema.bindings.exprType(for: args[argumentIndex].expr), ctx: ctx
              )
        else { return }
        recordFlowBuilderEmission(elementType, range: ctx.ast.arena.exprRange(id), ctx: ctx)
    }
}
