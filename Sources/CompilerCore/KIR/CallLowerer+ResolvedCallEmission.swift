extension CallLowerer {
    /// Returns the `StringBuilder` class symbol when `symbolID` is one of its
    /// constructors, so callers can both gate on "is this a StringBuilder
    /// construction" and reuse the owner symbol for itable registration
    /// without a second lookup.
    private func stringBuilderConstructorOwner(
        _ symbolID: SymbolID?,
        sema: SemaModule,
        knownNames: KnownCompilerNames
    ) -> SymbolID? {
        guard let symbolID,
              sema.symbols.symbol(symbolID)?.kind == .constructor,
              let ownerSymbol = sema.symbols.parentSymbol(for: symbolID),
              let ownerInfo = sema.symbols.symbol(ownerSymbol),
              knownNames.isStringBuilderSymbol(ownerInfo)
        else {
            return nil
        }
        return ownerSymbol
    }

    /// True for the compiler-provided `kotlin.Any.<init>()`. Its constructor
    /// has no body; the normal constructor path already allocates and registers
    /// the object, so emitting a second call would create an undefined callee.
    private func isSyntheticAnyConstructor(
        _ symbolID: SymbolID?,
        sema: SemaModule
    ) -> Bool {
        guard let symbolID,
              let constructor = sema.symbols.symbol(symbolID),
              constructor.kind == .constructor,
              constructor.flags.contains(.synthetic),
              let ownerSymbol = sema.symbols.parentSymbol(for: symbolID)
        else {
            return false
        }
        return ownerSymbol == sema.types.anyClassSymbol
    }

    private func lowerStringBuilderConstructorCall(
        finalArgIDs: [KIRExprID],
        resultType: TypeID,
        nominalSymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let result = arena.appendTemporary(type: resultType)
        let runtimeCallee: InternedString
        let runtimeArgs: [KIRExprID]
        let canThrow: Bool
        let firstArgType = finalArgIDs.first.flatMap { arena.exprType($0) }
        if let firstArg = finalArgIDs.first,
           let firstArgType,
           sema.types.isSubtype(sema.types.makeNonNullable(firstArgType), sema.types.stringType)
        {
            runtimeCallee = interner.intern("__kk_string_builder_new_from_string_flat")
            runtimeArgs = [firstArg]
            canThrow = false
        } else if let firstArg = finalArgIDs.first,
                  let firstArgType,
                  let charSequenceSymbol = sema.types.charSequenceInterfaceSymbol,
                  sema.types.isSubtype(
                      sema.types.makeNonNullable(firstArgType),
                      sema.types.make(.classType(ClassType(
                          classSymbol: charSequenceSymbol,
                          args: [],
                          nullability: .nonNull
                      )))
                  )
        {
            runtimeCallee = interner.intern("__kk_string_builder_new_from_char_sequence")
            runtimeArgs = [firstArg]
            canThrow = false
        } else if let firstArg = finalArgIDs.first,
                  let firstArgType,
                  sema.types.isSubtype(sema.types.makeNonNullable(firstArgType), sema.types.intType)
        {
            // BUG-165: StringBuilder(capacity: Int) has no Kotlin-level body
            // to validate the argument itself (see StringBuilder.kt), so a
            // negative capacity must be rejected here — matching
            // kk_array_new_checked's precedent for the same
            // ignored-negative-size failure mode.
            runtimeCallee = interner.intern("__kk_string_builder_new_capacity_checked")
            runtimeArgs = [firstArg]
            canThrow = true
        } else {
            runtimeCallee = interner.intern("__kk_string_builder_new")
            runtimeArgs = []
            canThrow = false
        }
        instructions.append(.call(
            symbol: nil,
            callee: runtimeCallee,
            arguments: runtimeArgs,
            result: result,
            canThrow: canThrow,
            thrownResult: nil
        ))
        // BUG-166: StringBuilder instances bypass the normal kk_object_new
        // construction path (see the BUG-044 comment in RuntimeStringBuilder.swift),
        // so they never receive the itable registrations a regular class
        // constructor gets from KIRLoweringDriver+ObjectInitializer.swift.
        // Without this, dispatching a call through an Appendable/CharSequence-typed
        // reference to a StringBuilder finds no itable entry and panics with
        // KSWIFTK-RUNTIME-0001 ("method not found in vtable/itable") even though
        // `is`/`as` checks (registered separately in runtimeRegisterStringBuilderType)
        // succeed.
        appendObjectItableMethodRegistrations(
            objectValue: result,
            nominalSymbol: nominalSymbol,
            driver: driver,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        return result
    }

    /// True for runtime-backed factory constructors that allocate
    /// their own object (atomic scalar/array boxes and built-in exception classes).
    private func isAtomicScalarConstructor(
        _ symbolID: SymbolID?,
        sema: SemaModule,
        knownNames: KnownCompilerNames
    ) -> Bool {
        guard let symbolID,
              sema.symbols.symbol(symbolID)?.kind == .constructor,
              let ownerSymbol = sema.symbols.parentSymbol(for: symbolID),
              let ownerInfo = sema.symbols.symbol(ownerSymbol)
        else {
            return false
        }
        return knownNames.isAtomicScalarFactorySymbol(ownerInfo)
            || isRuntimeFactoryConstructor(symbolID, sema: sema)
    }

    private func hasFunctionValueParameter(_ symbolID: SymbolID, sema: SemaModule) -> Bool {
        guard let signature = sema.symbols.functionSignature(for: symbolID) else {
            return false
        }
        return signature.parameterTypes.contains { parameterType in
            if case .functionType = sema.types.kind(of: sema.types.makeNonNullable(parameterType)) {
                return true
            }
            return false
        }
    }

    private func lowerAtomicScalarConstructorCall(
        constructorSymbol: SymbolID,
        finalArgIDs: [KIRExprID],
        resultType: TypeID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let result = arena.appendTemporary(type: resultType)
        // The runtime factory (e.g. `kk_atomic_int_create`)
        // allocates the box itself; we must not precede it with `kk_object_new`
        // and an implicit `this` argument.
        let callee = sema.symbols.externalLinkName(for: constructorSymbol)
            .flatMap { name in name.isEmpty ? nil : interner.intern(name) }
            ?? interner.intern("__kk_atomic_unknown_create")
        let canThrow = sema.symbols.functionSignature(for: constructorSymbol)?.canThrow ?? false
        // Keep the constructor symbol on the call so ABI lowering can resolve the
        // FunctionSignature (e.g. type-parameter parameters for Pair/Triple) while
        // the runtime factory callee handles allocation directly.
        instructions.append(.call(
            symbol: constructorSymbol,
            callee: callee,
            arguments: finalArgIDs,
            result: result,
            canThrow: canThrow,
            thrownResult: nil
        ))
        appendRuntimeRangeItableRegistrations(
            objectValue: result, factoryName: callee,
            sema: sema, arena: arena, interner: interner, instructions: &instructions
        )
        if let owner = sema.symbols.parentSymbol(for: constructorSymbol),
           sema.symbols.symbol(owner)?.fqName == ["kotlin", "collections", "ArrayDeque"].map(interner.intern)
        {
            appendObjectVtableMethodRegistrations(
                objectValue: result,
                nominalSymbol: owner,
                driver: driver,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }
        return result
    }

    /// Emits the call/allocation instructions for an already-resolved call
    /// target: the callee (function, constructor, or callable value) and its
    /// arguments are already lowered by the time this runs. Shared by
    /// `lowerCallExpr` (plain `.call` nodes, which supply
    /// `loweredCalleeExprID`/`loweredCallable`/`callableValueCallBinding`
    /// derived from lowering `calleeExpr`) and
    /// `tryLowerFQNTopLevelResolvedCall` (namespace-qualified function/
    /// constructor calls reached via `.memberCall`, e.g.
    /// `kotlin.math.abs(x)` or `kotlin.text.StringBuilder()`, which have no
    /// callee expression to lower at all — `chosen` and `callBinding` come
    /// directly from Sema's FQN top-level resolution, so
    /// `loweredCalleeExprID`/`loweredCallable`/`callableValueCallBinding` are
    /// always nil there).
    // swiftlint:disable:next cyclomatic_complexity
    func lowerResolvedCallBody(
        _ exprID: ExprID,
        args: [CallArgument],
        loweredArgIDs: [KIRExprID],
        chosen: SymbolID?,
        callBinding: CallBinding?,
        callableValueCallBinding: CallableValueCallBinding?,
        loweredCallable: KIRCallableValueInfo?,
        loweredCalleeExprID: KIRExprID?,
        sourceCalleeName: InternedString,
        boundType: TypeID?,
        knownNames: KnownCompilerNames,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let result = arena.appendTemporary(type: boundType ?? sema.types.anyType)
        let callNormalized: NormalizedCallResult = if callBinding != nil {
            driver.callSupportLowerer.normalizedCallArguments(
                providedArguments: loweredArgIDs,
                callBinding: callBinding,
                chosenCallee: chosen,
                spreadFlags: args.map(\.isSpread),
                argumentLabels: args.map(\.label),
                sourceArgExprs: args.map(\.expr),
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        } else {
            NormalizedCallResult(
                arguments: normalizedCallableValueArguments(
                    providedArguments: loweredArgIDs,
                    callableValueCallBinding: callableValueCallBinding,
                    sema: sema
                ),
                defaultMask: 0
            )
        }
        var finalArgIDs = callNormalized.arguments
        var implicitReceiverDispatch: (receiver: KIRExprID, kind: KIRDispatchKind)?
        var implicitReceiverRuntimeCallee: InternedString?
        // Compiler-generated lambdas/local functions use the compiler ABI
        // (including the hidden thrown channel), so route them through their
        // lowered symbol directly instead of Swift closure helpers.
        let callableInvokeCallee: InternedString? = if loweredCallable == nil {
            runtimeCallableInvokeCallee(
                callableValueCallBinding: callableValueCallBinding,
                sema: sema,
                interner: interner
            )
        } else {
            nil
        }
        let isAtomicFactory = chosen.map {
            isAtomicScalarConstructor($0, sema: sema, knownNames: knownNames)
        } ?? false
        if callableInvokeCallee == nil,
           loweredCallable == nil,
           let stringBuilderOwnerSymbol = stringBuilderConstructorOwner(chosen, sema: sema, knownNames: knownNames)
        {
            return lowerStringBuilderConstructorCall(
                finalArgIDs: finalArgIDs,
                resultType: boundType ?? sema.types.anyType,
                nominalSymbol: stringBuilderOwnerSymbol,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }
        if callableInvokeCallee == nil,
           loweredCallable == nil,
           let chosen,
           isAtomicFactory,
           !hasFunctionValueParameter(chosen, sema: sema)
        {
            // This factory bridge allocates and returns the object itself (KUU-548):
            // it never goes through the constructor branch below, so a function-typed
            // argument stored into one of its erased type-param slots (e.g. Pair's
            // `first: A`) would otherwise reach `__kk_pair_new` as a bare, unwrapped
            // lambda symbolRef -- the same erased-boundary wrapping every other
            // typeParam-typed argument gets here. `finalArgIDs` holds plain value
            // arguments here (no `kk_object_new`-allocated `this` prepended, unlike
            // the constructor branch below), so index by position with no offset.
            materializeSourceBackedFunctionValueArguments(
                chosenCallee: chosen,
                sourceArgExprs: args.map(\.expr),
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions,
                arguments: &finalArgIDs,
                valueArgOffsetOverride: 0
            )
            return lowerAtomicScalarConstructorCall(
                constructorSymbol: chosen,
                finalArgIDs: finalArgIDs,
                resultType: boundType ?? sema.types.anyType,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }
        if callableInvokeCallee != nil, let loweredCalleeExprID {
            finalArgIDs.insert(loweredCalleeExprID, at: 0)
            if let callableValueCallBinding,
               case let .functionType(functionType) = sema.types.kind(
                   of: sema.types.makeNonNullable(callableValueCallBinding.functionType)
               ),
               functionType.receiver != nil,
               // `finalArgIDs` here is `[closure] + normalizedArgs`.
               // When the receiver was already supplied positionally
               // (`ef(3, 4)`), normalizedArgs already has `params.count + 1`
               // elements and finalArgIDs.count is params.count + 2 -- there
               // is no missing receiver slot to fill from the ambient scope.
               finalArgIDs.count == functionType.params.count + 1
            {
                // A receiver-function value invoked as `block()` inside a
                // receiver scope uses the active implicit receiver as its
                // dispatch receiver (e.g. the bodies of T.run and T.apply).
                let implicitReceiver = sema.bindings.implicitExtensionReceiver(for: exprID)
                    .flatMap { driver.ctx.localValue(for: $0) }
                    ?? driver.ctx.activeImplicitReceiverExprID()
                if let implicitReceiver { finalArgIDs.insert(implicitReceiver, at: 1) }
            }
        }
        if callableInvokeCallee == nil, let loweredCallable {
            if let callableValueCallBinding,
               case let .functionType(functionType) = sema.types.kind(
                   of: sema.types.makeNonNullable(callableValueCallBinding.functionType)
               ),
               functionType.receiver != nil,
               finalArgIDs.count == functionType.params.count {
                let implicitReceiver = sema.bindings.implicitExtensionReceiver(for: exprID)
                    .flatMap { driver.ctx.localValue(for: $0) }
                    ?? driver.ctx.activeImplicitReceiverExprID()
                if let implicitReceiver { finalArgIDs.insert(implicitReceiver, at: 0) }
            }
            finalArgIDs.insert(contentsOf: loweredCallable.captureArguments, at: 0)
        } else if let chosen,
                  !isAtomicFactory,
                  sema.symbols.symbol(chosen)?.kind == .constructor
        {
            // Constructor calls need an allocated object as the implicit receiver.
            // Resolve an inner class's enclosing instance from the active receiver.
            let allocatedObj = allocateAndRegisterConstructedObject(
                chosen: chosen,
                boundType: boundType,
                outerReceiver: driver.ctx.activeImplicitReceiverExprID(),
                driver: driver,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            // KUU-555: a local class's `<init>` runs as an independent KIR
            // function — materialize captured outer locals into the fresh
            // instance's fields here, where the enclosing scope's locals are
            // still active (same convention as object-literal capture
            // materialization in `lowerStoredObjectLiteralExpr`).
            if let ownerNominalSymbol = sema.symbols.parentSymbol(for: chosen),
               let layout = sema.symbols.nominalLayout(for: ownerNominalSymbol)
            {
                let intType = sema.types.make(.primitive(.int, .nonNull))
                for capturedSymbol in sema.bindings.objectLiteralCaptureSymbols(for: ownerNominalSymbol) {
                    guard let fieldOffset = layout.fieldOffsets[capturedSymbol],
                          let captureValue = driver.lambdaLowerer.captureValueExpr(
                              for: capturedSymbol,
                              sema: sema,
                              arena: arena,
                              interner: interner,
                              instructions: &instructions
                          )
                    else {
                        continue
                    }
                    let captureOffsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: intType)
                    instructions.append(.constValue(
                        result: captureOffsetExpr,
                        value: .intLiteral(Int64(fieldOffset))
                    ))
                    let captureSetResult = arena.appendTemporary(type: sema.types.anyType)
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_array_set"),
                        arguments: [allocatedObj, captureOffsetExpr, captureValue],
                        result: captureSetResult,
                        canThrow: true,
                        thrownResult: nil
                    ))
                }
            }
            finalArgIDs.insert(allocatedObj, at: 0)
            if isSyntheticAnyConstructor(chosen, sema: sema) {
                // Any's implicit constructor is represented by allocation only;
                // there is no source or runtime constructor body to call.
                instructions.append(.copy(from: allocatedObj, to: result))
                return result
            }
        } else if let chosen,
                  let signature = sema.symbols.functionSignature(for: chosen),
                  signature.receiverType != nil,
                  !runtimeExternalOmitsObjectReceiver(chosen, sema: sema)
        {
            // A call that Sema resolved on an *outer* implicit receiver (e.g.
            // an enclosing class's member invoked unqualified from an object
            // literal's member body) reads the receiver through the captured
            // enclosing `this`, not the member's own implicit receiver.
            var implicitReceiver = sema.bindings.implicitReceiverOuterReceiver(for: exprID)
                .flatMap { driver.ctx.localValue(for: $0) }
            if memberExtensionOwnerSymbol(for: chosen, sema: sema) != nil {
                // Member extensions carry a dispatch receiver ahead of the
                // extension receiver: `implicitReceiverOuterReceiver` names
                // the *dispatch* side, so the extension receiver must come
                // from an implicit receiver whose type is a subtype of the
                // declared receiver — the innermost `this` first, then a
                // labeled/captured receiver that happens to match.
                func matchesDeclaredReceiver(_ candidate: KIRExprID?) -> Bool {
                    guard let candidate,
                          let declaredReceiver = signature.receiverType,
                          let type = arena.exprType(candidate)
                    else { return false }
                    return sema.types.isSubtype(
                        sema.types.makeNonNullable(type),
                        sema.types.makeNonNullable(declaredReceiver)
                    )
                }
                if !matchesDeclaredReceiver(implicitReceiver) {
                    implicitReceiver = nil
                    // Sema records which receiver-tower entry supplies the
                    // extension receiver (e.g. the enclosing Int receiver
                    // parameter captured into a `with("s")` lambda), so read
                    // that exact value first — the active receiver may be an
                    // unrelated shadowing receiver.
                    if let receiverSymbol = sema.bindings.implicitExtensionReceiver(for: exprID),
                       let receiverValue = driver.ctx.localValue(for: receiverSymbol),
                       matchesDeclaredReceiver(receiverValue)
                    {
                        implicitReceiver = receiverValue
                    } else if let activeReceiver = driver.ctx.activeImplicitReceiverExprID(),
                              matchesDeclaredReceiver(activeReceiver)
                    {
                        implicitReceiver = activeReceiver
                    } else if let owner = sema.symbols.parentSymbol(for: chosen),
                              let ownerName = sema.symbols.symbol(owner)?.name,
                              let qualifiedThis = driver.ctx.qualifiedThisReceiverExprID(for: ownerName),
                              matchesDeclaredReceiver(qualifiedThis)
                    {
                        implicitReceiver = qualifiedThis
                    }
                }
                if implicitReceiver == nil {
                    implicitReceiver = driver.ctx.activeImplicitReceiverExprID()
                }
            } else if let owner = sema.symbols.parentSymbol(for: chosen)
            {
                if let activeReceiver = driver.ctx.activeImplicitReceiverExprID(),
                   let activeType = arena.exprType(activeReceiver),
                   case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(activeType)),
                   sema.types.isNominalSubtypeSymbol(classType.classSymbol, of: owner)
                {
                    implicitReceiver = activeReceiver
                } else if let dispatchReceiver = driver.ctx.capturedOuterReceiverExprID(for: owner)
                    ?? driver.ctx.capturedOuterReceiverExprID(reaching: owner, sema: sema)
                {
                    implicitReceiver = dispatchReceiver
                }
            }
            // Inside a member-extension body the active implicit receiver is
            // the extension receiver, but an unqualified call to an enclosing
            // member must dispatch on the `this@Owner` parameter instead.
            if implicitReceiver == nil,
               let owner = sema.symbols.parentSymbol(for: chosen),
               let ownerName = sema.symbols.symbol(owner)?.name,
               let qualifiedThis = driver.ctx.qualifiedThisReceiverExprID(for: ownerName)
            {
                implicitReceiver = qualifiedThis
            }
            if implicitReceiver == nil {
                implicitReceiver = driver.ctx.activeImplicitReceiverExprID()
                // A bare call inside an object literal can resolve to a member of
                // its enclosing class. The literal is the active receiver while
                // lowering its member body, so use the captured enclosing receiver
                // when the callee's owner is available as a captured local value.
                // (An inner class's own enclosing instance isn't captured this
                // way -- it's resolved through the `$outer` chain below instead.)
                if let owner = sema.symbols.parentSymbol(for: chosen),
                   owner != driver.ctx.activeImplicitReceiverSymbol(),
                   let capturedReceiver = driver.ctx.localValue(for: owner)
                       ?? driver.ctx.capturedOuterReceiverExprID(reaching: owner, sema: sema)
                {
                    implicitReceiver = capturedReceiver
                }
            }
            if let owner = sema.symbols.parentSymbol(for: chosen),
               let containingClass = sema.symbols.parentSymbol(for: owner),
               sema.symbols.companionObjectSymbol(for: containingClass) == owner,
               let receiverType = signature.receiverType,
               case let .classType(receiverClass) = sema.types.kind(of: receiverType),
               receiverClass.classSymbol == owner
            {
                driver.emitObjectLazyInitGuardIfNeeded(
                    objectSymbol: owner, arena: arena, sema: sema, instructions: &instructions
                )
                let receiver = arena.appendExpr(.symbolRef(owner), type: receiverType)
                instructions.append(.constValue(result: receiver, value: .symbolRef(owner)))
                implicitReceiver = receiver
            }
            if implicitReceiver == nil,
               sema.bindings.isCoroutineScopeImplicitReceiverCall(exprID)
            {
                let receiver = arena.appendTemporary(type: signature.receiverType ?? sema.types.anyType)
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_coroutine_current_scope"),
                    arguments: [],
                    result: receiver,
                    canThrow: false,
                    thrownResult: nil
                ))
                implicitReceiver = receiver
            }
            // An inner class's active implicit receiver is the inner instance,
            // but an unqualified call to a member declared on an enclosing
            // class must use that enclosing instance as its dispatch receiver.
            // Resolve through the same `$outer` chain used by field accesses;
            // for ordinary subtype/interface dispatch the helper returns the
            // existing receiver unchanged.
            if let owner = sema.symbols.parentSymbol(for: chosen),
               let receiver = implicitReceiver,
               let ownerReceiver = resolveOuterChainValue(
                   from: receiver,
                   to: owner,
                   sema: sema,
                   arena: arena,
                   interner: interner,
                   instructions: &instructions
               )
            {
                implicitReceiver = ownerReceiver
            }
            if let extensionReceiver = implicitReceiver {
                finalArgIDs.insert(extensionReceiver, at: 0)
                if let dispatchReceiver = memberExtensionDispatchReceiver(
                    for: chosen,
                    callExprID: exprID,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                ) {
                    finalArgIDs.insert(dispatchReceiver, at: 0)
                    implicitReceiver = dispatchReceiver
                }
                // Runtime-backed MutableSet values (including collection
                // builder receivers) do not carry a Kotlin itable for the
                // source-backed default mutation members. Resolve those
                // implicit calls to their demoted ABI bridges before the
                // generic virtual-dispatch path is selected.
                let implicitReceiverType = arena.exprType(implicitReceiver ?? extensionReceiver)
                    ?? signature.receiverType
                    ?? sema.types.anyType
                implicitReceiverRuntimeCallee = runtimeBackedSetMemberCallee(
                    memberName: interner.resolve(sourceCalleeName),
                    receiverType: implicitReceiverType,
                    chosenCallee: chosen,
                    sema: sema,
                    interner: interner
                ) ?? runtimeBackedListMemberCallee(
                    memberName: interner.resolve(sourceCalleeName),
                    receiverType: implicitReceiverType,
                    chosenCallee: chosen,
                    sema: sema,
                    interner: interner
                )
            }
            // An unqualified `compute()` inside a member body is `this.compute()`
            // and must dispatch through the receiver's vtable/itable exactly like
            // the explicit form: a subclass override, or a base-class
            // implementation of an interface method, is otherwise bypassed.
            // SequenceScope calls use runtime-owned builder receivers, so their
            // remapped ABI entry points must remain direct calls.
            //
            // Source-declared callees (no link name) always take this path.
            // Imported `kk_fn_*` members only take it when the callee is
            // abstract: kklib emits a no-op stub for abstract declarations, so
            // a direct call silently does nothing (KUU-962: `registerClause`
            // inside `SelectBuilder` member extensions). Non-abstract
            // `kk_fn_*` members (`external` runtime bridges like
            // `MutableCollection.remove`, and members with real bodies) are
            // callable directly — virtual dispatch on them would also break
            // receivers whose runtime box never registered the interface
            // itable (`kk_itable_lookup_dynamic` → dispatch error).
            let chosenLinkName = sema.symbols.externalLinkName(for: chosen)
            let isUnlinkedSourceCallee = chosenLinkName?.isEmpty ?? true
            let isAbstractLinkedCallee = CallLowerer.isSourceBackedLinkName(chosenLinkName)
                && !isUnlinkedSourceCallee
                && sema.symbols.symbol(chosen)?.flags.contains(.abstractType) == true
            if let implicitReceiver,
               implicitReceiverRuntimeCallee == nil,
               isUnlinkedSourceCallee || isAbstractLinkedCallee,
               sequenceBuilderRuntimeCalleeName(
                   chosenCallee: chosen,
                   calleeName: sourceCalleeName,
                   sema: sema,
                   interner: interner
               ) == nil
            {
                implicitReceiverDispatch = resolveVirtualDispatch(
                    callee: chosen,
                    receiverTypeID: arena.exprType(implicitReceiver),
                    sema: sema,
                    interner: interner
                ).map { (receiver: implicitReceiver, kind: $0) }
            }
        }
        if loweredCallable == nil {
            adaptCoroutineLauncherBlock(
                chosenCallee: chosen,
                sourceArgExprs: args.map(\.expr),
                sema: sema, arena: arena, interner: interner,
                instructions: &instructions, arguments: &finalArgIDs
            )
            materializeSourceBackedFunctionValueArguments(
                chosenCallee: chosen,
                sourceArgExprs: args.map(\.expr),
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions,
                arguments: &finalArgIDs
            )
        }
        if loweredCallable == nil, let chosen {
            finalArgIDs = appendClosureArgumentsIfNeeded(
                finalArgIDs,
                originalArgs: args,
                chosenCallee: chosen,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }
        // Inject callable value captures for coroutine launcher arguments.
        // When a suspend lambda/closure with captures is passed to a launcher
        // (runBlocking/launch/async), the capture values must be included in
        // the call arguments so the CoroutineLoweringPass can store them in
        // the continuation via launcherArgs and forward them through the thunk.
        // Guard on chosen == nil && loweredCallable == nil to avoid misfiring
        // on user-defined functions that happen to share a launcher name.
        // Only expand captures for the launcher entry function reference; the
        // remaining arguments are value args for the referenced suspend
        // function and should not be expanded. The entry reference is normally
        // arguments[0], but a dispatcher-aware `launch(dispatcher) { ... }`
        // carries the dispatcher at arguments[0] and the suspend lambda at
        // arguments[1] (matching rewriteLauncherCall's dispatcher-aware path),
        // so scan for the first argument that actually is a callable value and
        // insert its captures right after it.
        if loweredCallable == nil {
            // KSP-1573: `kotlinx.coroutines.channels.produce` is now a real
            // bundled-source function whose block is a boxed suspend lambda —
            // its captures travel inside the callable's closure env, so this
            // thunk-style capture expansion must only run for the synthetic
            // launcher symbols (runBlocking/launch/async/produce stubs).
            // Imported library declarations always carry `.synthetic` (they
            // have no source declSite), so a genuinely imported produce must
            // be excluded here too or its captures would be flattened into
            // trailing call args and break the kirbin expansion's arity.
            let isSyntheticCoroutineLauncher: Bool = if let chosen,
                                                        let chosenInfo = sema.symbols.symbol(chosen)
            {
                chosenInfo.flags.contains(.synthetic)
                    && !chosenInfo.flags.contains(.importedLibrary)
                    && (chosenInfo.fqName == knownNames.kotlinxCoroutinesRunBlockingFQName
                        || chosenInfo.fqName == knownNames.kotlinxCoroutinesLaunchFQName
                        || chosenInfo.fqName == knownNames.kotlinxCoroutinesAsyncFQName
                        || chosenInfo.fqName == knownNames.kotlinxCoroutinesProduceFQName)
            } else {
                true
            }
            if isSyntheticCoroutineLauncher,
               sourceCalleeName == knownNames.runBlocking
               || sourceCalleeName == knownNames.launch
               || sourceCalleeName == knownNames.async
               || sourceCalleeName == knownNames.produce
            {
                // A leading dispatcher (only valid for `launch`) pushes the
                // entry reference to index 1; otherwise it is index 0.
                let entryIndex = finalArgIDs.indices.first { index in
                    driver.ctx.callableValueInfo(for: finalArgIDs[index]) != nil
                }
                if let entryIndex,
                   entryIndex <= 1,
                   let callableInfo = driver.ctx.callableValueInfo(for: finalArgIDs[entryIndex]),
                   !callableInfo.captureArguments.isEmpty
                {
                    finalArgIDs.insert(contentsOf: callableInfo.captureArguments, at: entryIndex + 1)
                }
            }
        }
        if sourceCalleeName == knownNames.withContext
            || sourceCalleeName == knownNames.withTimeout
            || sourceCalleeName == knownNames.withTimeoutOrNull,
           finalArgIDs.count >= 2,
           let callableInfo = driver.ctx.callableValueInfo(for: finalArgIDs[1]),
           !callableInfo.captureArguments.isEmpty
        {
            finalArgIDs.insert(contentsOf: callableInfo.captureArguments, at: 2)
        }
        // KUU-938: this synthetic conversion has no runtime symbol. The
        // receiver has already been inserted above, including for an outer
        // implicit receiver; preserve its raw primitive representation.
        if let chosen,
           sema.symbols.symbol(chosen)?.flags.contains(.synthetic) == true,
           sema.symbols.externalLinkName(for: chosen) == "kk_primitive_identity",
           finalArgIDs.count == 1
        {
            instructions.append(.copy(from: finalArgIDs[0], to: result))
            return result
        }
        // KUU-655: an override that inherits its defaults never has its own
        // stub; resolve to the base declaration's stub instead (see
        // `defaultStubOwnerSymbol`).
        let defaultStubOwner = chosen.map { driver.callSupportLowerer.defaultStubOwnerSymbol(for: $0, sema: sema) }
        if callNormalized.defaultMask != 0,
           let chosen,
           let defaultStubOwner,
           (sema.symbols.externalLinkName(for: chosen)?.isEmpty ?? true ||
            sema.symbols.externalLinkName(for: driver.callSupportLowerer.defaultStubSymbol(for: defaultStubOwner)) != nil)
        {
            appendReifiedTypeTokens(
                chosenCallee: chosen,
                callBinding: callBinding,
                sema: sema,
                interner: interner,
                arena: arena,
                instructions: &instructions,
                arguments: &finalArgIDs
            )
            appendDefaultMaskArgument(
                callNormalized.defaultMask,
                sema: sema,
                arena: arena,
                instructions: &instructions,
                arguments: &finalArgIDs
            )
            let stubName = interner.intern(interner.resolve(sourceCalleeName) + "$default")
            let stubSym = driver.callSupportLowerer.defaultStubSymbol(for: defaultStubOwner)
            instructions.append(.call(
                symbol: stubSym,
                callee: stubName,
                arguments: finalArgIDs,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
        } else {
            appendReifiedTypeTokens(
                chosenCallee: chosen,
                callBinding: callBinding,
                sema: sema,
                interner: interner,
                arena: arena,
                instructions: &instructions,
                arguments: &finalArgIDs
            )
            let loweredCalleeName: InternedString = if let callableInvokeCallee {
                callableInvokeCallee
            } else if let chosen,
                      let sequenceBuilderCallee = sequenceBuilderRuntimeCalleeName(
                          chosenCallee: chosen,
                          calleeName: sourceCalleeName,
                          sema: sema,
                          interner: interner
                      )
            {
                sequenceBuilderCallee
            } else if let implicitReceiverRuntimeCallee {
                implicitReceiverRuntimeCallee
            } else if let chosen,
                                                       let externalLinkName = sema.symbols.externalLinkName(for: chosen),
                                                       !externalLinkName.isEmpty
            {
                interner.intern(externalLinkName)
            } else if let loweredCallable {
                loweredCallable.callee
            } else if chosen == nil {
                driver.callSupportLowerer.loweredRuntimeBuiltinCallee(
                    for: sourceCalleeName,
                    argumentCount: finalArgIDs.count,
                    argumentTypes: finalArgIDs.map { arena.exprType($0) ?? sema.types.anyType },
                    interner: interner,
                    types: sema.types,
                    knownNames: knownNames
                ) ?? sourceCalleeName
            } else {
                sourceCalleeName
            }
            if loweredCalleeName == interner.intern("__kk_throwable_new"), finalArgIDs.isEmpty {
                // Throwable() and the zero-argument synthetic exception constructors
                // route here, but the runtime bridge still expects a nullable message
                // pointer. Pass the null sentinel so it defaults to "Throwable".
                let nullMessageExpr = arena.appendExpr(
                    .intLiteral(Int64.min),
                    type: sema.types.intType
                )
                instructions.append(.constValue(result: nullMessageExpr, value: .intLiteral(Int64.min)))
                finalArgIDs.append(nullMessageExpr)
            } else if loweredCalleeName == interner.intern("kk_coroutine_cancel_current"),
                      finalArgIDs.count == 1
            {
                // The synthetic one-argument `cancel(message)` overload lowers
                // to the same runtime ABI as the two-argument overload and
                // supplies a null cause implicitly.
                let nullCauseExpr = arena.appendExpr(
                    .intLiteral(0),
                    type: sema.types.intType
                )
                instructions.append(.constValue(result: nullCauseExpr, value: .intLiteral(0)))
                finalArgIDs.append(nullCauseExpr)
            } else if loweredCalleeName == interner.intern("kk_channel_send")
                || loweredCalleeName == interner.intern("kk_channel_receive")
                || loweredCalleeName == interner.intern("kk_mutex_lock")
                || loweredCalleeName == interner.intern("__kk_mutex_lock_owner")
                || loweredCalleeName == interner.intern("kk_semaphore_acquire")
            {
                // Implicit-receiver calls (e.g. `send(x)` inside a `produce { }`
                // block) reach this path instead of `emitMemberCallInstruction`,
                // which normally appends the zero continuation placeholder for
                // these callees. Without it the runtime ABI receives one fewer
                // argument than expected.
                let continuationExpr = arena.appendExpr(
                    .intLiteral(0),
                    type: sema.types.intType
                )
                instructions.append(.constValue(result: continuationExpr, value: .intLiteral(0)))
                finalArgIDs.append(continuationExpr)
            }
            let callCanThrow = needsThrownChannel(calleeName: loweredCalleeName, interner: interner)
            let thrownResult = callCanThrow
                ? arena.appendTemporary(type: sema.types.nullableAnyType
                )
                : nil
            let arrayResultTypeID = runtimeArrayNominalTypeID(
                boundType ?? arena.exprType(result),
                sema: sema,
                interner: interner
            )
            let callResult: KIRExprID = if arrayResultTypeID != nil {
                arena.appendTemporary(type: boundType ?? arena.exprType(result))
            } else {
                result
            }
            // When calling a callable value (function-type local/parameter),
            // use its symbol so InlineLoweringPass can match it against lambda
            // parameter symbols and expand the lambda body in place.
            let callSymbol: SymbolID? = (chosen ?? loweredCallable?.symbol ?? {
                if let binding = callableValueCallBinding,
                   case let .localValue(sym) = binding.target
                {
                    return sym
                }
                return nil
            }())
            if let implicitReceiverDispatch, finalArgIDs.first == implicitReceiverDispatch.receiver {
                instructions.append(.virtualCall(
                    symbol: callSymbol,
                    callee: loweredCalleeName,
                    receiver: implicitReceiverDispatch.receiver,
                    arguments: Array(finalArgIDs.dropFirst()),
                    result: callResult,
                    canThrow: callCanThrow,
                    thrownResult: thrownResult,
                    dispatch: implicitReceiverDispatch.kind
                ))
            } else {
                instructions.append(.call(
                    symbol: callSymbol,
                    callee: loweredCalleeName,
                    arguments: finalArgIDs,
                    result: callResult,
                    canThrow: callCanThrow,
                    thrownResult: thrownResult
                ))
            }
            appendRuntimeRangeItableRegistrations(
                objectValue: callResult, factoryName: loweredCalleeName,
                sema: sema, arena: arena, interner: interner, instructions: &instructions
            )
            if let arrayResultTypeID {
                let typeIDExpr = arena.appendExpr(
                    .intLiteral(arrayResultTypeID),
                    type: sema.types.intType
                )
                instructions.append(.constValue(
                    result: typeIDExpr,
                    value: .intLiteral(arrayResultTypeID)
                ))
                let taggedResult = arena.appendTemporary(type: boundType ?? arena.exprType(result))
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_array_tag_type"),
                    arguments: [callResult, typeIDExpr],
                    result: taggedResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                instructions.append(.copy(from: taggedResult, to: result))
            }
            if let thrownResult,
               shouldRethrowThrownChannelResult(calleeName: loweredCalleeName, interner: interner)
            {
                let continueLabel = driver.ctx.makeLoopLabel()
                let rethrowLabel = driver.ctx.makeLoopLabel()
                instructions.append(.jumpIfNotNull(value: thrownResult, target: rethrowLabel))
                instructions.append(.jump(continueLabel))
                instructions.append(.label(rethrowLabel))
                instructions.append(.rethrow(value: thrownResult))
                instructions.append(.label(continueLabel))
            }
        }
        return result
    }
}
