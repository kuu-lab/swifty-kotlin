
extension KIRLoweringDriver {

    func lowerConstructor(
        ctorSymbol: SymbolID,
        ctorFQName: [InternedString],
        classDecl: ClassDecl,
        ownerSymbol: SymbolID,
        shared: KIRLoweringSharedContext
    ) -> [KIRDeclID] {
        let sema = shared.sema

        // Constructors with an external link name are implemented by the
        // runtime. Do not emit a synthetic constructor body: NativeEmitter
        // registers every emitted KIRFunction as an internal definition, and
        // that definition would shadow the runtime entry point at call sites.
        if let externalLink = sema.symbols.externalLinkName(for: ctorSymbol), !externalLink.isEmpty {
            return []
        }

        // Paired expect/actual classes share an FQName, so looking up
        // `<init>` by FQName returns constructors from both declarations.
        // Only lower the constructor owned by this class declaration;
        // lowering both bodies under the same symbol creates duplicate KIR
        // definitions, and the expect body's empty initializer can win at
        // codegen time.
        guard sema.symbols.parentSymbol(for: ctorSymbol) == ownerSymbol else {
            return []
        }

        let arena = shared.arena
        guard let signature = sema.symbols.functionSignature(for: ctorSymbol) else {
            return []
        }
        ctx.resetScopeForFunction()
        ctx.beginCallableLoweringScope()
        ctx.setCurrentFunctionSymbol(ctorSymbol)

        let receiverSymbol = callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: ctorSymbol)
        var params = [KIRParameter(symbol: receiverSymbol, type: signature.returnType)]
        ctx.setImplicitReceiver(
            symbol: receiverSymbol,
            exprID: arena.appendExpr(.symbolRef(receiverSymbol), type: signature.returnType)
        )
        for (index, parameterSymbol) in signature.valueParameterSymbols.enumerated() {
            params.append(KIRParameter(
                symbol: parameterSymbol,
                type: constructorParameterStorageType(
                    at: index, signature: signature, sema: sema, interner: shared.interner
                )
            ))
        }

        let body = buildConstructorBody(
            ctorSymbol: ctorSymbol, ctorFQName: ctorFQName,
            classDecl: classDecl, ownerSymbol: ownerSymbol,
            shared: shared
        )

        let decls = finalizeConstructorDecl(
            ctorSymbol: ctorSymbol, classDecl: classDecl,
            params: params, returnType: signature.returnType,
            body: body, signature: signature, shared: shared
        )
        ctx.setCurrentFunctionSymbol(nil)
        return decls
    }

    /// The semantic signature records vararg element types; constructor bodies
    /// and synthetic reflection wrappers receive one packed array instead.
    func constructorParameterStorageType(
        at index: Int,
        signature: FunctionSignature,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        let parameterType = signature.parameterTypes[index]
        guard signature.valueParameterIsVararg.indices.contains(index),
              signature.valueParameterIsVararg[index]
        else {
            return parameterType
        }
        if let arrayType = primitiveVarargArrayType(
            elementType: parameterType, sema: sema, interner: interner
        ) {
            return arrayType
        }
        return referenceVarargArrayType(
            elementType: parameterType, sema: sema, interner: interner
        ) ?? parameterType
    }

    private func buildConstructorBody(
        ctorSymbol: SymbolID,
        ctorFQName: [InternedString],
        classDecl: ClassDecl,
        ownerSymbol: SymbolID,
        shared: KIRLoweringSharedContext
    ) -> KIRLoweringEmitContext {
        let sema = shared.sema
        var body: KIRLoweringEmitContext = [.beginBlock]
        // Constructing a class is an active use of that class on the JVM.
        // Its companion initializer — whose own body first runs the
        // supertype companion initializers (KUU-3225) — executes before
        // superclass or instance init code. A companion-less class still
        // owes its supertype chain's initialization.
        if let companionSymbol = sema.symbols.companionObjectSymbol(for: ownerSymbol) {
            emitObjectLazyInitGuardIfNeeded(
                objectSymbol: companionSymbol,
                arena: shared.arena,
                sema: sema,
                interner: shared.interner,
                instructions: &body.instructions
            )
        } else {
            emitSupertypeCompanionInitCalls(
                for: ownerSymbol,
                sema: sema,
                arena: shared.arena,
                interner: shared.interner,
                instructions: &body.instructions
            )
        }
        if let receiverBinding = ctx.activeImplicitReceiver() {
            body.append(.constValue(result: receiverBinding.exprID, value: .symbolRef(receiverBinding.symbol)))
        }
        // Constructor parameters are not member properties: lambdas nested in
        // delegation arguments or property initializers capture them through
        // the local-value table, so bind each parameter's symbolRef here —
        // otherwise the lambda frame reads an uninitialised slot (0).
        if let signature = sema.symbols.functionSignature(for: ctorSymbol) {
            for (index, parameterSymbol) in signature.valueParameterSymbols.enumerated() {
                guard ctx.localValue(for: parameterSymbol) == nil else { continue }
                let paramExpr = shared.arena.appendExpr(
                    .symbolRef(parameterSymbol),
                    type: constructorParameterStorageType(
                        at: index, signature: signature,
                        sema: sema, interner: shared.interner
                    )
                )
                body.append(.constValue(result: paramExpr, value: .symbolRef(parameterSymbol)))
                ctx.setLocalValue(paramExpr, for: parameterSymbol)
            }
        }
        // KUU-555: a local class's `<init>` is an independent KIR function —
        // captured outer locals (stored into instance fields at the
        // construction call site) must be read back before super-delegation
        // args, initializers or init blocks reference them. No-ops for named
        // classes, which carry no capture list.
        objectLiteralLowerer.restoreObjectLiteralCaptures(
            forMemberFunction: ctorSymbol,
            sema: sema,
            arena: shared.arena,
            interner: shared.interner,
            instructions: &body.instructions
        )
        // Seed `lateinit` and explicit-null storage before delegation so
        // superclass `init` sees the correct sentinel and virtual writes survive.
        emitLateinitFieldSentinels(classDecl: classDecl, shared: shared, body: &body)
        emitNullInitializerFieldSentinels(classDecl: classDecl, shared: shared, body: &body)
        let constructorDeclSite = sema.symbols.symbol(ctorSymbol)?.declSite
        let isSecondary = classDecl.secondaryConstructors.contains { constructor in
            constructor.range == constructorDeclSite
        }
        if !isSecondary {
            emitSuperConstructorDelegation(
                classDecl: classDecl, ctorSymbol: ctorSymbol, ownerSymbol: ownerSymbol,
                shared: shared, body: &body
            )
            emitPrimaryConstructorPropertyInitializers(
                classDecl: classDecl,
                ownerSymbol: ownerSymbol,
                shared: shared,
                body: &body
            )
            // Enum entries are ordinal-backed and initialized inside
            // $enumEnsureInit$; their delegate handles are stored there by
            // emitEnumEntryConstructorInitialization instead.
            if sema.symbols.symbol(ownerSymbol)?.kind != .enumClass {
                emitClassDelegationInitializers(
                    ownerSymbol: ownerSymbol,
                    receiverID: ctx.activeImplicitReceiverExprID()!,
                    shared: shared, body: &body
                )
            }
            emitClassBodyInitializers(
                classDecl: classDecl, shared: shared, body: &body
            )
        }
        if isSecondary {
            emitSecondaryConstructorBody(
                classDecl: classDecl, ctorSymbol: ctorSymbol,
                ctorFQName: ctorFQName, ownerSymbol: ownerSymbol,
                shared: shared, body: &body
            )
        }
        if let receiver = ctx.activeImplicitReceiverExprID() {
            body.append(.returnValue(receiver))
        } else {
            body.append(.returnUnit)
        }
        body.append(.endBlock)
        return body
    }

    /// Kotlin runs the superclass constructor before the subclass's own
    /// initializers, so the superclass's property initializers and `init`
    /// blocks — which write into the same object at the layout offsets the
    /// subclass inherits — must execute here. Without this call a subclass
    /// instance keeps the zeroed defaults for every inherited property
    /// (BUG-155).
    func emitSuperConstructorDelegation(
        classDecl: ClassDecl,
        ctorSymbol: SymbolID,
        ownerSymbol: SymbolID,
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) {
        let sema = shared.sema
        let arena = shared.arena
        // Enum entries use the runtime ordinal box initialized by enum entry
        // lowering. They do not call the source Enum(name, ordinal) constructor
        // through the ordinary object constructor ABI.
        guard sema.symbols.symbol(ownerSymbol)?.kind != .enumClass else {
            return
        }
        guard let receiverID = ctx.activeImplicitReceiverExprID(),
              let superclassSymbol = sema.symbols.directSupertypes(for: ownerSymbol).first(where: {
                  let kind = sema.symbols.symbol($0)?.kind
                  return kind == .class || kind == .enumClass
              }),
              let superclassInfo = sema.symbols.symbol(superclassSymbol)
        else {
            return
        }
        // KSP-933: ArrayList keeps the synthetic AbstractMutableList anchor
        // until KSP-929 supplies its bundled implementation. That bootstrap
        // constructor has no emitted body, so delegating to its bare `<init>`
        // would leave an unresolved linker symbol in the bundled stdlib.
        let syntheticAbstractMutableListFQName = [
            shared.interner.intern("kotlin"),
            shared.interner.intern("collections"),
            shared.interner.intern("AbstractMutableList"),
        ]
        if superclassInfo.flags.contains(.synthetic),
           superclassInfo.fqName == syntheticAbstractMutableListFQName
        {
            return
        }
        let superCtorSymbol = sema.bindings.constructorDelegationTarget(for: ctorSymbol)
            ?? sema.symbols
            .lookupAll(fqName: superclassInfo.fqName + [shared.interner.intern("<init>")])
            .first { $0 != ctorSymbol }
        guard let superCtorSymbol else {
            return
        }
        // Any's compiler-provided constructor is allocation-only. A kklib
        // import marks it source-backed, which would otherwise emit a call to
        // a bare `<init>` that nothing defines.
        if sema.symbols.symbol(superCtorSymbol)?.flags.contains(.synthetic) == true,
           sema.symbols.parentSymbol(for: superCtorSymbol) == sema.types.anyClassSymbol
        {
            return
        }

        let resolvedSuperclassFQName = superclassInfo.fqName.map(shared.interner.resolve)
        let isSourceBackedTimeSource =
            resolvedSuperclassFQName == ["kotlin", "time", "AbstractDoubleTimeSource"]
                || resolvedSuperclassFQName == ["kotlin", "time", "AbstractLongTimeSource"]
        let superArgs = classDecl.superTypeEntries.first { !$0.constructorArgs.isEmpty }?.constructorArgs ?? []
        if !isSourceBackedTimeSource,
           isRuntimeThrowableSuperConstructor(superCtorSymbol, sema: sema)
        {
            emitRuntimeThrowableSuperInitialization(
                superCtorSymbol: superCtorSymbol,
                superclassSymbol: superclassSymbol,
                receiver: receiverID,
                loweredArgs: lowerSuperConstructorArguments(
                    superArgs,
                    ctorSymbol: ctorSymbol,
                    ownerSymbol: ownerSymbol,
                    receiver: receiverID,
                    shared: shared,
                    body: &body
                ),
                spreadFlags: superArgs.map(\.isSpread),
                argumentLabels: superArgs.map(\.label),
                callBinding: sema.bindings.constructorDelegationCallBinding(for: ctorSymbol),
                shared: shared,
                body: &body
            )
            return
        }
        // Synthetic nominal shells may expose a constructor for Sema
        // compatibility without providing a linkable implementation. Imported
        // library declarations also carry the synthetic bit, but their
        // artifact object contains the real constructor body and must remain
        // callable from a user-defined subclass. The time-source shells are
        // source-backed in the bundled stdlib and their constructor initializes
        // the inherited `unit` field, so retain that delegation even while the
        // compatibility flag is present.
        guard !(sema.symbols.symbol(superCtorSymbol)?.flags.contains(.synthetic) ?? false)
            || sema.symbols.isSourceBackedSymbol(superCtorSymbol)
            || isSourceBackedTimeSource
        else {
            return
        }

        // HashSet is source-backed while AbstractMutableSet remains a synthetic
        // surface. Its synthetic protected constructor has no emitted body, so
        // a generated parent call would leave an unresolved `<init>` symbol.
        let hashSetFQName = [
            shared.interner.intern("kotlin"),
            shared.interner.intern("collections"),
            shared.interner.intern("HashSet"),
        ]
        if sema.symbols.symbol(ownerSymbol)?.fqName == hashSetFQName,
           sema.symbols.symbol(superCtorSymbol)?.flags.contains(.synthetic) == true
        {
            return
        }

        let loweredSuperArgs = lowerSuperConstructorArguments(
            superArgs,
            ctorSymbol: ctorSymbol,
            ownerSymbol: ownerSymbol,
            receiver: receiverID,
            shared: shared,
            body: &body
        )
        let resultID = arena.appendTemporary(type: sema.types.unitType)
        emitDelegatedConstructorCall(
            target: superCtorSymbol,
            receiver: receiverID,
            loweredArgs: loweredSuperArgs,
            spreadFlags: superArgs.map(\.isSpread),
            argumentLabels: superArgs.map(\.label),
            callBinding: sema.bindings.constructorDelegationCallBinding(for: ctorSymbol),
            sourceArgExprs: superArgs.map(\.expr),
            result: resultID,
            shared: shared,
            body: &body
        )
    }

    func lowerSuperConstructorArguments(
        _ arguments: [CallArgument],
        ctorSymbol: SymbolID,
        ownerSymbol: SymbolID,
        receiver: KIRExprID,
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) -> [KIRExprID] {
        guard !arguments.isEmpty else { return [] }

        let previousOverride = ctx.superConstructorArgumentReceiverOverride
        defer { ctx.superConstructorArgumentReceiverOverride = previousOverride }
        if shared.sema.symbols.symbol(ownerSymbol)?.flags.contains(.innerClass) == true,
           ctx.currentFunctionSymbol == ctorSymbol,
           let receiverSymbol = ctx.activeImplicitReceiverSymbol()
        {
            ctx.superConstructorArgumentReceiverOverride = .init(
                constructorSymbol: ctorSymbol,
                receiverSymbol: receiverSymbol,
                receiverExprID: receiver
            )
        }
        return arguments.map { lowerExpr($0.expr, shared: shared, emit: &body) }
    }

    /// True when a `super(...)` target is a runtime-backed Throwable
    /// constructor (`@KsSymbolName("__kk_exception_new_message")` etc.). Such
    /// a constructor returns its own native box instead of initializing the
    /// compiler-allocated subclass object, so it cannot be called as `<init>`.
    func isRuntimeThrowableSuperConstructor(_ superCtorSymbol: SymbolID, sema: SemaModule) -> Bool {
        if callLowerer.isRuntimeFactoryConstructor(superCtorSymbol, sema: sema) {
            return true
        }
        return sema.symbols.externalLinkName(for: superCtorSymbol) == "__kk_throwable_new"
            && sema.symbols.functionSignature(for: superCtorSymbol)?.parameterTypes.isEmpty == true
    }

    /// Initializes a Kotlin Throwable subclass whose `super(...)` target is a
    /// runtime factory (see `isRuntimeThrowableSuperConstructor`). The factory
    /// is called with the normalized arguments (named arguments reordered like
    /// any call site), and the message / cause of the box it returns are copied
    /// onto `receiver`. Copying instead of mapping parameters by hand keeps the
    /// factory's own semantics, e.g. `Exception(cause)` deriving its message
    /// from `cause.toString()`.
    func emitRuntimeThrowableSuperInitialization(
        superCtorSymbol: SymbolID,
        superclassSymbol: SymbolID,
        receiver: KIRExprID,
        loweredArgs: [KIRExprID],
        spreadFlags: [Bool],
        argumentLabels: [InternedString?] = [],
        callBinding: CallBinding?,
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        let throwableFQName = [interner.intern("kotlin"), interner.intern("Throwable")]
        guard let throwableSymbol = sema.symbols.lookup(fqName: throwableFQName) else {
            return
        }
        let superclassType = sema.types.make(.classType(ClassType(
            classSymbol: superclassSymbol, args: [], nullability: .nonNull
        )))
        let throwableType = sema.types.make(.classType(ClassType(
            classSymbol: throwableSymbol, args: [], nullability: .nonNull
        )))
        guard sema.types.isSubtype(superclassType, throwableType) else {
            return
        }
        let nullableStringType = sema.types.makeNullable(sema.types.stringType)
        let nullableThrowableType = sema.types.makeNullable(throwableType)

        func helperSymbol(named name: String) -> SymbolID? {
            sema.symbols.lookupAll(
                fqName: throwableFQName.dropLast() + [interner.intern(name)]
            ).first(where: { sema.symbols.symbol($0)?.kind == .function })
        }

        func emitHelperCall(_ name: String, arguments: [KIRExprID], resultType: TypeID) -> KIRExprID? {
            guard let symbol = helperSymbol(named: name) else {
                return nil
            }
            let resultID = arena.appendTemporary(type: resultType)
            body.append(.call(
                symbol: symbol,
                callee: interner.intern(sema.symbols.externalLinkName(for: symbol) ?? name),
                arguments: arguments,
                result: resultID,
                canThrow: false,
                isSuperCall: false
            ))
            return resultID
        }

        guard callLowerer.isRuntimeFactoryConstructor(superCtorSymbol, sema: sema) else {
            // `Throwable()`'s bare allocator: only the message slot needs a
            // defined (null) value.
            let messageID = arena.appendExpr(.null, type: nullableStringType)
            body.append(.constValue(result: messageID, value: .null))
            _ = emitHelperCall(
                "__kkThrowableSetMessage", arguments: [receiver, messageID], resultType: sema.types.unitType
            )
            return
        }

        var factoryArgs = loweredArgs
        if let callBinding, callBinding.chosenCallee == superCtorSymbol {
            factoryArgs = callSupportLowerer.normalizedCallArguments(
                providedArguments: loweredArgs,
                callBinding: callBinding,
                chosenCallee: superCtorSymbol,
                spreadFlags: spreadFlags,
                argumentLabels: argumentLabels,
                shared: shared,
                emit: &body
            ).arguments
        }
        let factoryResult = arena.appendTemporary(type: throwableType)
        body.append(.call(
            symbol: superCtorSymbol,
            callee: interner.intern(sema.symbols.externalLinkName(for: superCtorSymbol) ?? "<init>"),
            arguments: factoryArgs,
            result: factoryResult,
            canThrow: sema.symbols.functionSignature(for: superCtorSymbol)?.canThrow ?? false
        ))
        if let messageID = emitHelperCall(
            "__kkThrowableMessage", arguments: [factoryResult], resultType: nullableStringType
        ) {
            _ = emitHelperCall(
                "__kkThrowableSetMessage", arguments: [receiver, messageID], resultType: sema.types.unitType
            )
        }
        if let causeID = emitHelperCall(
            "__kkThrowableCause", arguments: [factoryResult], resultType: nullableThrowableType
        ) {
            _ = emitHelperCall(
                "__kkThrowableSetCause", arguments: [receiver, causeID], resultType: sema.types.unitType
            )
        }
    }

    private func emitPrimaryConstructorPropertyInitializers(
        classDecl: ClassDecl,
        ownerSymbol: SymbolID,
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) {
        let sema = shared.sema
        let arena = shared.arena

        // Only primary-constructor properties represent constructor storage.
        // A member extension may reuse their name but is not initialized here.
        let propertySymbolsByName: [InternedString: SymbolID] = Dictionary(
            classDecl.memberProperties.compactMap { declID -> (InternedString, SymbolID)? in
                guard let symbol = sema.bindings.declSymbols[declID],
                      let decl = shared.ast.arena.decl(declID),
                      case let .propertyDecl(propertyDecl) = decl,
                      propertyDecl.isSynthesizedPrimaryConstructorProperty
                else {
                    return nil
                }
                return (propertyDecl.name, symbol)
            },
            uniquingKeysWith: { first, _ in first }
        )

        guard let receiverID = ctx.activeImplicitReceiverExprID(),
              let ctorSignature = sema.symbols.functionSignature(for: ctx.activeFunctionSymbol() ?? .invalid)
        else {
            return
        }

        let isDataClass = sema.symbols.symbol(ownerSymbol)?.flags.contains(.dataType) == true

        for (index, param) in classDecl.primaryConstructorParams.enumerated() {
            guard param.isProperty,
                  index < ctorSignature.valueParameterSymbols.count,
                  let propertySymbol = propertySymbolsByName[param.name]
            else {
                continue
            }
            let targetSymbol = sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
            guard let fieldOffset = sema.symbols.nominalLayout(
                for: sema.symbols.parentSymbol(for: propertySymbol) ?? .invalid
            )?.fieldOffsets[targetSymbol] else {
                continue
            }

            let parameterSymbol = ctorSignature.valueParameterSymbols[index]
            let propertyType = sema.symbols.propertyType(for: propertySymbol) ?? sema.types.anyType
            let storageType = constructorParameterStorageType(
                at: index, signature: ctorSignature, sema: sema, interner: shared.interner
            )
            let parameterExpr = arena.appendExpr(.symbolRef(parameterSymbol), type: storageType)
            body.append(.constValue(result: parameterExpr, value: .symbolRef(parameterSymbol)))
            // Source-backed constructor storage already has the public Array
            // representation. Storing this handle preserves callBy/default identity.
            let propertyValue = parameterExpr

            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
            body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))

            var arguments = [receiverID, offsetExpr, propertyValue]
            let callee: InternedString
            let resultType: TypeID
            if isDataClass {
                let tagValue = computeAnyFallbackTag(for: propertyType, sema: sema)
                let tagExpr = arena.appendExpr(.intLiteral(tagValue), type: sema.types.intType)
                body.append(.constValue(result: tagExpr, value: .intLiteral(tagValue)))
                arguments.append(tagExpr)
                callee = shared.interner.intern("kk_array_set_typed")
                resultType = sema.types.intType
            } else {
                callee = shared.interner.intern("kk_array_set")
                resultType = sema.types.anyType
            }

            let unusedResult = arena.appendTemporary(type: resultType)
            body.append(.call(callee: callee, arguments: arguments, result: unusedResult, canThrow: false, isSuperCall: false))
        }
    }

    private func finalizeConstructorDecl(
        ctorSymbol: SymbolID,
        classDecl: ClassDecl,
        params: [KIRParameter],
        returnType: TypeID,
        body: KIRLoweringEmitContext,
        signature: FunctionSignature,
        shared: KIRLoweringSharedContext
    ) -> [KIRDeclID] {
        let arena = shared.arena
        var declIDs: [KIRDeclID] = []
        let ctorKirID = arena.appendDecl(
            .function(KIRFunction(
                symbol: ctorSymbol, name: classDecl.name,
                params: params, returnType: returnType,
                body: body, isSuspend: false, isInline: false
            ))
        )
        declIDs.append(ctorKirID)
        if let defaults = ctx.defaultArguments(for: ctorSymbol) {
            let stubID = callSupportLowerer.generateDefaultStubFunction(
                originalSymbol: ctorSymbol, originalName: classDecl.name,
                signature: signature, defaultExpressions: defaults,
                shared: shared
            )
            declIDs.append(stubID)
        }
        declIDs.append(contentsOf: ctx.drainGeneratedCallableDecls())
        return declIDs
    }

    func emitClassDelegationInitializers(
        ownerSymbol: SymbolID,
        receiverID: KIRExprID,
        superTypeEntries: [SuperTypeEntry]? = nil,
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) {
        let sema = shared.sema
        let arena = shared.arena
        let delegatedInterfaces = sema.symbols.delegatedInterfaces(forClass: ownerSymbol)
        let orderedInterfaces = superTypeEntries.map { entries in
            entries.compactMap { entry in
                entry.delegateExpression.flatMap { expr in
                    delegatedInterfaces.first {
                        sema.symbols.classDelegationExpr(forClass: ownerSymbol, interface: $0) == expr
                    }
                }
            }
        } ?? delegatedInterfaces
        for interfaceSymbol in orderedInterfaces {
            guard let delegateExpr = sema.symbols.classDelegationExpr(forClass: ownerSymbol, interface: interfaceSymbol),
                  let fieldSymbol = sema.symbols.classDelegationField(forClass: ownerSymbol, interface: interfaceSymbol)
            else {
                continue
            }
            let delegateValue = lowerExpr(delegateExpr, shared: shared, emit: &body)

            // Enum values are ordinal-backed: the delegate handle lives in a
            // per-entry global slot populated by $enumEnsureInit$, matching
            // how ordinary enum stored properties are kept.
            if let slotSymbol = ctx.enumEntryStorageSlots[fieldSymbol] {
                let slotType = sema.symbols.propertyType(for: fieldSymbol) ?? sema.types.anyType
                let slotRef = arena.appendExpr(.symbolRef(slotSymbol), type: slotType)
                body.append(.constValue(result: slotRef, value: .symbolRef(slotSymbol)))
                body.append(.copy(from: delegateValue, to: slotRef))
                continue
            }

            let storedDelegateValue: KIRExprID
            let enumEntryOwner = sema.bindings.identifierSymbols[delegateExpr].flatMap { symbol -> SymbolID? in
                guard sema.symbols.symbol(symbol)?.kind == .field,
                      let owner = sema.symbols.parentSymbol(for: symbol),
                      sema.symbols.symbol(owner)?.kind == .enumClass
                else {
                    return nil
                }
                return owner
            }
            let enumEntryType = enumEntryOwner.map {
                sema.types.make(.classType(ClassType(
                    classSymbol: $0,
                    args: [],
                    nullability: .nonNull
                )))
            }
            let delegateSourceType = enumEntryType
                ?? sema.bindings.exprTypes[delegateExpr]
                ?? arena.exprType(delegateValue)
            if let delegateSourceType,
               case let .classType(enumType) = sema.types.kind(of: delegateSourceType),
               sema.symbols.symbol(enumType.classSymbol)?.kind == .enumClass
            {
                // Enum values are raw ordinals until they cross a reference
                // boundary. A class-delegation field is an interface handle,
                // so store the boxed enum entry rather than ordinal zero as
                // a null pointer.
                storedDelegateValue = boxValueForAnySlot(
                    delegateValue,
                    sourceType: delegateSourceType,
                    types: sema.types,
                    symbols: sema.symbols,
                    interner: shared.interner,
                    arena: arena,
                    resultType: sema.symbols.propertyType(for: fieldSymbol),
                    requireNonNull: true,
                    sema: sema,
                    cache: ctx.nominalDispatchCache,
                    into: &body.instructions
                )
            } else {
                // `kk_array_set` stores the raw word: a delegate expression
                // whose static type has an unboxed runtime representation — a
                // value class — would land its bare payload in the
                // interface-typed field and read back as a bogus (often null)
                // handle. Box it for the object slot the same way
                // Any/reference boundaries do (KUU-3672).
                storedDelegateValue = boxValueForAnySlot(
                    delegateValue,
                    sourceType: arena.exprType(delegateValue) ?? sema.types.anyType,
                    types: sema.types,
                    symbols: sema.symbols,
                    interner: shared.interner,
                    arena: arena,
                    resultType: sema.symbols.propertyType(for: fieldSymbol) ?? sema.types.anyType,
                    sema: sema,
                    into: &body.instructions
                )
            }

            guard let fieldOffset = shared.sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[fieldSymbol] else {
                continue
            }
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: shared.sema.types.intType)
            body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))

            let unusedResult = arena.appendTemporary(type: shared.sema.types.anyType)
            body.append(.call(
                callee: shared.interner.intern("kk_array_set"),
                arguments: [receiverID, offsetExpr, storedDelegateValue],
                result: unusedResult,
                canThrow: true,
                isSuperCall: false
            ))
        }
    }

    /// Emits property initializers and `init { }` blocks in the order they
    /// appear in the class body, matching Kotlin's guaranteed top-to-bottom
    /// initialization semantics.
    func emitClassBodyInitializers(
        classDecl: ClassDecl,
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) {
        for member in classDecl.classBodyInitOrder {
            switch member {
            case let .property(index):
                guard index < classDecl.memberProperties.count else { continue }
                let propDeclID = classDecl.memberProperties[index]
                emitPropertyInitializer(
                    propDeclID: propDeclID,
                    shared: shared,
                    body: &body
                )
            case let .initBlock(index):
                guard index < classDecl.initBlocks.count else { continue }
                emitInitBlock(classDecl.initBlocks[index], shared: shared, body: &body)
            }
        }
    }

    func emitInitBlock(
        _ initBlock: FunctionBody,
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) {
        switch initBlock {
        case let .block(exprIDs, _):
            for exprID in exprIDs {
                _ = lowerExpr(exprID, shared: shared, emit: &body)
            }
        case let .expr(exprID, _):
            _ = lowerExpr(exprID, shared: shared, emit: &body)
        case .unit:
            break
        }
    }

    func emitPropertyInitializer(
        propDeclID: DeclID,
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) {
        let ast = shared.ast
        let sema = shared.sema
        let arena = shared.arena
        guard let propDecl = ast.arena.decl(propDeclID),
              case let .propertyDecl(prop) = propDecl,
              let propSymbol = sema.bindings.declSymbols[propDeclID]
        else {
            return
        }

        if prop.delegateExpression != nil {
            emitDelegatePropertyInitializer(
                propertyDecl: prop,
                propSymbol: propSymbol,
                sema: sema,
                arena: arena,
                shared: shared,
                body: &body
            )
            return
        }

        if let explicitField = prop.explicitBackingField {
            let targetSymbol = sema.symbols.backingFieldSymbol(for: propSymbol) ?? propSymbol
            let backingFieldType = sema.symbols.propertyType(for: targetSymbol) ?? sema.types.anyType
            if let initializer = explicitField.initializer,
               !isDefaultFieldInitializer(initializer, fieldType: backingFieldType, shared: shared)
            {
                let initValue = lowerPropertyInitializerValue(
                    initializer,
                    shared: shared, emit: &body
                )
                emitFieldStore(
                    propSymbol: propSymbol, targetSymbol: targetSymbol,
                    value: initValue, valueType: backingFieldType,
                    shared: shared, body: &body
                )
            }
            if let initExpr = prop.initializer {
                let propType = sema.symbols.propertyType(for: propSymbol) ?? sema.types.anyType
                if !isDefaultFieldInitializer(initExpr, fieldType: propType, shared: shared) {
                    let propInitValue = lowerPropertyInitializerValue(initExpr, shared: shared, emit: &body)
                    emitFieldStore(
                        propSymbol: propSymbol, targetSymbol: targetSymbol,
                        value: propInitValue, valueType: propType,
                        shared: shared, body: &body
                    )
                }
            }
            return
        }

        // A `lateinit` without an initializer emits nothing here: its null
        // sentinel is seeded at constructor entry (`emitLateinitFieldSentinels`).
        guard let initExpr = prop.initializer else { return }
        let targetSymbol = sema.symbols.backingFieldSymbol(for: propSymbol) ?? propSymbol
        let propType = sema.symbols.propertyType(for: propSymbol) ?? sema.types.anyType
        guard !isDefaultFieldInitializer(initExpr, fieldType: propType, shared: shared) else { return }
        let initValue = lowerPropertyInitializerValue(
            initExpr,
            shared: shared, emit: &body
        )
        emitFieldStore(
            propSymbol: propSymbol, targetSymbol: targetSymbol,
            value: initValue, valueType: propType,
            shared: shared, body: &body
        )
    }

    private func isDefaultFieldInitializer(
        _ exprID: ExprID,
        fieldType: TypeID,
        shared: KIRLoweringSharedContext
    ) -> Bool {
        let collector = ConstantCollector(
            resolvedConstant: { shared.sema.bindings.constExprValue(for: $0) },
            floatingPointComparisonSemantics: .ieee754
        )
        guard let value = collector.literalConstantExpr(
            exprID, ast: shared.ast, interner: shared.interner
        ) else {
            return false
        }
        return KIRDefaultFieldInitializer.isDefaultValue(
            value, for: fieldType, types: shared.sema.types
        )
    }

    private func lowerPropertyInitializerValue(
        _ exprID: ExprID,
        shared: KIRLoweringSharedContext,
        emit body: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let value = lowerExpr(exprID, shared: shared, emit: &body)
        guard let type = shared.sema.bindings.exprTypes[exprID],
              case let .functionType(functionType) = shared.sema.types.kind(of: shared.sema.types.makeNonNullable(type))
        else {
            return value
        }
        return callLowerer.materializeFunctionValueArgument(
            loweredArgID: value,
            argExprID: exprID,
            functionType: functionType,
            sema: shared.sema,
            arena: shared.arena,
            interner: shared.interner,
            instructions: &body.instructions
        )
    }

    /// Emitted at constructor entry, ahead of the superclass constructor call
    /// (see `KIRLoweringDriver+LateinitSentinel.swift`).
    private func emitLateinitFieldSentinels(
        classDecl: ClassDecl,
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) {
        let sema = shared.sema
        let arena = shared.arena
        for propSymbol in lateinitSentinelPropertySymbols(classDecl.memberProperties, shared: shared) {
            let targetSymbol = sema.symbols.backingFieldSymbol(for: propSymbol) ?? propSymbol
            let propType = sema.symbols.propertyType(for: propSymbol) ?? sema.types.anyType
            let nullExpr = arena.appendExpr(.null, type: propType)
            body.append(.constValue(result: nullExpr, value: .null))
            emitFieldStore(
                propSymbol: propSymbol, targetSymbol: targetSymbol,
                value: nullExpr, valueType: propType,
                shared: shared, body: &body
            )
        }
    }

    /// The corresponding initializer is elided later because this sentinel
    /// is already the default and must not overwrite a virtual superclass write.
    private func emitNullInitializerFieldSentinels(
        classDecl: ClassDecl,
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) {
        let sema = shared.sema
        let arena = shared.arena
        for propSymbol in nullInitializerPropertySymbols(classDecl.memberProperties, shared: shared) {
            let targetSymbol = sema.symbols.backingFieldSymbol(for: propSymbol) ?? propSymbol
            let fieldType = sema.symbols.propertyType(for: propSymbol) ?? sema.types.anyType
            guard KIRDefaultFieldInitializer.isDefaultValue(.null, for: fieldType, types: sema.types) else {
                continue
            }
            let nullExpr = arena.appendExpr(.null, type: fieldType)
            body.append(.constValue(result: nullExpr, value: .null))
            emitFieldStore(
                propSymbol: propSymbol, targetSymbol: targetSymbol,
                value: nullExpr, valueType: fieldType,
                shared: shared, body: &body
            )
        }
    }

    /// Class instance properties live inside the heap-allocated object, not in
    /// a module-global slot, so the write must go through `kk_array_set` at
    /// the property's computed field offset (the same mechanism reads use in
    /// `tryLowerStoredMemberPropertyRead`) — mirroring how primary-constructor
    /// property parameters are stored in `emitPrimaryConstructorPropertyInitializers`.
    /// Falls back to a direct symbol copy when no constructor receiver or
    /// layout is available (e.g. if ever invoked outside a constructor body).
    private func emitFieldStore(
        propSymbol: SymbolID,
        targetSymbol: SymbolID,
        value: KIRExprID,
        valueType: TypeID,
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) {
        let sema = shared.sema
        let arena = shared.arena
        // Enum entries are ordinal-backed: while the enum's lazy initializer
        // constructs an entry, its stored properties go to per-entry globals.
        if let slotSymbol = ctx.enumEntryStorageSlots[propSymbol] {
            let slotRef = arena.appendExpr(.symbolRef(slotSymbol), type: valueType)
            body.append(.constValue(result: slotRef, value: .symbolRef(slotSymbol)))
            body.append(.copy(from: value, to: slotRef))
            return
        }
        if let receiverID = ctx.activeImplicitReceiverExprID(),
           let ownerSymbol = sema.symbols.parentSymbol(for: propSymbol),
           let ownerInfo = sema.symbols.symbol(ownerSymbol),
           ownerInfo.kind == .class || ownerInfo.kind == .interface,
           let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[targetSymbol]
        {
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
            body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
            let storedValue = normalizedValueForNullablePrimitiveSlot(
                value,
                slotType: valueType,
                types: sema.types,
                arena: arena,
                into: &body
            )
            let unusedResult = arena.appendTemporary(type: sema.types.anyType)
            body.append(.call(
                callee: shared.interner.intern("kk_array_set"),
                arguments: [receiverID, offsetExpr, storedValue],
                result: unusedResult,
                canThrow: false,
                isSuperCall: false
            ))
        } else {
            let fieldRef = arena.appendExpr(.symbolRef(targetSymbol), type: valueType)
            body.append(.copy(from: value, to: fieldRef))
        }
    }


    func emitSecondaryConstructorBody(
        classDecl: ClassDecl,
        ctorSymbol: SymbolID,
        ctorFQName: [InternedString],
        ownerSymbol: SymbolID,
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) {
        let sema = shared.sema
        let arena = shared.arena
        for secondaryCtor in classDecl.secondaryConstructors {
            guard secondaryCtor.range == sema.symbols.symbol(ctorSymbol)?.declSite else {
                continue
            }
            if let delegation = secondaryCtor.delegationCall {
                emitDelegationCall(
                    delegation: delegation,
                    ctorFQName: ctorFQName,
                    ownerSymbol: ownerSymbol,
                    ctorSymbol: ctorSymbol,
                    sema: sema,
                    arena: arena,
                    shared: shared,
                    body: &body
                )
            } else if !classDecl.hasPrimaryConstructorSyntax {
                // No explicit delegation and no primary constructor to route
                // through: the superclass constructor is invoked implicitly.
                emitSuperConstructorDelegation(
                    classDecl: classDecl, ctorSymbol: ctorSymbol, ownerSymbol: ownerSymbol,
                    shared: shared, body: &body
                )
            }
            // A class without a primary constructor runs its property
            // initializers and `init` blocks inside every secondary
            // constructor that reaches the superclass directly; constructors
            // delegating to `this(...)` inherit them from the target instead.
            if secondaryCtor.delegationCall?.kind != .this {
                emitClassBodyInitializers(
                    classDecl: classDecl, shared: shared, body: &body
                )
            }
            switch secondaryCtor.body {
            case let .block(exprIDs, _):
                for exprID in exprIDs {
                    _ = lowerExpr(exprID, shared: shared, emit: &body)
                }
            case let .expr(exprID, _):
                _ = lowerExpr(exprID, shared: shared, emit: &body)
            case .unit:
                break
            }
            break
        }
    }

    /// Used by `ObjectLiteralLowerer` for object-expression members —
    /// there is no constructor to run inside, so it is invoked inline at the
    /// construction site with the object literal as the implicit receiver.
    func emitDelegatePropertyInitializer(
        propertyDecl: PropertyDecl,
        propSymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) {
        guard let delegateExpr = propertyDecl.delegateExpression else { return }
        let delegateStorageSym = sema.symbols.delegateStorageSymbol(for: propSymbol)
        let delegateKind = StdlibDelegateKind.detect(
            delegateExpr: delegateExpr, ast: shared.ast, interner: shared.interner
        )

        if delegateKind == .lazy, propertyDecl.delegateBody != nil {
            emitLazyDelegatePropertyInitializer(
                propertyDecl: propertyDecl, propSymbol: propSymbol,
                delegateStorageSym: delegateStorageSym, sema: sema, arena: arena,
                shared: shared, body: &body
            )
            return
        }

        let delegateValue = lowerExpr(delegateExpr, shared: shared, emit: &body)
        let hasProvideDelegate = sema.symbols.hasProvideDelegate(for: propSymbol)
        let valueToStore: KIRExprID = if hasProvideDelegate, let storageSym = delegateStorageSym {
            emitProvideDelegateCall(
                delegateValue: delegateValue, storageSym: storageSym,
                propSymbol: propSymbol, sema: sema, arena: arena,
                shared: shared, body: &body
            )
        } else {
            delegateValue
        }
        if let storageSym = delegateStorageSym {
            emitFieldStore(
                propSymbol: propSymbol, targetSymbol: storageSym,
                value: valueToStore, valueType: sema.types.anyType,
                shared: shared, body: &body
            )
        }
    }

    /// Initializes a member property using the compiler's special `lazy`
    /// implementation. Other stdlib delegates are lowered as ordinary source
    /// expressions, just like custom property delegates.
    private func emitLazyDelegatePropertyInitializer(
        propertyDecl: PropertyDecl,
        propSymbol: SymbolID,
        delegateStorageSym: SymbolID?,
        sema: SemaModule,
        arena: KIRArena,
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) {
        guard let storageSym = delegateStorageSym else { return }
        let interner = shared.interner
        let delegateType = sema.types.anyType
        let lambdaFnPtr = lowerDelegateLambdaBody(
            delegateBody: propertyDecl.delegateBody,
            delegateBodyParams: propertyDecl.delegateBodyParams, propertySymbol: propSymbol,
            paramCount: 0, shared: shared, emit: &body
        )
        let lockValue = LazyThreadSafetyModeLowering.lockExpression(
            from: propertyDecl.delegateExpression,
            ast: shared.ast,
            sema: shared.sema,
            interner: interner
        ).map { lowerExpr($0, shared: shared, emit: &body) }
        let modeExpr = lowerLazyModeExpr(
            delegateExpression: propertyDecl.delegateExpression,
            shared: shared, emit: &body
        )
        let lockArgument: KIRExprID
        if let lockValue {
            lockArgument = lockValue
        } else {
            lockArgument = arena.appendExpr(.null, type: sema.types.nullableAnyType)
            body.append(.constValue(result: lockArgument, value: .null))
        }
        let initialValueExpr = arena.appendExpr(.unit, type: sema.types.anyType)
        body.append(.constValue(result: initialValueExpr, value: .null))
        let initialComputedExpr = arena.appendExpr(.boolLiteral(false), type: sema.types.booleanType)
        body.append(.constValue(result: initialComputedExpr, value: .boolLiteral(false)))
        guard let ctorSymbol = stdlibDelegateSymbol(
            fqName: [interner.intern("kotlin"), interner.intern("LazyImpl"), interner.intern("<init>")],
            parameterCount: 5, sema: sema
        ), let ownerSymbol = sema.symbols.parentSymbol(for: ctorSymbol) else {
            preconditionFailure("KSP-491: missing kotlin.LazyImpl constructor")
        }
        let allocatedObj = allocateStdlibDelegateInstance(
            ownerSymbol: ownerSymbol, resultType: delegateType,
            sema: sema, arena: arena, interner: interner, emit: &body
        )
        let createResult = arena.appendTemporary(type: delegateType)
        body.append(.call(
            symbol: ctorSymbol, callee: interner.intern("<init>"),
            arguments: [allocatedObj, lambdaFnPtr, modeExpr, lockArgument, initialValueExpr, initialComputedExpr],
            result: createResult, canThrow: false
        ))

        emitFieldStore(
            propSymbol: propSymbol, targetSymbol: storageSym,
            value: createResult, valueType: delegateType,
            shared: shared, body: &body
        )
    }

    private func emitProvideDelegateCall(
        delegateValue: KIRExprID,
        storageSym: SymbolID,
        propSymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        guard let provideDelegateSymbol = sema.symbols.delegateProvideDelegateSymbol(
            for: propSymbol
        ) else {
            return delegateValue
        }
        let delegateType = sema.types.anyType
        emitFieldStore(
            propSymbol: propSymbol, targetSymbol: storageSym,
            value: delegateValue, valueType: delegateType,
            shared: shared, body: &body
        )
        let thisRefExprID: KIRExprID
        if let receiver = ctx.activeImplicitReceiverExprID() {
            thisRefExprID = receiver
        } else {
            let nullExpr = arena.appendExpr(.null, type: sema.types.nullableAnyType)
            body.append(.constValue(result: nullExpr, value: .null))
            thisRefExprID = nullExpr
        }
        let kPropertyExprID = emitKPropertyStubCreate(
            propertySymbol: propSymbol,
            sema: sema,
            arena: arena,
            interner: shared.interner,
            delegateValue: delegateValue,
            emit: &body
        )
        let provideDelegateName = shared.interner.intern("provideDelegate")
        // Keep the provideDelegate return type on the result register (see the
        // top-level twin in KIRLoweringDriver+ProvideDelegate.swift): a
        // primitive-returning overload must leave a raw scalar in the delegate
        // storage, not a boxed `Any` handle.
        let provideDelegateResult = arena.appendTemporary(
            type: sema.symbols.functionSignature(for: provideDelegateSymbol)?.returnType
                ?? sema.types.anyType
        )
        body.append(memberLowerer.dispatchedDelegateMemberCall(
            symbol: provideDelegateSymbol, callee: provideDelegateName,
            receiver: delegateValue, extraArguments: [thisRefExprID, kPropertyExprID],
            result: provideDelegateResult, sema: sema, interner: shared.interner
        ))
        return provideDelegateResult
    }

    func synthesizeConstructorReflectionInitializer(
        classDecl: ClassDecl,
        ownerSymbol: SymbolID,
        shared: KIRLoweringSharedContext
    ) -> [KIRDeclID] {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        guard let ownerInfo = sema.symbols.symbol(ownerSymbol) else {
            return []
        }

        let ctorFQName = ownerInfo.fqName + [interner.intern("<init>")]
        // Paired expect/actual declarations share an FQName, so this lookup can
        // also return the paired declaration's constructors. Keep only
        // owner-owned constructors — the same guard `lowerConstructor` uses —
        // because the other side's constructor is never lowered here: for a
        // paired enum the expect declaration is skipped entirely, so its
        // constructor has no internal function and no external link name, and
        // the generated `__kconstructor_callable` thunk would emit a bare
        // `_<init>` reference that cannot link (KUU-2672).
        let ctorSymbols = sema.symbols.lookupAll(fqName: ctorFQName).filter {
            sema.symbols.parentSymbol(for: $0) == ownerSymbol
        }
        guard !ctorSymbols.isEmpty else {
            return []
        }

        let initializerSymbol = ctx.allocateSyntheticGeneratedSymbol()
        let initializerName = interner.intern("__ctor_reflect_init_\(ownerSymbol.rawValue)")
        let intType = sema.types.intType

        var body: KIRLoweringEmitContext = [.beginBlock]

        let typeToken = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: ownerSymbol,
            sema: sema,
            interner: interner
        )
        let encodedToken = RuntimeTypeCheckToken.encode(
            base: RuntimeTypeCheckToken.nominalBase,
            nullable: false,
            payload: typeToken
        )
        let typeTokenExpr = arena.appendExpr(.intLiteral(encodedToken), type: intType)
        body.append(.constValue(result: typeTokenExpr, value: .intLiteral(encodedToken)))

        let simpleNameInterned = interner.intern(interner.resolve(classDecl.name))
        let simpleNameExpr = arena.appendExpr(.stringLiteral(simpleNameInterned), type: intType)
        body.append(.constValue(result: simpleNameExpr, value: .stringLiteral(simpleNameInterned)))

        let kclassExpr = arena.appendTemporary(type: sema.types.makeKClassType(argument: sema.types.anyType)
        )
        body.append(.call(
            callee: interner.intern("__kk_kclass_create"),
            arguments: [typeTokenExpr, simpleNameExpr],
            result: kclassExpr,
            canThrow: false
        ))

        let ctorNameInterned = interner.intern("<init>")
        let ctorNameExpr = arena.appendExpr(.stringLiteral(ctorNameInterned), type: intType)
        body.append(.constValue(result: ctorNameExpr, value: .stringLiteral(ctorNameInterned)))

        let returnTypeExpr = arena.appendExpr(.stringLiteral(simpleNameInterned), type: intType)
        body.append(.constValue(result: returnTypeExpr, value: .stringLiteral(simpleNameInterned)))

        let visibilityExpr = arena.appendExpr(.intLiteral(0), type: intType)
        body.append(.constValue(result: visibilityExpr, value: .intLiteral(0)))

        for ctorSymbol in ctorSymbols {
            guard let signature = sema.symbols.functionSignature(for: ctorSymbol) else {
                continue
            }
            let arityExpr = arena.appendExpr(.intLiteral(Int64(signature.parameterTypes.count)), type: intType)
            body.append(.constValue(result: arityExpr, value: .intLiteral(Int64(signature.parameterTypes.count))))

            let fnPtrExpr = arena.appendExpr(.symbolRef(ctorSymbol), type: intType)
            body.append(.constValue(result: fnPtrExpr, value: .symbolRef(ctorSymbol)))

            let isPrimary = sema.symbols.symbol(ctorSymbol)?.declSite == classDecl.range ? 1 : 0
            let isPrimaryExpr = arena.appendExpr(.intLiteral(Int64(isPrimary)), type: intType)
            body.append(.constValue(result: isPrimaryExpr, value: .intLiteral(Int64(isPrimary))))

            let constructorInfo = sema.symbols.symbol(ctorSymbol)
            let jvmVisibilityOrdinal: Int
            if constructorInfo?.flags.contains(.constructorVisibilityInherited) == true {
                jvmVisibilityOrdinal = 0
            } else {
                switch constructorInfo?.visibility ?? .public {
                case .public, .internal:
                    jvmVisibilityOrdinal = 0
                case .protected:
                    jvmVisibilityOrdinal = 1
                case .private:
                    jvmVisibilityOrdinal = 3
                }
            }
            let jvmVisibilityExpr = arena.appendExpr(.intLiteral(Int64(jvmVisibilityOrdinal)), type: intType)
            body.append(.constValue(result: jvmVisibilityExpr, value: .intLiteral(Int64(jvmVisibilityOrdinal))))

            let registrationResult = arena.appendTemporary(type: intType)
            body.append(.call(
                callee: interner.intern("__kk_kconstructor_create"),
                arguments: [
                    ctorNameExpr, arityExpr, returnTypeExpr, fnPtrExpr, isPrimaryExpr,
                    visibilityExpr, kclassExpr,
                ],
                result: registrationResult,
                canThrow: false
            ))
            body.append(.call(
                callee: interner.intern("__kk_kconstructor_set_jvm_visibility"),
                arguments: [registrationResult, jvmVisibilityExpr],
                result: nil,
                canThrow: false
            ))

            let reflectedParameterTypes = (ownerInfo.kind == .enumClass
                ? [sema.types.stringType, sema.types.intType]
                : []) + signature.parameterTypes
            for (index, parameterType) in reflectedParameterTypes.enumerated() {
                let parameterIndexExpr = arena.appendExpr(.intLiteral(Int64(index)), type: intType)
                body.append(.constValue(
                    result: parameterIndexExpr,
                    value: .intLiteral(Int64(index))
                ))
                let parameterTypeToken = RuntimeTypeCheckToken.encode(
                    type: parameterType,
                    sema: sema,
                    interner: interner
                )
                let parameterTypeTokenExpr = arena.appendExpr(.intLiteral(parameterTypeToken), type: intType)
                body.append(.constValue(
                    result: parameterTypeTokenExpr,
                    value: .intLiteral(parameterTypeToken)
                ))
                let parameterTypeResult = arena.appendTemporary(type: intType)
                body.append(.call(
                    callee: interner.intern("__kk_kconstructor_set_parameter_type"),
                    arguments: [registrationResult, parameterIndexExpr, parameterTypeTokenExpr],
                    result: parameterTypeResult,
                    canThrow: false
                ))
            }

            let knownNames = KnownCompilerNames(interner: interner)
            let isAtomicFactory = sema.symbols.parentSymbol(for: ctorSymbol)
                .flatMap { sema.symbols.symbol($0) }
                .map(knownNames.isAtomicScalarFactorySymbol) ?? false
            let canGenerateInvocation = sema.symbols.externalLinkName(for: ctorSymbol) == nil
                && !isAtomicFactory
                && !callLowerer.isRuntimeFactoryConstructor(ctorSymbol, sema: sema)
            let callableSymbol: SymbolID
            let callableName: InternedString
            if canGenerateInvocation {
                // Reuse normal constructor lowering so the bridge allocates the
                // instance and enters its body with the reflected arguments.
                callableSymbol = ctx.allocateSyntheticGeneratedSymbol()
                callableName = interner.intern("__kconstructor_callable_\(ctorSymbol.rawValue)")
                let callableParams = signature.parameterTypes.enumerated().map { index, _ in
                    let paramName = interner.intern("arg\(index)")
                    let paramSymbol = sema.symbols.define(
                        kind: .valueParameter,
                        name: paramName,
                        fqName: [callableName, paramName],
                        declSite: nil,
                        visibility: .private,
                        flags: [.synthetic]
                    )
                    return KIRParameter(
                        symbol: paramSymbol,
                        type: constructorParameterStorageType(
                            at: index, signature: signature, sema: sema, interner: interner
                        )
                    )
                }
                let callableBody: [KIRInstruction] = ctx.withNewScope {
                    ctx.resetScopeForFunction()
                    ctx.setCurrentFunctionSymbol(callableSymbol)
                    var instructions: KIRLoweringEmitContext = [.beginBlock]
                    let loweredArguments = callableParams.map { param -> KIRExprID in
                        let argument = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
                        instructions.append(.constValue(result: argument, value: .symbolRef(param.symbol)))
                        return argument
                    }
                    let constructedValue = callLowerer.lowerResolvedCallBody(
                        .invalid,
                        args: [],
                        loweredArgIDs: loweredArguments,
                        chosen: ctorSymbol,
                        callBinding: nil,
                        callableValueCallBinding: nil,
                        loweredCallable: nil,
                        loweredCalleeExprID: nil,
                        sourceCalleeName: ctorNameInterned,
                        boundType: signature.returnType,
                        knownNames: knownNames,
                        ast: shared.ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        propertyConstantInitializers: [:],
                        instructions: &instructions.instructions
                    )
                    instructions.append(.returnValue(constructedValue))
                    instructions.append(.endBlock)
                    return instructions.instructions
                }
                ctx.appendGeneratedCallableDecl(arena.appendDecl(.function(KIRFunction(
                    symbol: callableSymbol,
                    name: callableName,
                    params: callableParams,
                    returnType: signature.returnType,
                    body: callableBody,
                    isSuspend: false,
                    isInline: false
                ))))
            } else {
                callableSymbol = ctorSymbol
                callableName = ctorNameInterned
            }
            lambdaLowerer.registerCallableReflection(
                value: registrationResult,
                callableSymbol: callableSymbol,
                callableName: callableName,
                targetSymbol: ctorSymbol,
                parameterTypes: signature.parameterTypes,
                returnType: signature.returnType,
                captures: [],
                receiverCount: 0,
                packedConstructorVarargs: canGenerateInvocation,
                includeInvocation: canGenerateInvocation,
                ast: shared.ast,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &body.instructions
            )
        }

        emitMemberReflectionRegistration(
            ownerSymbol: ownerSymbol,
            kclassExpr: kclassExpr,
            sema: sema,
            arena: arena,
            interner: interner,
            body: &body
        )

        appendValueClassAnyToStringRegistration(
            nominalSymbol: ownerSymbol,
            classID: typeToken,
            driver: self,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &body.instructions
        )

        body.append(.returnUnit)
        body.append(.endBlock)

        let declID = arena.appendDecl(
            .function(KIRFunction(
                symbol: initializerSymbol,
                name: initializerName,
                params: [],
                returnType: sema.types.unitType,
                body: body,
                isSuspend: false,
                isInline: false,
                sourceRange: classDecl.range
            ))
        )
        ctx.registerReflectionInitializer(symbol: initializerSymbol, name: initializerName)
        return [declID] + ctx.drainGeneratedCallableDecls()
    }


    /// Called from `synthesizeConstructorReflectionInitializer` so that
    /// `KClass.members` returns real handles rather than count-sized placeholders.
    func emitMemberReflectionRegistration(
        ownerSymbol: SymbolID,
        kclassExpr: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        body: inout KIRLoweringEmitContext
    ) {
        guard let ownerInfo = sema.symbols.symbol(ownerSymbol) else { return }
        let intType = sema.types.intType
        let childSymbols = sema.symbols.children(of: ownerSymbol)
        for childID in childSymbols {
            guard let childSym = sema.symbols.symbol(childID) else { continue }
            let isDataClassComponent = isSyntheticDataClassComponent(
                childSym,
                owner: ownerInfo,
                sema: sema,
                interner: interner
            )
            guard !childSym.flags.contains(.synthetic) || isDataClassComponent else { continue }
            switch childSym.kind {
            case .function:
                guard let signature = sema.symbols.functionSignature(for: childID) else { continue }
                let fnName = interner.resolve(childSym.name)
                let fnNameInterned = interner.intern(fnName)
                let fnNameExpr = arena.appendExpr(.stringLiteral(fnNameInterned), type: intType)
                body.append(.constValue(result: fnNameExpr, value: .stringLiteral(fnNameInterned)))
                let arity = Int64(signature.parameterTypes.count)
                let arityExpr = arena.appendExpr(.intLiteral(arity), type: intType)
                body.append(.constValue(result: arityExpr, value: .intLiteral(arity)))
                let returnTypeName = sema.types.displayName(
                    of: signature.returnType, symbols: sema.symbols, interner: interner
                )
                let retTypeInterned = interner.intern(returnTypeName)
                let retTypeExpr = arena.appendExpr(.stringLiteral(retTypeInterned), type: intType)
                body.append(.constValue(result: retTypeExpr, value: .stringLiteral(retTypeInterned)))
                // Packed modifier flags — bit0=suspend, bit1=inline,
                // bit2=operator, bit3=infix, bit4=external. Matches
                // `RuntimeKFunctionFlags` in the runtime.
                var functionFlags: Int64 = 0
                if signature.isSuspend { functionFlags |= 1 << 0 }
                if childSym.flags.contains(.inlineFunction) { functionFlags |= 1 << 1 }
                if childSym.flags.contains(.operatorFunction) { functionFlags |= 1 << 2 }
                if childSym.flags.contains(.infixFunction) { functionFlags |= 1 << 3 }
                if sema.symbols.externalLinkName(for: childID) != nil { functionFlags |= 1 << 4 }
                let isSuspendExpr = arena.appendExpr(.intLiteral(functionFlags), type: intType)
                body.append(.constValue(result: isSuspendExpr, value: .intLiteral(functionFlags)))
                let fnPtrExpr = arena.appendExpr(.symbolRef(childID), type: intType)
                body.append(.constValue(result: fnPtrExpr, value: .symbolRef(childID)))
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: intType)
                body.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                let kfunctionResult = arena.appendTemporary(type: intType)
                body.append(.call(
                    callee: interner.intern("__kk_kfunction_create"),
                    arguments: [fnNameExpr, arityExpr, retTypeExpr, isSuspendExpr, fnPtrExpr, zeroExpr],
                    result: kfunctionResult,
                    canThrow: false
                ))
                let fnRegisterResult = arena.appendTemporary(type: intType)
                body.append(.call(
                    callee: interner.intern("__kk_kclass_register_member"),
                    arguments: [kclassExpr, kfunctionResult],
                    result: fnRegisterResult,
                    canThrow: false
                ))
            case .property:
                let propName = interner.resolve(childSym.name)
                let propNameInterned = interner.intern(propName)
                let propNameExpr = arena.appendExpr(.stringLiteral(propNameInterned), type: intType)
                body.append(.constValue(result: propNameExpr, value: .stringLiteral(propNameInterned)))
                let propTypeName: String
                if let propTypeID = sema.symbols.propertyType(for: childID) {
                    propTypeName = sema.types.displayName(
                        of: propTypeID, symbols: sema.symbols, interner: interner
                    )
                } else {
                    propTypeName = "kotlin.Any"
                }
                let propTypeInterned = interner.intern(propTypeName)
                let propTypeExpr = arena.appendExpr(.stringLiteral(propTypeInterned), type: intType)
                body.append(.constValue(result: propTypeExpr, value: .stringLiteral(propTypeInterned)))
                let kpropResult = arena.appendTemporary(type: intType)
                body.append(.call(
                    callee: interner.intern("__kk_kproperty_stub_create"),
                    arguments: [propNameExpr, propTypeExpr],
                    result: kpropResult,
                    canThrow: false
                ))
                let propRegisterResult = arena.appendTemporary(type: intType)
                body.append(.call(
                    callee: interner.intern("__kk_kclass_register_member"),
                    arguments: [kclassExpr, kpropResult],
                    result: propRegisterResult,
                    canThrow: false
                ))
            default:
                break
            }
        }
    }

    private func isSyntheticDataClassComponent(
        _ symbol: SemanticSymbol,
        owner: SemanticSymbol,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard owner.flags.contains(.dataType),
              symbol.kind == .function,
              symbol.flags.contains(.synthetic),
              let signature = sema.symbols.functionSignature(for: symbol.id),
              signature.parameterTypes.isEmpty
        else {
            return false
        }

        let name = interner.resolve(symbol.name)
        guard name.hasPrefix("component"),
              let index = Int(name.dropFirst("component".count)),
              index > 0
        else {
            return false
        }
        return true
    }
}
