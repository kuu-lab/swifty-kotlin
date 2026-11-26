
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
        ctx.sema.types.attribution?.increment(.callSites)
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
        // The receiver of `a?.b` is evaluated iff the call itself is — only
        // the member access and arguments sit behind the `?.` conditional
        // point — so it keeps the conditionality the call node was entered
        // with. `(x!!)?.f()` still narrows `x`, while `x?.f(y!!.v)` keeps
        // the `!!` on the conditional path so it cannot leak to following
        // code when the whole call was already conditional (KUU-3966).
        var receiverCtx = ctx
        receiverCtx.isConditionallyEvaluated = ctx.receiverConditionallyEvaluated
        if !safeCall, case let .nameRef(name, nameRange) = ctx.ast.arena.expr(receiverID) {
            receiverType = driver.exprChecker.inferNameRefExpr(
                receiverID, name: name, nameRange: nameRange, ctx: receiverCtx,
                locals: &locals, isQualifier: true
            )
        } else {
            receiverType = driver.inferExpr(receiverID, ctx: receiverCtx, locals: &locals)
        }
        if args.isEmpty,
           !ctx.ast.arena.isExplicitCall(id),
           let receiverExpr = ctx.ast.arena.expr(receiverID),
           case .callableRef = receiverExpr,
           let receiverRange = ctx.ast.arena.exprRange(receiverID),
           ctx.sema.diagnostics.diagnostics.contains(where: {
               $0.code == "KSWIFTK-SEMA-0022"
                   && $0.primaryRange == receiverRange
                   && $0.message.hasPrefix("Unresolved reference '::")
           }) {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0022",
                "Unresolved reference '\(ctx.interner.resolve(calleeName))'.",
                range: range
            )
            return driver.helpers.bindAndReturnErrorType(id, sema: ctx.sema)
        }
        if !safeCall, receiverType != ctx.sema.types.errorType {
            receiverType = resolveSuperMemberReceiverType(
                receiverID: receiverID,
                receiverType: receiverType,
                calleeName: calleeName,
                isPropertyAccess: args.isEmpty && !ctx.ast.arena.isExplicitCall(id),
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

        // A `!!` on a definitely-null reference types the receiver itself as
        // `Nothing`, but kotlinc resolves member accesses on that receiver
        // against the asserted declared type — the operand's declared type
        // made non-null (KUU-4593). The receiver expression binding keeps its
        // real `Nothing` type; only member resolution uses the asserted type.
        var memberReceiverType = receiverType
        if !safeCall,
           receiverType == ctx.sema.types.nothingType,
           let receiverExpr = ctx.ast.arena.expr(receiverID),
           case let .nullAssert(operandID, _) = receiverExpr,
           let assertedType = nullAssertedOperandType(operandID, ctx: ctx, locals: locals)
        {
            memberReceiverType = assertedType
        }

        // `a?.f(<args>)` skips the whole argument evaluation when `a` is null,
        // so a definite assignment performed inside the arguments (directly,
        // in a block-valued argument, or through a nested callsInPlace
        // contract) is only conditional. The receiver is already evaluated
        // here, so only locals still uninitialized at this point are reverted
        // once the arguments have been inferred (KUU-4625).
        let uninitializedBeforeArguments: Set<SymbolID> = safeCall
            ? Set(locals.compactMap { $0.value.isInitialized ? nil : $0.value.symbol })
            : []
        defer {
            if !uninitializedBeforeArguments.isEmpty {
                var reverted: Set<SymbolID> = []
                for (name, local) in locals
                where local.isInitialized && uninitializedBeforeArguments.contains(local.symbol) {
                    locals[name] = (local.type, local.symbol, local.isMutable, false)
                    reverted.insert(local.symbol)
                    if !local.isMutable { locals.possiblyAssignedVals.insert(local.symbol) }
                }
                if !reverted.isEmpty { locals.safeCallArgumentInitializations[id] = reverted }
            }
        }

        if safeCall {
            let baseState = ctx.flowState.includingMembers(from: locals)
            var narrowedState = ctx.dataFlow.narrowNonNull(
                receiverID,
                base: baseState,
                locals: locals,
                ast: ctx.ast,
                sema: ctx.sema,
                interner: ctx.interner
            )
            narrowedState = ctx.dataFlow.narrowSafeCastOperand(
                receiverID,
                base: narrowedState,
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
                        narrowedRequest, receiverType: memberReceiverType, locals: &narrowedLocals
                    )
                )
                for (name, prior) in locals
                where narrowedState.variables[prior.symbol] != baseState.variables[prior.symbol] {
                    narrowedLocals[name] = prior
                }
                narrowedLocals.memberFlow = locals.memberFlow
                narrowedLocals.variableFacts = locals.variableFacts
                narrowedLocals.invalidatedVariableFacts = locals.invalidatedVariableFacts
                locals = narrowedLocals
                return result
            }
        }

        let result = enforceFunctionInvocationSyntax(
            request,
            result: inferMemberCallOnReceiver(request, receiverType: memberReceiverType, locals: &locals)
        )
        checkObjectQualifierOptInCoverage(request)
        return result
    }

    private func checkObjectQualifierOptInCoverage(_ request: MemberCallInferenceRequest) {
        let sema = request.ctx.sema
        guard !request.safeCall,
              case .nameRef = request.ctx.ast.arena.expr(request.receiverID),
              let qualifier = sema.bindings.identifierSymbol(for: request.receiverID),
              sema.symbols.symbol(qualifier)?.kind == .object,
              !sema.symbols.children(of: qualifier).contains(where: { child in
                  switch sema.symbols.symbol(child)?.kind {
                  case .class, .interface, .enumClass, .object, .annotationClass, .typeAlias:
                      return true
                  default:
                      return false
                  }
              }),
              let chosen = sema.bindings.callBinding(for: request.id)?.chosenCallee
                  ?? sema.bindings.identifierSymbol(for: request.id).flatMap({ symbol in
                      switch sema.symbols.symbol(symbol)?.kind {
                      case .function, .property:
                          return symbol
                      default:
                          return nil
                      }
                  })
        else {
            return
        }
        let qualifierRequirements = driver.helpers.resolvedOptInRequirements(for: qualifier, ctx: request.ctx)
        guard !qualifierRequirements.isEmpty else { return }
        let coveredMarkers = Set(driver.helpers.resolvedOptInRequirements(
            for: chosen,
            ctx: request.ctx
        ).map(\.markerSymbol))
        let uncovered = qualifierRequirements.filter { !coveredMarkers.contains($0.markerSymbol) }
        guard !uncovered.isEmpty,
              let receiverRange = request.ctx.ast.arena.exprRange(request.receiverID)
        else {
            return
        }
        driver.helpers.emitOptInRequirements(
            uncovered,
            ctx: request.ctx,
            range: receiverRange,
            diagnostics: sema.diagnostics
        )
    }

    private func enforceFunctionInvocationSyntax(
        _ request: MemberCallInferenceRequest,
        result: TypeID
    ) -> TypeID {
        let sema = request.sema
        let knownNames = request.knownNames
        let isDottedMemberAccess = switch request.ctx.ast.arena.expr(request.id) {
        case .memberCall, .safeMemberCall:
            true
        default:
            false
        }
        if isDottedMemberAccess,
           request.ctx.ast.arena.isExplicitCall(request.id),
           let chosen = sema.bindings.callBinding(for: request.id)?.chosenCallee,
           isSyntheticCharPropertyFacadeFunction(chosen, ctx: request.ctx)
        {
            sema.diagnostics.error(
                "KSWIFTK-SEMA-0022",
                "Expression '\(request.ctx.interner.resolve(request.calleeName))' cannot be invoked as a function.",
                range: request.range
            )
            return driver.helpers.bindAndReturnErrorType(request.id, sema: sema)
        }
        guard isDottedMemberAccess,
              request.args.isEmpty,
              request.explicitTypeArgs.isEmpty,
              !request.ctx.ast.arena.isExplicitCall(request.id),
              result != sema.types.errorType
        else {
            return result
        }

        if let chosen = sema.bindings.callBinding(for: request.id)?.chosenCallee,
           let symbol = sema.symbols.symbol(chosen)
        {
            guard symbol.kind == .function || symbol.kind == .constructor else {
                return result
            }
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
            if isBundledJavaIsGetterMemberFunction(
                chosen,
                receiverType: sema.bindings.exprType(for: request.receiverID),
                ctx: request.ctx
            ) {
                return result
            }
        } else {
            let isProperty = sema.bindings.identifierSymbol(for: request.id)
                .flatMap(sema.symbols.symbol)
                .map { $0.kind == .property || $0.kind == .field } ?? false
            guard request.calleeName == knownNames.toString,
                  !isProperty
            else {
                return result
            }
        }
        request.ctx.sema.diagnostics.error(
            "KSWIFTK-SEMA-0309",
            "function invocation '\(request.ctx.interner.resolve(request.calleeName))()' expected.",
            range: request.range
        )
        sema.bindings.bindExprType(request.id, type: sema.types.errorType)
        return sema.types.errorType
    }

    func isSyntheticCharPropertyFacadeFunction(
        _ candidate: SymbolID,
        ctx: TypeInferenceContext
    ) -> Bool {
        guard let symbol = ctx.sema.symbols.symbol(candidate),
              ["code", "category", "directionality"].contains(ctx.interner.resolve(symbol.name))
        else { return false }
        return isBundledPropertyStyleFacadeFunction(candidate, ctx: ctx)
    }

    func isBundledPropertyStyleFacadeFunction(
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
        var allowsSyntheticStub = false
        switch interner.resolve(symbol.name) {
        case "lastIndex", "indices", "javaClass":
            break
        case "java":
            guard symbol.fqName == [
                interner.intern("kotlin"), interner.intern("jvm"), interner.intern("java"),
            ] else { return false }
        case "code", "category", "directionality":
            guard signature.receiverType == sema.types.charType,
                  symbol.fqName == [
                      interner.intern("kotlin"), interner.intern("text"), symbol.name,
                  ]
            else {
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
        if let declFileID = sema.symbols.sourceFileID(for: candidate) ?? symbol.declSite?.start.file,
           let sourceManager = ctx.visibilityChecker.sourceManager,
           sourceManager.origin(of: declFileID)?.isBundledStdlib == true
        {
            return true
        }
        return allowsSyntheticStub && symbol.flags.contains(.synthetic)
    }

    func isBundledJavaIsGetterMemberFunction(
        _ candidate: SymbolID,
        receiverType: TypeID?,
        ctx: TypeInferenceContext
    ) -> Bool {
        isBundledJavaIsGetterFunctionShape(candidate, ctx: ctx)
            && isBundledJavaNominal(receiverType: receiverType, ctx: ctx)
    }

    func isBundledJavaIsGetterFunctionShape(
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
              sema.symbols.memberExtensionOwnerSymbol(for: candidate) == nil,
              !symbol.flags.contains(.extensionMemberAlias)
        else {
            return false
        }
        switch sema.types.kind(of: signature.returnType) {
        case .unit, .nullableUnit, .platformUnit, .nothing, .error:
            return false
        default:
            break
        }
        let name = interner.resolve(symbol.name)
        guard name.count > 2,
              name.hasPrefix("is"),
              name[name.index(name.startIndex, offsetBy: 2)].isUppercase
        else {
            return false
        }
        guard let parentID = sema.symbols.parentSymbol(for: candidate),
              let parent = sema.symbols.symbol(parentID),
              parent.kind == .class || parent.kind == .interface
                  || parent.kind == .object || parent.kind == .enumClass
                  || parent.kind == .annotationClass,
              symbol.fqName == parent.fqName + [symbol.name]
        else {
            return false
        }
        return true
    }

    func isBundledJavaNominal(
        receiverType: TypeID?,
        ctx: TypeInferenceContext
    ) -> Bool {
        let sema = ctx.sema
        let interner = ctx.interner
        guard let receiverType,
              let nominalID = driver.helpers.nominalSymbol(
                  of: sema.types.makeNonNullable(receiverType),
                  types: sema.types
              ),
              let nominal = sema.symbols.symbol(nominalID),
              nominal.fqName.first == interner.intern("java")
        else {
            return false
        }
        if sema.bundledIndex.containsNominal(fqName: nominal.fqName)
            || sema.symbols.isImportedStdlibSymbol(nominalID)
        {
            return true
        }
        if let declFileID = sema.symbols.sourceFileID(for: nominalID) ?? nominal.declSite?.start.file,
           let sourceManager = ctx.visibilityChecker.sourceManager,
           sourceManager.origin(of: declFileID)?.isBundledStdlib == true
        {
            return true
        }
        return false
    }

    private func inferMemberCallOnReceiver(
        _ request: MemberCallInferenceRequest,
        receiverType: TypeID,
        locals: inout LocalBindings
    ) -> TypeID {
        if request.ctx.ast.arena.isInfixCall(request.id) {
            return inferRegularMemberCall(request, receiverType: receiverType, locals: &locals)
        }
        if ["transform", "transformLatest"].contains(request.ctx.interner.resolve(request.calleeName)),
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
                request.calleeName,
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

        if request.ctx.sema.requiresResolvedLibraryCalls,
           KnownCompilerNames(interner: request.ctx.interner).jvmSourceCollectionCalls.contains(request.calleeName)
        {
            return inferRegularMemberCall(request, receiverType: receiverType, locals: &locals)
        }

        let memberName = request.ctx.interner.resolve(request.calleeName)
        let isSuperReceiverCall: Bool = {
            if case .superRef = request.ctx.ast.arena.expr(request.receiverID) { return true }
            return false
        }()
        if memberName == "removeAll" || memberName == "retainAll",
           !hasUserDefinedMutableBulkCandidate(
               named: request.calleeName,
               receiverType: receiverType,
               isSuperCall: isSuperReceiverCall,
               ctx: request.ctx,
               locals: locals
           ),
           let result = bindMutableCollectionSourceExtension(
               exprID: request.id,
               memberName: request.calleeName,
               receiverID: request.receiverID,
               args: request.args,
               safeCall: request.safeCall,
               ctx: request.ctx,
               locals: &locals
           )
        {
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

    /// User-declared `removeAll`/`retainAll` members and extensions must reach
    /// the regular overload resolver: binding the bundled `kotlin.collections`
    /// source extension in `bindMutableCollectionSourceExtension` would
    /// otherwise hijack the call before those candidates are even collected
    /// (KUU-4297). Mirrors the bulk-candidate gate that
    /// `selectRegularMemberCallReceiverAndFallbacks` applies to `addAll`.
    func hasUserDefinedMutableBulkCandidate(
        named calleeName: InternedString,
        receiverType: TypeID,
        isSuperCall: Bool,
        ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> Bool {
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)
        guard !isSuperCall else { return false }
        let lookupReceiverType = sema.types.makeNonNullable(receiverType)
        let bulkReceiverFQName = sema.requiresResolvedLibraryCalls
            ? knownNames.kotlinCollectionsMutableCollectionFQName
            : knownNames.kotlinCollectionsMutableSetFQName
        guard sema.symbols.lookup(fqName: bulkReceiverFQName).map({ owner in
            driver.helpers.allNominalSymbols(
                of: lookupReceiverType, types: sema.types, symbols: sema.symbols
            ).contains {
                sema.types.isNominalSubtypeSymbol($0, of: owner)
            }
        }) == true else {
            return false
        }
        func isUserDeclared(_ candidate: SymbolID) -> Bool {
            guard let symbol = sema.symbols.symbol(candidate),
                  sema.symbols.isSourceBackedSymbol(candidate),
                  !symbol.fqName.starts(with: knownNames.kotlinCollectionsPackage),
                  !sema.symbols.isImportedStdlibSymbol(candidate)
            else { return false }
            if let declFileID = sema.symbols.sourceFileID(for: candidate)
                ?? symbol.declSite?.start.file,
               let sourceManager = ctx.visibilityChecker.sourceManager,
               sourceManager.origin(of: declFileID)?.isBundledStdlib == true
            {
                return false
            }
            return true
        }
        let memberCandidates = driver.helpers.collectMemberFunctionCandidates(
            named: calleeName,
            receiverType: lookupReceiverType,
            sema: sema,
            interner: interner
        )
        if memberCandidates.contains(where: { candidate in
            guard isUserDeclared(candidate),
                  let signature = sema.symbols.functionSignature(for: candidate)
            else { return false }
            return signature.parameterTypes.count == 1
        }) {
            return true
        }
        let extensionCandidates = collectExtensionCallCandidates(
            named: calleeName,
            memberLookupType: lookupReceiverType,
            isSuperCall: isSuperCall,
            supertypeSymbols: [],
            ctx: ctx,
            locals: locals,
            sema: sema,
            interner: interner
        )
        let (visibleExtensions, _) = ctx.filterByVisibility(extensionCandidates)
        return visibleExtensions.contains { candidate in
            guard isUserDeclared(candidate),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.count == 1,
                  let declaredReceiver = signature.receiverType
            else { return false }
            let receiverSymbols = driver.helpers.allNominalSymbols(
                of: lookupReceiverType, types: sema.types, symbols: sema.symbols
            )
            let declaredReceiverSymbols = driver.helpers.allNominalSymbols(
                of: declaredReceiver, types: sema.types, symbols: sema.symbols
            )
            return receiverSymbols.contains { actual in
                declaredReceiverSymbols.contains { declared in
                    sema.types.isNominalSubtypeSymbol(actual, of: declared)
                }
            }
        }
    }

    private func realMemberOwners(
        of root: SymbolID,
        sema: SemaModule
    ) -> Set<SymbolID> {
        var seen: Set<SymbolID> = []
        var queue = [root]
        while let owner = queue.popLast() {
            guard seen.insert(owner).inserted else { continue }
            queue.append(contentsOf: sema.symbols.directSupertypes(for: owner))
        }
        return seen
    }

    func resolveSuperMemberReceiverType(
        receiverID: ExprID,
        receiverType: TypeID,
        calleeName: InternedString,
        isPropertyAccess: Bool,
        ctx: TypeInferenceContext
    ) -> TypeID {
        let sema = ctx.sema
        guard case let .superRef(nil, label, range) = ctx.ast.arena.expr(receiverID) else {
            return receiverType
        }
        let currentType = label.flatMap { ctx.resolveQualifiedThis(label: $0) } ?? ctx.implicitReceiverType
        guard let currentType,
              case let .classType(currentClass) = sema.types.kind(of: currentType)
        else {
            return receiverType
        }

        var memberSupertypes: [TypeID] = []
        var concreteSupertypes: [TypeID] = []
        var implementationSupertypes: [TypeID] = []
        for superSymbol in sema.symbols.directSupertypes(for: currentClass.classSymbol) {
            let typeArgs = sema.types.liftedNominalSupertypeArgs(
                from: currentClass.classSymbol,
                childArgs: currentClass.args,
                to: superSymbol
            ) ?? []
            let superType = sema.types.make(.classType(ClassType(classSymbol: superSymbol, args: typeArgs)))
            let foundMembers: [SymbolID]
            if isPropertyAccess {
                foundMembers = driver.helpers.lookupMemberProperty(
                    named: calleeName,
                    receiverType: superType,
                    sema: sema
                ).map { [$0.symbol] } ?? []
            } else {
                foundMembers = driver.helpers.collectMemberFunctionCandidates(
                    named: calleeName,
                    receiverType: superType,
                    sema: sema,
                    interner: ctx.interner
                )
            }
            // Ambiguity counts only members the supertype reaches through real
            // supertype edges. Interface member lookups synthesize `kotlin.Any`
            // as a fallback owner, but `super.toString()` is not ambiguous just
            // because every interface can reach `Any` — the callee must live in
            // the supertype's own member scope (kotlinc diamond rule).
            let reachableOwners = realMemberOwners(of: superSymbol, sema: sema)
            let members = foundMembers.filter { member in
                reachableOwners.contains(sema.symbols.parentSymbol(for: member) ?? member)
            }
            guard !members.isEmpty else { continue }
            memberSupertypes.append(superType)
            let concreteMembers = members.filter { sema.symbols.symbol($0)?.flags.contains(.abstractType) == false }
            if !concreteMembers.isEmpty {
                concreteSupertypes.append(superType)
            }
            if concreteMembers.contains(where: { member in
                guard let owner = sema.symbols.parentSymbol(for: member),
                      sema.symbols.symbol(owner)?.kind == .interface,
                      let memberSymbol = sema.symbols.symbol(member)
                else { return true }
                guard !memberSymbol.flags.contains(.synthetic)
                        || memberSymbol.flags.contains(.importedLibrary)
                else { return false }
                return !sema.symbols.annotations(for: member).contains {
                    KnownCompilerAnnotation.ksSymbolName.matches($0.annotationFQName)
                }
            }) {
                implementationSupertypes.append(superType)
            }
        }

        let fallbackCandidates = concreteSupertypes.isEmpty ? memberSupertypes : concreteSupertypes
        let candidates = implementationSupertypes.isEmpty ? fallbackCandidates : implementationSupertypes
        if candidates.count > 1 {
            ctx.sema.diagnostics.error(
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
