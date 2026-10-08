
extension CallTypeChecker {
    func inferMemberCallImpl(
        _ id: ExprID,
        receiverID: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        safeCall: Bool
    ) -> TypeID {
        let request = MemberCallInferenceRequest(
            id: id,
            receiverID: receiverID,
            calleeName: calleeName,
            args: args,
            range: range,
            ctx: ctx,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            safeCall: safeCall
        )

        markDeferredCollectionHOFLambdaIfNeeded(request)

        if let result = tryInferMemberCallWithoutReceiverSpecials(request, locals: &locals) {
            return enforceFunctionInvocationSyntax(request, result: result)
        }

        if let result = tryInferFQNQualifiedValue(request, locals: locals) {
            return enforceFunctionInvocationSyntax(request, result: result)
        }

        if let result = tryInferFQNPackageTopLevelCall(request, locals: &locals) {
            return enforceFunctionInvocationSyntax(request, result: result)
        }

        var receiverType: TypeID
        if !safeCall, case let .nameRef(name, nameRange) = ctx.ast.arena.expr(receiverID) {
            receiverType = driver.exprChecker.inferNameRefExpr(
                receiverID, name: name, nameRange: nameRange, ctx: ctx,
                locals: &locals, isQualifier: true
            )
        } else {
            receiverType = driver.inferExpr(receiverID, ctx: ctx, locals: &locals)
        }
        if !safeCall, receiverType != ctx.sema.types.errorType {
            receiverType = resolveSuperMemberReceiverType(
                receiverID: receiverID,
                receiverType: receiverType,
                calleeName: calleeName,
                ctx: ctx
            )
        }
        // The invalid super receiver already emitted its own diagnostic.
        // Resolving a member on the error type can introduce unrelated
        // extension candidates and produce a misleading overload error.
        if receiverType == ctx.sema.types.errorType,
           case .superRef = ctx.ast.arena.expr(receiverID)
        {
            ctx.sema.bindings.bindExprType(id, type: ctx.sema.types.errorType)
            return ctx.sema.types.errorType
        }

        // A `?.` call evaluates its arguments only when the receiver is
        // non-null, so a stable receiver reference narrows to non-null while
        // they are checked (`x?.let { x.length }`, `map[x]` inside the
        // lambda). The narrowing is scoped to the arguments: the receiver may
        // still be null afterwards, so the narrowed local must be restored.
        if safeCall {
            let baseState = ctx.flowState.includingMembers(from: locals)
            let narrowedState = ctx.dataFlow.narrowNonNull(
                receiverID,
                base: baseState,
                locals: locals,
                ast: ctx.ast,
                sema: ctx.sema,
                interner: ctx.interner
            )
            if narrowedState != baseState {
                var narrowedLocals = locals
                driver.exprChecker.applyFlowStateToLocals(
                    narrowedState, locals: &narrowedLocals, sema: ctx.sema
                )
                let narrowedRequest = MemberCallInferenceRequest(
                    id: id,
                    receiverID: receiverID,
                    calleeName: calleeName,
                    args: args,
                    range: range,
                    ctx: ctx.copying(flowState: narrowedState),
                    expectedType: expectedType,
                    explicitTypeArgs: explicitTypeArgs,
                    safeCall: safeCall
                )
                let result = enforceFunctionInvocationSyntax(
                    narrowedRequest,
                    result: inferMemberCallOnReceiver(
                        narrowedRequest, receiverType: receiverType, locals: &narrowedLocals
                    )
                )
                // Keep argument-side effects on other locals, but restore
                // the entries that moved only because of the receiver
                // narrowing: `?.` may skip evaluation entirely.
                for (name, prior) in locals
                where narrowedState.variables[prior.symbol] != baseState.variables[prior.symbol] {
                    narrowedLocals[name] = prior
                }
                narrowedLocals.memberFlow = locals.memberFlow
                locals = narrowedLocals
                return result
            }
        }

        return enforceFunctionInvocationSyntax(
            request,
            result: inferMemberCallOnReceiver(request, receiverType: receiverType, locals: &locals)
        )
    }

    /// KUU-1453: `recv.name` without parentheses is property-access syntax.
    /// Kotlin never invokes a function that way — `c.m` is a compile error
    /// ("function invocation 'm()' expected"). Member-call inference shares
    /// one candidate machinery for both shapes, so an argument-less
    /// non-explicit call can otherwise bind any zero-argument function
    /// (member `c.m`, user extension `l.myProp`, bundled function
    /// `l.first`). The only function bindings legal under property syntax
    /// are property accessors (extension-property reads bind the getter
    /// call) and the bundled-stdlib property facades (`lastIndex`,
    /// `indices`, `javaClass`, and the synthetic `Char` member properties
    /// `code`/`category`/`directionality`) that model upstream properties
    /// the bundled surface cannot declare directly — the same contract
    /// KUU-1451 established on the implicit-receiver side.
    private func enforceFunctionInvocationSyntax(
        _ request: MemberCallInferenceRequest,
        result: TypeID
    ) -> TypeID {
        let sema = request.ctx.sema
        // This check protects dotted property syntax (`recv.name`). A
        // nominal callable value written as `f()` is routed through member
        // inference for its generated `invoke`, but the source expression
        // remains `.call` rather than a dotted member access.
        let isDottedMemberAccess = switch request.ctx.ast.arena.expr(request.id) {
        case .memberCall, .safeMemberCall:
            true
        default:
            false
        }
        guard isDottedMemberAccess,
              request.args.isEmpty,
              request.explicitTypeArgs.isEmpty,
              !request.ctx.ast.arena.isExplicitCall(request.id),
              result != sema.types.errorType,
              let chosen = sema.bindings.callBinding(for: request.id)?.chosenCallee,
              let symbol = sema.symbols.symbol(chosen),
              symbol.kind == .function || symbol.kind == .constructor
        else {
            return result
        }
        // A property read binds its accessor call — the property itself,
        // not a function invocation. `accessorOwnerProperty` covers
        // registered accessors; a `.property` parent marks source-level
        // getter/setter helpers that share the property's name.
        if sema.symbols.accessorOwnerProperty(for: chosen) != nil {
            return result
        }
        if let parent = sema.symbols.parentSymbol(for: chosen),
           sema.symbols.symbol(parent)?.kind == .property
        {
            return result
        }
        if isBundledPropertyStyleFacadeFunction(chosen, ctx: request.ctx) {
            return result
        }
        request.ctx.semaCtx.diagnostics.error(
            "KSWIFTK-SEMA-0309",
            "function invocation '\(request.ctx.interner.resolve(request.calleeName))()' expected.",
            range: request.range
        )
        sema.bindings.bindExprType(request.id, type: sema.types.errorType)
        return sema.types.errorType
    }

    /// The bundled stdlib models a small, fixed set of upstream Kotlin
    /// properties as zero-argument package-level extension functions
    /// (bundled-source `lastIndex`/`indices`/`javaClass` facades, and the
    /// synthetic `Char` member-property stubs `code`/`category`/
    /// `directionality`). A function bound through property-access syntax
    /// is a facade only for those exact modeled properties — user,
    /// member, or other bundled functions keep Kotlin's
    /// invocation-syntax requirement.
    private func isBundledPropertyStyleFacadeFunction(
        _ candidate: SymbolID,
        ctx: TypeInferenceContext
    ) -> Bool {
        let sema = ctx.sema
        let interner = ctx.interner
        guard let symbol = sema.symbols.symbol(candidate),
              symbol.kind == .function,
              let signature = sema.symbols.functionSignature(for: candidate),
              signature.parameterTypes.isEmpty,
              !signature.isSuspend,
              signature.receiverType != nil,
              sema.symbols.memberExtensionOwnerSymbol(for: candidate) == nil
        else {
            return false
        }
        // Two facade families model upstream Kotlin properties as
        // zero-argument functions:
        // - Bundled source extension functions for the upstream extension
        //   properties `lastIndex`, `indices` and `javaClass`, which the
        //   bundled parser cannot declare on generic receivers (see
        //   `Stdlib/kotlin/collections/` and `Stdlib/kotlin/JavaClass.kt`).
        //   These must be bundled declarations.
        // - The upstream `Char` member properties `code`, `category` and
        //   `directionality`, which the header pipeline registers as
        //   synthetic `kotlin.text` extension functions on a non-null Char
        //   receiver (see `HeaderHelpers+SyntheticCharStubs.swift`). These
        //   are synthetic stubs, not bundled declarations, so the receiver
        //   is pinned to `Char` and the symbol to stdlib-internal flags.
        var allowsSyntheticStub = false
        switch interner.resolve(symbol.name) {
        case "lastIndex", "indices", "javaClass":
            break
        case "code", "category", "directionality":
            guard signature.receiverType == sema.types.charType else {
                return false
            }
            allowsSyntheticStub = true
        default:
            return false
        }
        if let parentID = sema.symbols.parentSymbol(for: candidate),
           let parent = sema.symbols.symbol(parentID)
        {
            if parent.kind == .property {
                return false
            }
            // A genuine member is declared under its nominal owner; a
            // package-level extension keeps its package FQName even when
            // member lookup attaches it to the nominal.
            if parent.kind != .package,
               symbol.fqName == parent.fqName + [symbol.name]
            {
                return false
            }
        }
        guard let memberKey = BundledDeclarationIndex.memberKey(
            for: symbol,
            symbolID: candidate,
            symbols: sema.symbols,
            types: sema.types,
            interner: interner
        ) else {
            return false
        }
        let declaredOwnerKey = BundledMemberKey(
            ownerFQName: Array(symbol.fqName.dropLast()),
            name: symbol.name,
            arity: signature.parameterTypes.count
        )
        if sema.bundledIndex.contains(memberKey)
            || sema.bundledIndex.contains(declaredOwnerKey)
        {
            return true
        }
        // A bundled-source declaration can be missing from the bundled
        // index when its receiver is a bare type parameter
        // (`fun <T : Any> T.javaClass()`): the AST key builder cannot name
        // a nominal owner for `T`. Its declSite still marks it as bundled
        // stdlib source.
        if let declFileID = sema.symbols.sourceFileID(for: candidate) ?? symbol.declSite?.start.file,
           let sourceManager = ctx.visibilityChecker.sourceManager,
           sourceManager.origin(of: declFileID)?.isBundledStdlib == true
        {
            return true
        }
        // Synthetic stubs carry no bundled-declaration index entry; they
        // are still stdlib-internal symbols, so the flag is enough proof
        // of bundled origin for the synthetic facade names.
        return allowsSyntheticStub && symbol.flags.contains(.synthetic)
    }

    private func inferMemberCallOnReceiver(
        _ request: MemberCallInferenceRequest,
        receiverType: TypeID,
        locals: inout LocalBindings
    ) -> TypeID {
        if request.ctx.interner.resolve(request.calleeName) == "transform",
           case let .classType(receiverClass) = request.ctx.sema.types.kind(
               of: request.ctx.sema.types.makeNonNullable(receiverType)
           ),
           request.ctx.sema.symbols.symbol(receiverClass.classSymbol)?.fqName == [
               request.ctx.interner.intern("kotlinx"),
               request.ctx.interner.intern("coroutines"),
               request.ctx.interner.intern("flow"),
               request.ctx.interner.intern("Flow"),
           ]
        {
            let candidates = request.ctx.sema.symbols.lookupAll(fqName: [
                request.ctx.interner.intern("kotlinx"),
                request.ctx.interner.intern("coroutines"),
                request.ctx.interner.intern("flow"),
                request.ctx.interner.intern("transform"),
            ]).filter { candidate in
                guard let symbol = request.ctx.sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      request.ctx.sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = request.ctx.sema.symbols.functionSignature(for: candidate),
                      signature.receiverType != nil,
                      signature.typeParameterSymbols.count == 2,
                      signature.parameterTypes.count == 1,
                      case let .functionType(callback) = request.ctx.sema.types.kind(of: signature.parameterTypes[0]),
                      callback.returnType == request.ctx.sema.types.unitType
                else { return false }
                return true
            }
            if let result = inferReceiverBuilderCall(
                request.id,
                calleeName: request.calleeName,
                args: request.args,
                range: request.range,
                ctx: request.ctx,
                locals: &locals,
                expectedType: request.expectedType,
                explicitTypeArgs: request.explicitTypeArgs,
                receiverType: receiverType,
                candidateOverride: request.ctx.filterByVisibility(candidates).visible
            ) {
                return result
            }
        }

        if let result = tryInferMemberCallEarlyReceiverSpecials(
            request,
            receiverType: receiverType,
            locals: &locals
        ) {
            return result
        }

        if let result = tryInferMemberCallScopeResultAndFileSpecials(
            request,
            receiverType: receiverType,
            locals: &locals
        ) {
            return result
        }

        if let result = tryInferMemberCallCollectionFlowSpecials(
            request,
            receiverType: receiverType,
            locals: &locals
        ) {
            return result
        }

        if let result = tryInferMemberCallStringRangeComparatorSpecials(
            request,
            receiverType: receiverType,
            locals: &locals
        ) {
            return result
        }

        return inferRegularMemberCall(request, receiverType: receiverType, locals: &locals)
    }

    private func resolveSuperMemberReceiverType(
        receiverID: ExprID,
        receiverType: TypeID,
        calleeName: InternedString,
        ctx: TypeInferenceContext
    ) -> TypeID {
        let sema = ctx.sema
        guard case let .superRef(nil, range) = ctx.ast.arena.expr(receiverID),
              let currentType = ctx.implicitReceiverType,
              case let .classType(currentClass) = sema.types.kind(of: currentType)
        else {
            return receiverType
        }

        var memberSupertypes: [TypeID] = []
        var concreteSupertypes: [TypeID] = []
        for superSymbol in sema.symbols.directSupertypes(for: currentClass.classSymbol) {
            let typeArgs = sema.types.liftedNominalSupertypeArgs(
                from: currentClass.classSymbol,
                childArgs: currentClass.args,
                to: superSymbol
            ) ?? []
            let superType = sema.types.make(.classType(ClassType(classSymbol: superSymbol, args: typeArgs)))
            // Supertype selection precedes overload applicability: even different
            // parameter lists require super<T> when both supertypes define the name.
            let members = driver.helpers.collectMemberFunctionCandidates(
                named: calleeName,
                receiverType: superType,
                sema: sema,
                interner: ctx.interner
            )
            guard !members.isEmpty else { continue }
            memberSupertypes.append(superType)
            if members.contains(where: { sema.symbols.symbol($0)?.flags.contains(.abstractType) == false }) {
                concreteSupertypes.append(superType)
            }
        }

        let candidates = concreteSupertypes.isEmpty ? memberSupertypes : concreteSupertypes
        if candidates.count > 1 {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0056",
                "Multiple supertypes available. Specify the intended supertype in angle brackets, e.g. 'super<Foo>'.",
                range: range
            )
            sema.bindings.bindExprType(receiverID, type: sema.types.errorType)
            return sema.types.errorType
        }
        guard let selectedType = candidates.first else { return receiverType }
        sema.bindings.bindExprType(receiverID, type: selectedType)
        return selectedType
    }
}
