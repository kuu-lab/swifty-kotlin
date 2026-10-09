extension CallTypeChecker {
    /// Explicit-receiver calls partition by lexical/import tier before comparing
    /// functions with property + invoke. A package property therefore precedes
    /// an implicitly imported function, while a same-tier function wins.
    func callableInvocationScopePriority(_ candidate: SymbolID, named name: InternedString, ctx: TypeInferenceContext) -> Int {
        let sema = ctx.sema
        guard let symbol = sema.symbols.symbol(candidate) else { return 0 }
        if symbol.flags.contains(.localFunction) { return 1 }
        if let owner = sema.symbols.parentSymbol(for: candidate),
           let ownerSymbol = sema.symbols.symbol(owner),
           ownerSymbol.kind == .class || ownerSymbol.kind == .interface || ownerSymbol.kind == .object,
           Array(symbol.fqName.dropLast()) == ownerSymbol.fqName {
            return sema.symbols.extensionPropertyReceiverType(for: candidate) != nil
                || sema.symbols.memberExtensionOwnerSymbol(for: candidate) != nil ? 1 : 0
        }
        guard let file = ctx.currentASTFile else { return 0 }
        if file.imports.contains(where: {
            !$0.isWildcard && $0.path == symbol.fqName && ($0.alias == nil || $0.alias == name)
        }) { return 2 }
        let package = Array(symbol.fqName.dropLast())
        if file.packageFQName == package { return 3 }
        if file.imports.contains(where: { $0.isWildcard && $0.path == package }) { return 4 }
        return 5
    }

    /// Check the call shape without inferring a lambda against the losing tier.
    /// Body errors must still be reported against the winning property type.
    func callablePropertyAcceptsArgumentShape(
        _ property: SymbolID,
        request: MemberCallInferenceRequest,
        argTypes: [TypeID],
        typeOverride: TypeID? = nil,
        locals: LocalBindings
    ) -> Bool {
        let ctx = request.ctx
        let sema = ctx.sema
        guard let type = typeOverride ?? sema.symbols.propertyType(for: property),
              case let .functionType(function) = sema.types.kind(of: type) else { return false }
        return callableValueAcceptsArgumentShape(
            function, receiverIsExplicit: sema.symbols.extensionPropertyReceiverType(for: property) != nil,
            request: request, argTypes: argTypes, locals: locals
        )
    }

    func callableValueAcceptsArgumentShape(
        _ function: FunctionType,
        receiverIsExplicit: Bool,
        request: MemberCallInferenceRequest,
        argTypes: [TypeID],
        locals: LocalBindings
    ) -> Bool {
        let ctx = request.ctx
        let sema = ctx.sema
        guard
              function.nullability == .nonNull,
              !request.args.contains(where: { $0.label != nil || $0.isSpread }) else { return false }
        let parameters = receiverIsExplicit ? function.receiver.map { [$0] } ?? [] : []
        let parameterTypes = parameters + function.params
        guard parameterTypes.count == request.args.count else { return false }
        for (index, argument) in request.args.enumerated() {
            let parameter = parameterTypes[index]
            switch ctx.ast.arena.expr(argument.expr) {
            case let .lambdaLiteral(params, _, _, _):
                guard let callback = callableArgumentFunctionType(parameter, ctx: ctx) else {
                    if case .typeParam = sema.types.kind(of: parameter) { continue }
                    if callableArgumentAcceptsUnknownArity(parameter, isReference: false, ctx: ctx) { continue }
                    return false
                }
                if params.isEmpty {
                    if callback.params.count > 1 { return false }
                } else if params.count != callback.params.count { return false }
            case .callableRef:
                guard callableReferenceAcceptsArgumentType(argument.expr, parameter: parameter, ctx: ctx, locals: locals) else { return false }
            default:
                if case .typeParam = sema.types.kind(of: parameter) { continue }
                guard sema.types.isSubtype(argTypes[index], parameter)
                    || integerLiteralFitsParameter(argument.expr, parameterType: parameter, ctx: ctx) else { return false }
            }
        }
        return true
    }

    private func callableArgumentFunctionType(_ type: TypeID, ctx: TypeInferenceContext) -> FunctionType? {
        if case let .functionType(function) = ctx.sema.types.kind(of: type) { return function }
        return ctx.sema.types.nominalFunctionType(for: type)
            ?? driver.helpers.samFunctionType(for: type, sema: ctx.sema)
    }

    private func callableArgumentAcceptsUnknownArity(_ type: TypeID, isReference: Bool, ctx: TypeInferenceContext) -> Bool {
        let placeholder = ctx.sema.types.make(.functionType(FunctionType(
            params: [], returnType: ctx.sema.types.nothingType,
            isSuspend: false, isCallableReference: isReference, nullability: .nonNull
        )))
        return ctx.sema.types.isSubtype(placeholder, type)
    }

    /// Check known reference signatures without binding the reference against
    /// a tier that may lose. The normal contextual inference still reports
    /// errors and binds the target once the winning callable is selected.
    private func callableReferenceAcceptsArgumentType(
        _ expression: ExprID, parameter: TypeID, ctx: TypeInferenceContext, locals: LocalBindings
    ) -> Bool {
        let sema = ctx.sema
        if parameter == sema.types.anyType || parameter == sema.types.nullableAnyType { return true }
        if case .typeParam = sema.types.kind(of: parameter) { return true }
        let expected = callableArgumentFunctionType(parameter, ctx: ctx)
        guard expected != nil || callableArgumentAcceptsUnknownArity(parameter, isReference: true, ctx: ctx) else { return false }
        guard case let .callableRef(receiver, member, _) = ctx.ast.arena.expr(expression) else { return true }
        var receiverType: TypeID?
        var bindReceiver = false
        var candidates: [SymbolID]
        if let receiver {
            receiverType = sema.bindings.exprType(for: receiver)
            if case let .nameRef(name, _) = ctx.ast.arena.expr(receiver) {
                if let local = locals[name] {
                    receiverType = local.type
                    bindReceiver = true
                } else if let owner = ctx.scope.lookup(name).compactMap({ sema.symbols.symbol($0) }).first(where: {
                    $0.kind == .class || $0.kind == .interface || $0.kind == .enumClass
                }), sema.types.nominalTypeParameterSymbols(for: owner.id).isEmpty {
                    receiverType = sema.types.make(.classType(ClassType(classSymbol: owner.id, args: [], nullability: .nonNull)))
                } else { return true }
            } else { bindReceiver = true }
            guard let receiverType else { return true }
            candidates = driver.helpers.collectMemberFunctionCandidates(
                named: member, receiverType: sema.types.makeNonNullable(receiverType), sema: sema,
                includeUnattachedPackageExtensions: true, interner: ctx.interner
            )
        } else {
            candidates = ctx.scope.lookupMergingChain(member).filter { sema.symbols.symbol($0)?.kind == .function }
            if candidates.isEmpty, let implicit = ctx.implicitReceiverType {
                receiverType = implicit
                bindReceiver = true
                candidates = driver.helpers.collectMemberFunctionCandidates(
                    named: member, receiverType: implicit, sema: sema, interner: ctx.interner
                )
            }
        }
        candidates = ctx.filterByVisibility(candidates).visible
        if candidates.isEmpty { return true }
        return candidates.contains { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else { return false }
            let receiverIsBound = bindReceiver || (receiver == nil && signature.receiverType.map { receiver in
                ctx.implicitReceiverType.map { sema.types.isSubtype($0, receiver) } ?? false
            } == true)
            let boundReceiver = receiverType.map { (candidate, $0) }
            if let expected {
                return driver.helpers.contextualCallableFunctionType(
                    for: signature, bindReceiver: receiverIsBound, boundReceiver: boundReceiver,
                    expectedFunctionType: sema.types.make(.functionType(expected)), sema: sema
                ) != nil
            }
            let inferred = driver.helpers.callableFunctionType(
                for: signature, bindReceiver: receiverIsBound, boundReceiver: boundReceiver, sema: sema
            )
            return sema.types.isSubtype(inferred, parameter)
        }
    }
}
