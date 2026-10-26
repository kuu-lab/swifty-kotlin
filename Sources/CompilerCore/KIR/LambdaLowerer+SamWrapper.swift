extension LambdaLowerer {
    func lowerSamWrapperValue(
        _ exprID: ExprID,
        interfaceType: ClassType,
        lambdaSymbol: SymbolID,
        lambdaName: InternedString,
        lambdaReturnType: TypeID,
        captureBindings: [(capturedSymbol: SymbolID, param: KIRParameter, valueExpr: KIRExprID, declaredType: TypeID)],
        samMethodReceiverType: TypeID? = nil,
        samMethodContextParameterTypes: [TypeID] = [],
        samMethodParamTypes: [TypeID],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        let interfaceSymbol = interfaceType.classSymbol
        guard let interfaceInfo = sema.symbols.symbol(interfaceSymbol),
              interfaceInfo.kind == .interface,
              interfaceInfo.flags.contains(.funInterface),
              let samMethod = samMethodSymbolAndSignature(for: interfaceSymbol, sema: sema)
        else {
            return nil
        }

        let wrapperName = interner.intern("kk_sam_wrapper_\(exprID.rawValue)")
        let wrapperFQName = [wrapperName]
        let wrapperSymbol = sema.symbols.define(
            kind: .class,
            name: wrapperName,
            fqName: wrapperFQName,
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        sema.symbols.setDirectSupertypes([interfaceSymbol], for: wrapperSymbol)
        sema.types.setNominalDirectSupertypes([interfaceSymbol], for: wrapperSymbol)
        sema.symbols.setSupertypeTypeArgs(interfaceType.args, for: wrapperSymbol, supertype: interfaceSymbol)
        sema.types.setNominalSupertypeTypeArgs(interfaceType.args, for: wrapperSymbol, supertype: interfaceSymbol)

        let wrapperType = sema.types.make(.classType(ClassType(
            classSymbol: wrapperSymbol,
            args: [],
            nullability: .nonNull
        )))

        var fieldOffsets: [SymbolID: Int] = [:]
        var nextFieldOffset = 2
        let captureFieldSymbols = captureBindings.enumerated().map { index, capture in
            let fieldName = interner.intern("$sam_capture_\(index)")
            let fieldSymbol = sema.symbols.define(
                kind: .field,
                name: fieldName,
                fqName: wrapperFQName + [fieldName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            sema.symbols.setParentSymbol(wrapperSymbol, for: fieldSymbol)
            sema.symbols.setPropertyType(capture.param.type, for: fieldSymbol)
            fieldOffsets[fieldSymbol] = nextFieldOffset
            nextFieldOffset += 1
            return fieldSymbol
        }

        let methodName = samMethod.info.name
        var methodFlags: SymbolFlags = [.synthetic]
        if samMethodReceiverType != nil {
            methodFlags.insert(.memberExtension)
        }
        let methodSymbol = sema.symbols.define(
            kind: .function,
            name: methodName,
            fqName: wrapperFQName + [methodName],
            declSite: nil,
            visibility: .public,
            flags: methodFlags
        )
        sema.symbols.setParentSymbol(wrapperSymbol, for: methodSymbol)

        let methodParamSymbols: [SymbolID] = samMethodParamTypes.enumerated().map { index, type in
            let paramName = interner.intern("$p\(index)")
            let paramSymbol = sema.symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: wrapperFQName + [methodName, paramName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            sema.symbols.setPropertyType(type, for: paramSymbol)
            return paramSymbol
        }
        let methodContextParamSymbols: [SymbolID] = samMethodContextParameterTypes.enumerated().map { index, type in
            let paramName = interner.intern("$context\(index)")
            let paramSymbol = sema.symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: wrapperFQName + [methodName, paramName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            sema.symbols.setPropertyType(type, for: paramSymbol)
            return paramSymbol
        }
        sema.symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: samMethodReceiverType ?? wrapperType,
                contextReceiverTypes: samMethodContextParameterTypes,
                contextParameterSymbols: methodContextParamSymbols,
                contextParameterTypes: samMethodContextParameterTypes,
                parameterTypes: samMethodParamTypes,
                returnType: lambdaReturnType,
                isSuspend: samMethod.signature.isSuspend,
                valueParameterSymbols: methodParamSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: methodParamSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: methodParamSymbols.count),
                typeParameterSymbols: []
            ),
            for: methodSymbol
        )
        // SAM wrappers implement the full interface surface, including
        // inherited defaults and property accessors. Keep a slot for every
        // interface in the transitive hierarchy so the shared itable
        // registration path can install those dispatch targets as well as the
        // synthesized SAM method.
        let samItableSlots = Dictionary(uniqueKeysWithValues: driver.ctx.nominalDispatchCache
            .transitiveInterfaceSupertypes(of: wrapperSymbol, sema: sema)
            .enumerated()
            .map { ($0.element, $0.offset) })
        sema.symbols.setNominalLayout(
            NominalLayout(
                objectHeaderWords: 2,
                instanceFieldCount: captureFieldSymbols.count,
                instanceSizeWords: max(2 + captureFieldSymbols.count, 1),
                fieldOffsets: fieldOffsets,
                vtableSlots: [methodSymbol: 0, samMethod.symbol: 0],
                itableSlots: samItableSlots,
                vtableSize: 1,
                superClass: nil
            ),
            for: wrapperSymbol
        )

        let nominalDeclID = arena.appendDecl(.nominalType(KIRNominalType(symbol: wrapperSymbol)))
        driver.ctx.appendGeneratedCallableDecl(nominalDeclID)

        let scopeSnapshot = driver.ctx.saveScope()
        driver.ctx.resetScopeForFunction()
        driver.ctx.beginCallableLoweringScope()
        driver.ctx.setCurrentFunctionSymbol(methodSymbol)

        let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: wrapperSymbol)
        let receiverExpr = arena.appendExpr(.symbolRef(receiverSymbol), type: wrapperType)
        driver.ctx.setImplicitReceiver(symbol: receiverSymbol, exprID: receiverExpr)

        let extensionReceiverSymbol = samMethodReceiverType.map { _ in
            driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: methodSymbol)
        }
        let extensionReceiverExpr: KIRExprID? = if let extensionReceiverSymbol, let samMethodReceiverType {
            arena.appendExpr(.symbolRef(extensionReceiverSymbol), type: samMethodReceiverType)
        } else {
            nil
        }
        let methodParams = [KIRParameter(symbol: receiverSymbol, type: wrapperType)]
            + (extensionReceiverSymbol.map { symbol in
                [KIRParameter(symbol: symbol, type: samMethodReceiverType ?? sema.types.anyType)]
            } ?? [])
            + zip(methodContextParamSymbols, samMethodContextParameterTypes).map { KIRParameter(symbol: $0.0, type: $0.1) }
            + zip(methodParamSymbols, samMethodParamTypes).map { KIRParameter(symbol: $0.0, type: $0.1) }
        var methodBody: [KIRInstruction] = [.beginBlock]
        methodBody.append(.constValue(result: receiverExpr, value: .symbolRef(receiverSymbol)))
        if let extensionReceiverSymbol, let extensionReceiverExpr {
            methodBody.append(.constValue(
                result: extensionReceiverExpr,
                value: .symbolRef(extensionReceiverSymbol)
            ))
            driver.ctx.setImplicitReceiver(symbol: extensionReceiverSymbol, exprID: extensionReceiverExpr)
        }
        let loweredContextParamExprs = zip(methodContextParamSymbols, samMethodContextParameterTypes).map { symbol, type in
            let expr = arena.appendExpr(.symbolRef(symbol), type: type)
            methodBody.append(.constValue(result: expr, value: .symbolRef(symbol)))
            return expr
        }

        var loadedCaptureExprs: [KIRExprID] = []
        for (index, fieldSymbol) in captureFieldSymbols.enumerated() {
            guard let fieldOffset = fieldOffsets[fieldSymbol] else {
                continue
            }
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
            methodBody.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
            let captureType = captureBindings[index].param.type
            let loadedExpr = arena.appendTemporary(type: captureType)
            methodBody.append(.call(
                callee: interner.intern("kk_array_get_inbounds"),
                arguments: [receiverExpr, offsetExpr],
                result: loadedExpr,
                canThrow: false
            ))
            loadedCaptureExprs.append(loadedExpr)
        }

        let loweredMethodParamExprs = zip(methodParamSymbols, samMethodParamTypes).map { symbol, type in
            let expr = arena.appendExpr(.symbolRef(symbol), type: type)
            methodBody.append(.constValue(result: expr, value: .symbolRef(symbol)))
            return expr
        }
        let samMethodInputExprs = loweredContextParamExprs
            + (extensionReceiverExpr.map { [$0] } ?? [])
            + loweredMethodParamExprs

        let callResult = arena.appendTemporary(type: lambdaReturnType)
        methodBody.append(.call(
            symbol: lambdaSymbol,
            callee: lambdaName,
            arguments: loadedCaptureExprs + samMethodInputExprs,
            result: callResult,
            canThrow: true
        ))
        if lambdaReturnType == sema.types.unitType {
            methodBody.append(.returnUnit)
        } else {
            methodBody.append(.returnValue(callResult))
        }
        methodBody.append(.endBlock)

        let methodDeclID = arena.appendDecl(.function(KIRFunction(
            symbol: methodSymbol,
            name: methodName,
            params: methodParams,
            returnType: lambdaReturnType,
            body: methodBody,
            isSuspend: samMethod.signature.isSuspend,
            isInline: false
        )))
        driver.ctx.appendGeneratedCallableDecl(methodDeclID)
        driver.ctx.restoreScope(scopeSnapshot)

        let slotCount = Int64(max(2 + captureFieldSymbols.count, 1))
        let slotCountExpr = arena.appendExpr(.intLiteral(slotCount), type: sema.types.intType)
        instructions.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))
        // KUU-3227: the runtime class tag comes from a shared per-interface
        // identity, not the per-site `wrapperSymbol` (which still owns layout
        // and vtable/itable dispatch). JVM emits exactly one SAM wrapper
        // class per fun interface, so `(SAM { ... } as Any)::class` must agree
        // across call sites; per-site class IDs interned distinct KClass
        // boxes and broke equality.
        let identitySymbol = samWrapperClassIdentitySymbol(
            for: interfaceSymbol,
            interfaceType: interfaceType,
            sema: sema,
            interner: interner
        )
        let classIDValue = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: identitySymbol,
            sema: sema,
            interner: interner
        )
        let classIDExpr = arena.appendExpr(.intLiteral(classIDValue), type: sema.types.intType)
        instructions.append(.constValue(result: classIDExpr, value: .intLiteral(classIDValue)))
        let wrapperValue = arena.appendTemporary(type: sema.types.make(.classType(ClassType(
                classSymbol: interfaceSymbol,
                args: interfaceType.args,
                nullability: .nonNull
            )))
        )
        instructions.append(.call(
            callee: interner.intern("kk_object_new"),
            arguments: [slotCountExpr, classIDExpr],
            result: wrapperValue,
            canThrow: false
        ))

        let childTypeExpr = arena.appendExpr(.intLiteral(classIDValue), type: sema.types.intType)
        instructions.append(.constValue(result: childTypeExpr, value: .intLiteral(classIDValue)))
        let interfaceTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: interfaceSymbol,
            sema: sema,
            interner: interner
        )
        let interfaceTypeExpr = arena.appendExpr(.intLiteral(interfaceTypeID), type: sema.types.intType)
        instructions.append(.constValue(result: interfaceTypeExpr, value: .intLiteral(interfaceTypeID)))
        let registerResult = arena.appendTemporary(type: sema.types.intType)
        instructions.append(.call(
            callee: interner.intern("kk_type_register_iface"),
            arguments: [childTypeExpr, interfaceTypeExpr],
            result: registerResult,
            canThrow: false
        ))
        // BUG-224: `wrapperSymbol` is a KIR-synthetic identity with no Sema
        // supertype entry of its own, so the edge above must stay explicit —
        // but `interfaceSymbol` (the SAM/fun interface being implemented) is
        // a real declared nominal, and if it itself extends another
        // interface that edge needs registering too, or a comparison through
        // that further ancestor would never reach this wrapper.
        appendTypeAncestryRegistrations(
            rootSymbol: interfaceSymbol,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )

        // Give the shared wrapper identity a stable KClass name so `::class`
        // on a SAM instance resolves simpleName/qualifiedName/supertypes
        // instead of reporting "Unknown". Registration is idempotent, so
        // emitting it per construction site is safe.
        let identityToken = RuntimeTypeCheckToken.encode(
            base: RuntimeTypeCheckToken.nominalBase,
            nullable: false,
            payload: classIDValue
        )
        let identityTokenExpr = arena.appendExpr(.intLiteral(identityToken), type: sema.types.intType)
        instructions.append(.constValue(result: identityTokenExpr, value: .intLiteral(identityToken)))
        driver.callLowerer.emitClassLiteralMetadataRegistration(
            classRefTargetType: sema.types.make(.classType(ClassType(
                classSymbol: identitySymbol,
                args: [],
                nullability: .nonNull
            ))),
            typeTokenExpr: identityTokenExpr,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )

        appendObjectItableMethodRegistrations(
            objectValue: wrapperValue,
            nominalSymbol: wrapperSymbol,
            driver: driver,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )

        // Expose the SAM wrapper as an invokable comparator value so stdlib
        // comparison lowering can call `compare` directly when needed.
        driver.ctx.registerCallableValue(
            wrapperValue,
            symbol: methodSymbol,
            callee: methodName,
            captureArguments: [wrapperValue],
            hasClosureParam: false
        )

        for (index, capture) in captureBindings.enumerated() {
            guard index < captureFieldSymbols.count,
                  let fieldOffset = fieldOffsets[captureFieldSymbols[index]]
            else {
                continue
            }
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
            instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
            let unusedResult = arena.appendTemporary(type: sema.types.anyType)
            instructions.append(.call(
                callee: interner.intern("kk_array_set"),
                arguments: [wrapperValue, offsetExpr, capture.valueExpr],
                result: unusedResult,
                canThrow: true
            ))
        }

        return wrapperValue
    }

    /// Returns the shared class-identity symbol for SAM-conversion wrappers
    /// of `interfaceSymbol`, creating it on first use (KUU-3227). The JVM
    /// emits one wrapper class per fun interface; every `SAM(...)` instance
    /// must therefore report the same `::class`. This symbol carries only the
    /// type identity used for the object header tag and KClass metadata —
    /// instance layout and dispatch stay on the per-site `wrapperSymbol`.
    private func samWrapperClassIdentitySymbol(
        for interfaceSymbol: SymbolID,
        interfaceType: ClassType,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID {
        if let cached = driver.ctx.samWrapperClassIdentitySymbols[interfaceSymbol] {
            return cached
        }
        let interfaceFQName = (sema.symbols.symbol(interfaceSymbol)?.fqName ?? [])
            .map { interner.resolve($0) }
            .joined(separator: ".")
        // The `$` keeps the name outside the source-declarable identifier
        // space, and the single-component fqName keeps the symbol on the
        // same "top-level synthetic" pruning path as the per-site
        // `kk_sam_wrapper_*` layouts (see MetadataSerializer+Encoder).
        let identityName = interner.intern("kk_sam_wrapper_class$\(interfaceFQName)")
        let identityFQName = [identityName]
        if let existing = sema.symbols.lookup(fqName: identityFQName),
           sema.symbols.symbol(existing)?.kind == .class {
            driver.ctx.samWrapperClassIdentitySymbols[interfaceSymbol] = existing
            return existing
        }
        let identitySymbol = sema.symbols.define(
            kind: .class,
            name: identityName,
            fqName: identityFQName,
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        // Report the fun interface as the wrapper's only supertype so
        // reflection (`supertypes`, `isInstance`) sees the real shape.
        sema.symbols.setDirectSupertypes([interfaceSymbol], for: identitySymbol)
        sema.types.setNominalDirectSupertypes([interfaceSymbol], for: identitySymbol)
        sema.symbols.setSupertypeTypeArgs(interfaceType.args, for: identitySymbol, supertype: interfaceSymbol)
        sema.types.setNominalSupertypeTypeArgs(interfaceType.args, for: identitySymbol, supertype: interfaceSymbol)
        driver.ctx.samWrapperClassIdentitySymbols[interfaceSymbol] = identitySymbol
        return identitySymbol
    }

    private func samMethodSymbolAndSignature(
        for interfaceSymbol: SymbolID,
        sema: SemaModule
    ) -> (symbol: SymbolID, info: SemanticSymbol, signature: FunctionSignature)? {
        guard let interfaceInfo = sema.symbols.symbol(interfaceSymbol),
              interfaceInfo.kind == .interface,
              interfaceInfo.flags.contains(.funInterface)
        else {
            return nil
        }
        guard let method = TypeCheckHelpers().effectiveSamAbstractMethod(for: interfaceSymbol, symbols: sema.symbols),
              let methodInfo = sema.symbols.symbol(method),
              let signature = sema.symbols.functionSignature(for: method)
        else {
            return nil
        }
        return (method, methodInfo, signature)
    }
}
