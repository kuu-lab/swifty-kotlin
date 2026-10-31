extension LambdaLowerer {
    private enum PropertyReferenceShape {
        case property0
        case mutableProperty0
        case property1
        case mutableProperty1
        case property2
        case mutableProperty2

        var arity: Int {
            switch self {
            case .property0, .mutableProperty0:
                0
            case .property1, .mutableProperty1:
                1
            case .property2, .mutableProperty2:
                2
            }
        }

        var isMutable: Bool {
            switch self {
            case .mutableProperty0, .mutableProperty1, .mutableProperty2:
                true
            case .property0, .property1, .property2:
                false
            }
        }
    }

    private struct PropertyReferenceAccessor {
        let propertySymbol: SymbolID
        let getterSymbol: SymbolID
        let setterSymbol: SymbolID?
        let propertyType: TypeID
        let ownerType: TypeID?
    }

    /// KProperty2 is intentionally left on the legacy path until its
    /// receiver/capture ABI is specified separately.
    func lowerPropertyReferenceWrapperValue(
        _ exprID: ExprID,
        targetSymbol: SymbolID?,
        memberName: InternedString,
        boundType: TypeID?,
        isUnbound: Bool,
        captureArguments: [KIRExprID],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard let boundType,
              case let .classType(referenceType) = sema.types.kind(of: boundType),
              let shape = propertyReferenceShape(
                  interfaceSymbol: referenceType.classSymbol,
                  sema: sema,
                  interner: interner
              ),
              let targetSymbol,
              let accessor = ensurePropertyReferenceAccessor(
                  targetSymbol: targetSymbol,
                  ast: ast,
                  sema: sema,
                  arena: arena,
                  interner: interner,
                  propertyConstantInitializers: propertyConstantInitializers
              )
        else {
            return nil
        }

        let interfaceSymbol = referenceType.classSymbol
        let interfaceSymbols = propertyReferenceInterfaceClosure(
            root: interfaceSymbol,
            sema: sema
        )
        guard !interfaceSymbols.isEmpty else { return nil }

        // KUU-3813 — JVM kotlin-reflect semantics: `Type::member` reflects the
        // member in the *erased* receiver class parameterized by its own type
        // parameters, so inherited generics are substituted through the
        // supertype instantiation (`A : H<A>` → T=A) while the written LHS
        // type arguments are ignored (`H<A>::parent` stays `T?`,
        // `B<Int>::parent` stays `U?`). A bound `expr::member` uses the
        // bound receiver's static type the same way.
        let receiverClassSymbol = propertyReferenceReceiverClassSymbol(
            shape: shape,
            isUnbound: isUnbound,
            referenceType: referenceType,
            captureArguments: captureArguments,
            sema: sema,
            arena: arena
        )
        let reflectedPropertyType = propertyReferenceReflectedType(
            propertySymbol: accessor.propertySymbol,
            propertyType: accessor.propertyType,
            receiverClassSymbol: receiverClassSymbol,
            sema: sema
        )

        let wrapperName = interner.intern("kk_kproperty_wrapper_\(exprID.rawValue)")
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
        sema.symbols.setSupertypeTypeArgs(referenceType.args, for: wrapperSymbol, supertype: interfaceSymbol)
        sema.types.setNominalSupertypeTypeArgs(referenceType.args, for: wrapperSymbol, supertype: interfaceSymbol)

        let wrapperType = sema.types.make(.classType(ClassType(
            classSymbol: wrapperSymbol,
            args: [],
            nullability: .nonNull
        )))

        var fieldOffsets: [SymbolID: Int] = [:]
        var captureFields: [SymbolID] = []
        for (index, capture) in captureArguments.enumerated() {
            let fieldName = interner.intern("$property_capture_\(index)")
            let fieldSymbol = sema.symbols.define(
                kind: .field,
                name: fieldName,
                fqName: wrapperFQName + [fieldName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            sema.symbols.setParentSymbol(wrapperSymbol, for: fieldSymbol)
            sema.symbols.setPropertyType(
                arena.exprType(capture) ?? sema.types.anyType,
                for: fieldSymbol
            )
            fieldOffsets[fieldSymbol] = index + 2
            captureFields.append(fieldSymbol)
        }

        // The `get`/`set`/`invoke` mirror the erased KPropertyN arity: every
        // leading interface type argument is a receiver parameter (dispatch
        // owner first for member extensions), followed by the value for `set`.
        let interfaceReceiverTypes: [TypeID] = referenceType.args.dropLast().compactMap { arg in
            switch arg {
            case let .invariant(type), let .out(type), let .in(type): type
            case .star: nil
            }
        }
        let methodReceiverTypes: [TypeID] = shape.arity == 0
            ? []
            : (interfaceReceiverTypes.isEmpty
                ? [accessor.ownerType ?? sema.types.anyType]
                : interfaceReceiverTypes)
        let getterMethodSymbol = definePropertyReferenceMethod(
            name: "get",
            wrapperSymbol: wrapperSymbol,
            wrapperFQName: wrapperFQName,
            parameterTypes: methodReceiverTypes,
            returnType: accessor.propertyType,
            sema: sema,
            interner: interner
        )
        let setterMethodSymbol: SymbolID? = shape.isMutable
            ? definePropertyReferenceMethod(
                name: "set",
                wrapperSymbol: wrapperSymbol,
                wrapperFQName: wrapperFQName,
                parameterTypes: methodReceiverTypes + [accessor.propertyType],
                returnType: sema.types.unitType,
                sema: sema,
                interner: interner
            )
            : nil
        // `canThrow` must be marked on the signature: when an itable bridge is
        // synthesized (e.g. KProperty1 whose erased `T` receiver differs from
        // the concrete owner type), the bridge consults `implSig.canThrow` to
        // decide whether to hand the impl a real outThrown slot. `false` would
        // pass nullThrownPointer and silently swallow the throw.
        let getDelegateMethodSymbol = definePropertyReferenceMethod(
            name: "getDelegate",
            wrapperSymbol: wrapperSymbol,
            wrapperFQName: wrapperFQName,
            parameterTypes: methodReceiverTypes,
            returnType: sema.types.nullableAnyType,
            canThrow: true,
            sema: sema,
            interner: interner
        )

        let itableSlots = Dictionary(
            uniqueKeysWithValues: interfaceSymbols.enumerated().map { index, symbol in
                (symbol, index)
            }
        )
        sema.symbols.setNominalLayout(
            NominalLayout(
                objectHeaderWords: 2,
                instanceFieldCount: captureFields.count,
                instanceSizeWords: max(2 + captureFields.count, 1),
                fieldOffsets: fieldOffsets,
                vtableSlots: [:],
                itableSlots: itableSlots,
                vtableSize: 0,
                itableSize: interfaceSymbols.count,
                superClass: nil
            ),
            for: wrapperSymbol
        )
        driver.ctx.appendGeneratedCallableDecl(
            arena.appendDecl(.nominalType(KIRNominalType(symbol: wrapperSymbol)))
        )

        emitPropertyReferenceGetter(
            methodSymbol: getterMethodSymbol,
            wrapperType: wrapperType,
            accessor: accessor,
            captureFields: captureFields,
            fieldOffsets: fieldOffsets,
            sema: sema,
            arena: arena,
            interner: interner
        )
        if let setterMethodSymbol {
            emitPropertyReferenceSetter(
                methodSymbol: setterMethodSymbol,
                wrapperType: wrapperType,
                accessor: accessor,
                captureFields: captureFields,
                fieldOffsets: fieldOffsets,
                sema: sema,
                arena: arena,
                interner: interner
            )
        }
        emitPropertyReferenceGetDelegate(
            methodSymbol: getDelegateMethodSymbol,
            wrapperType: wrapperType,
            shape: shape,
            accessor: accessor,
            captureFields: captureFields,
            fieldOffsets: fieldOffsets,
            sema: sema,
            arena: arena,
            interner: interner
        )

        let intType = sema.types.intType
        let slotCount = Int64(max(2 + captureFields.count, 1))
        let slotCountExpr = arena.appendExpr(.intLiteral(slotCount), type: intType)
        instructions.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))
        let classID = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: wrapperSymbol,
            sema: sema,
            interner: interner
        )
        let classIDExpr = arena.appendExpr(.intLiteral(classID), type: intType)
        instructions.append(.constValue(result: classIDExpr, value: .intLiteral(classID)))
        let wrapperValue = arena.appendTemporary(type: boundType)
        instructions.append(.call(
            callee: interner.intern("kk_object_new"),
            arguments: [slotCountExpr, classIDExpr],
            result: wrapperValue,
            canThrow: false
        ))

        registerPropertyReferenceInterfaces(
            wrapperValue: wrapperValue,
            wrapperSymbol: wrapperSymbol,
            interfaceSymbols: interfaceSymbols,
            getterMethodSymbol: getterMethodSymbol,
            setterMethodSymbol: setterMethodSymbol,
            getDelegateMethodSymbol: getDelegateMethodSymbol,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )

        for (index, capture) in captureArguments.enumerated() {
            guard index < captureFields.count,
                  let fieldOffset = fieldOffsets[captureFields[index]]
            else { continue }
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: intType)
            instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
            let storeResult = arena.appendTemporary(type: sema.types.anyType)
            instructions.append(.call(
                callee: interner.intern("kk_array_set"),
                arguments: [wrapperValue, offsetExpr, capture],
                result: storeResult,
                canThrow: true
            ))
        }

        let nameExpr = arena.appendExpr(.stringLiteral(memberName), type: sema.types.stringType)
        instructions.append(.constValue(result: nameExpr, value: .stringLiteral(memberName)))
        let returnTypeName = interner.intern(
            sema.types.displayName(of: reflectedPropertyType, symbols: sema.symbols, interner: interner)
        )
        let returnTypeExpr = arena.appendExpr(.stringLiteral(returnTypeName), type: sema.types.stringType)
        instructions.append(.constValue(result: returnTypeExpr, value: .stringLiteral(returnTypeName)))
        let arityExpr = arena.appendExpr(.intLiteral(Int64(shape.arity)), type: intType)
        instructions.append(.constValue(result: arityExpr, value: .intLiteral(Int64(shape.arity))))
        let taggedValue = arena.appendTemporary(type: boundType)
        instructions.append(.call(
            callee: interner.intern("kk_callable_ref_tag_kproperty"),
            arguments: [wrapperValue, nameExpr, returnTypeExpr, arityExpr],
            result: taggedValue,
            canThrow: false
        ))
        emitCallableReferenceIdentity(
            callableExpr: taggedValue,
            targetSymbol: accessor.getterSymbol,
            captures: captureArguments,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        driver.ctx.registerCallableValue(
            taggedValue,
            symbol: getterMethodSymbol,
            callee: interner.intern("get"),
            captureArguments: [wrapperValue],
            hasClosureParam: false
        )
        registerCallableReflection(
            value: taggedValue, callableSymbol: getterMethodSymbol, callableName: interner.intern("get"),
            targetSymbol: accessor.propertySymbol,
            parameterTypes: shape.arity == 0 ? [] : [
                propertyReferenceReceiverParameterType(
                    accessor: accessor, receiverClassSymbol: receiverClassSymbol, sema: sema
                ),
            ],
            returnType: reflectedPropertyType, captures: [wrapperValue], receiverCount: shape.arity,
            setterSymbol: setterMethodSymbol, ast: ast, sema: sema, arena: arena, interner: interner,
            instructions: &instructions
        )
        _ = isUnbound
        return taggedValue
    }

    private func propertyReferenceShape(
        interfaceSymbol: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> PropertyReferenceShape? {
        guard let symbol = sema.symbols.symbol(interfaceSymbol) else { return nil }
        switch interner.resolve(symbol.name) {
        case "KProperty0": return .property0
        case "KMutableProperty0": return .mutableProperty0
        case "KProperty1": return .property1
        case "KMutableProperty1": return .mutableProperty1
        case "KProperty2": return .property2
        case "KMutableProperty2": return .mutableProperty2
        default: return nil
        }
    }

    private func propertyReferenceInterfaceClosure(
        root: SymbolID,
        sema: SemaModule
    ) -> [SymbolID] {
        var result: [SymbolID] = []
        var pending = [root]
        var visited: Set<SymbolID> = []
        while let symbol = pending.popLast() {
            guard visited.insert(symbol).inserted else { continue }
            guard sema.symbols.symbol(symbol)?.kind == .interface else { continue }
            result.append(symbol)
            pending.append(contentsOf: sema.symbols.directSupertypes(for: symbol))
        }
        return result.sorted { $0.rawValue < $1.rawValue }
    }

    /// Erased class through which the reference is taken: the first
    /// `KPropertyN` type argument for unbound `Type::member` references, or
    /// the bound receiver's static type for `expr::member`. Only the nominal
    /// symbol matters — the written type arguments are dropped, matching the
    /// JVM's raw `KClass` owner.
    private func propertyReferenceReceiverClassSymbol(
        shape: PropertyReferenceShape,
        isUnbound: Bool,
        referenceType: ClassType,
        captureArguments: [KIRExprID],
        sema: SemaModule,
        arena: KIRArena
    ) -> SymbolID? {
        let receiverType: TypeID? = {
            if isUnbound {
                guard shape.arity >= 1, let firstArg = referenceType.args.first else { return nil }
                switch firstArg {
                case let .invariant(type), let .out(type), let .in(type):
                    return type
                case .star:
                    return nil
                }
            }
            return captureArguments.first.flatMap { arena.exprType($0) }
        }()
        guard let receiverType,
              case let .classType(receiver) = sema.types.kind(of: sema.types.makeNonNullable(receiverType))
        else {
            return nil
        }
        return receiver.classSymbol
    }

    /// The `receiverClass` instantiation of the declaring class's parameters,
    /// applied to the declared property type — the "member scope" type of the
    /// property as seen from the receiver class. Falls back to the declared
    /// type whenever no substitution applies (non-class owner, non-generic
    /// declaring class, or unreachable supertype).
    private func propertyReferenceReflectedType(
        propertySymbol: SymbolID,
        propertyType: TypeID,
        receiverClassSymbol: SymbolID?,
        sema: SemaModule
    ) -> TypeID {
        guard let receiverClassSymbol,
              let declaringSymbol = sema.symbols.parentSymbol(for: propertySymbol),
              let declaringInfo = sema.symbols.symbol(declaringSymbol),
              [.class, .interface, .object, .enumClass, .annotationClass].contains(declaringInfo.kind)
        else {
            return propertyType
        }
        let declaringParameters = sema.types.allTypeParameterSymbols(for: declaringSymbol)
        guard !declaringParameters.isEmpty else { return propertyType }

        let receiverArgs: [TypeArg] = sema.types.allTypeParameterSymbols(for: receiverClassSymbol).map {
            .invariant(sema.types.make(.typeParam(TypeParamType(symbol: $0, nullability: .nonNull))))
        }
        guard let lifted = sema.types.liftedNominalSupertypeArgs(
            from: receiverClassSymbol,
            childArgs: receiverArgs,
            to: declaringSymbol
        ) else {
            return propertyType
        }

        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(declaringParameters)
        var substitution: [TypeVarID: TypeID] = [:]
        for (index, arg) in lifted.enumerated() where declaringParameters.indices.contains(index) {
            guard let typeVar = typeVarBySymbol[declaringParameters[index]] else { continue }
            switch arg {
            case let .invariant(type), let .out(type), let .in(type):
                substitution[typeVar] = type
            case .star:
                continue
            }
        }
        guard !substitution.isEmpty else { return propertyType }
        return sema.types.substituteTypeParameters(
            in: propertyType,
            substitution: substitution,
            typeVarBySymbol: typeVarBySymbol
        )
    }

    /// INSTANCE parameter type of the reflected member: the erased receiver
    /// class parameterized by its own type parameters (e.g. `A` for
    /// `A::parent`, `H<T>` for `H<A>::parent`). Extension properties keep
    /// their declared receiver type.
    private func propertyReferenceReceiverParameterType(
        accessor: PropertyReferenceAccessor,
        receiverClassSymbol: SymbolID?,
        sema: SemaModule
    ) -> TypeID {
        let fallback = accessor.ownerType ?? sema.types.anyType
        guard let receiverClassSymbol,
              sema.symbols.extensionPropertyReceiverType(for: accessor.propertySymbol) == nil
        else {
            return fallback
        }
        let selfArgs: [TypeArg] = sema.types.allTypeParameterSymbols(for: receiverClassSymbol).map {
            .invariant(sema.types.make(.typeParam(TypeParamType(symbol: $0, nullability: .nonNull))))
        }
        return sema.types.make(.classType(sema.types.classType(
            for: receiverClassSymbol,
            arguments: selfArgs,
            nullability: .nonNull
        )))
    }

    func propertySymbol(for targetSymbol: SymbolID, sema: SemaModule) -> SymbolID? {
        if sema.symbols.symbol(targetSymbol)?.kind == .property {
            return targetSymbol
        }
        if let owner = sema.symbols.accessorOwnerProperty(for: targetSymbol) {
            return owner
        }
        return sema.symbols.allSymbols().first { symbol in
            symbol.kind == .property
                && (sema.symbols.extensionPropertyGetterAccessor(for: symbol.id) == targetSymbol
                    || sema.symbols.extensionPropertySetterAccessor(for: symbol.id) == targetSymbol
                    || SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol.id) == targetSymbol
                    || SyntheticSymbolScheme.propertySetterAccessorSymbol(for: symbol.id) == targetSymbol)
        }?.id
    }

    private func propertyDecl(
        for propertySymbol: SymbolID,
        ast: ASTModule,
        sema: SemaModule
    ) -> PropertyDecl? {
        for rawDecl in ast.arena.decls.indices {
            let declID = DeclID(rawValue: Int32(rawDecl))
            guard sema.bindings.declSymbols[declID] == propertySymbol,
                  let decl = ast.arena.decl(declID),
                  case let .propertyDecl(property) = decl
            else { continue }
            return property
        }
        return nil
    }

    /// `lowerPropertyReferenceWrapperValue` only covers the KProperty shapes,
    /// and the property symbol itself has no emitted function behind it, so
    /// every other consumer has to fall back to the generated accessor —
    /// otherwise codegen emits a direct call to a nonexistent symbol named
    /// after the property and the program fails to link.
    ///
    /// The accessor's signature already matches both callable-reference
    /// shapes: `(receiver) -> value` for a member property (the receiver is
    /// the function type's single parameter for `Type::member`, or the
    /// captured receiver for `instance::member`) and `() -> value` for a
    /// top-level or `object`-owned one.
    func propertyReferenceFunctionCallTarget(
        targetSymbol: SymbolID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind]
    ) -> (symbol: SymbolID, name: InternedString)? {
        guard let accessor = ensurePropertyReferenceAccessor(
            targetSymbol: targetSymbol,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers
        )
        else {
            return nil
        }
        if let thunk = virtualPropertyGetterThunk(
            accessor: accessor,
            sema: sema,
            arena: arena,
            interner: interner
        ) {
            return thunk
        }
        if let getter = arena.function(for: accessor.getterSymbol) {
            return propertyGetterThunk(
                accessor: accessor,
                getterName: getter.name,
                sema: sema,
                arena: arena,
                interner: interner
            )
        }
        // REFL-EXTPROP: an extension property imported from a precompiled
        // stdlib `.kklib` (e.g. `String.length`) links its getter externally
        // instead of getting a body lowered into *this* arena -- see the
        // matching external-link-name guard in `ensurePropertyReferenceAccessor`,
        // which deliberately leaves such a getter absent from the arena
        // rather than synthesizing a bogus stored-property body for it.
        if let externalLinkName = sema.symbols.externalLinkName(for: accessor.getterSymbol),
           !externalLinkName.isEmpty
        {
            return propertyGetterThunk(
                accessor: accessor,
                getterName: interner.intern(externalLinkName),
                sema: sema,
                arena: arena,
                interner: interner
            )
        }
        return nil
    }

    private func propertyGetterThunk(
        accessor: PropertyReferenceAccessor,
        getterName: InternedString,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner
    ) -> (symbol: SymbolID, name: InternedString) {
        let name = interner.intern("kk_lambda_property_getter_\(accessor.propertySymbol.rawValue)")
        if let existing = sema.symbols.lookup(fqName: [name]) {
            return (existing, name)
        }
        let symbol = sema.symbols.define(
            kind: .function,
            name: name,
            fqName: [name],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let receiverType = sema.symbols.functionSignature(for: accessor.getterSymbol)?.receiverType
        let params = receiverType.map { type in
            [KIRParameter(
                symbol: driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: symbol),
                type: type
            )]
        } ?? []
        sema.symbols.setFunctionSignature(
            FunctionSignature(receiverType: receiverType, parameterTypes: [], returnType: accessor.propertyType),
            for: symbol
        )
        var body: [KIRInstruction] = [.beginBlock]
        let arguments = params.map { param in
            let value = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
            body.append(.constValue(result: value, value: .symbolRef(param.symbol)))
            return value
        }
        let result = arena.appendTemporary(type: accessor.propertyType)
        // Adapt the thunk, not the getter, to the raw function-value ABI.
        // Imported getters must retain their compiled aggregate/throwing ABI.
        body.append(.call(symbol: accessor.getterSymbol, callee: getterName, arguments: arguments, result: result, canThrow: true))
        body.append(.returnValue(result))
        body.append(.endBlock)
        driver.ctx.appendGeneratedCallableDecl(arena.appendDecl(.function(KIRFunction(
            symbol: symbol,
            name: name,
            params: params,
            returnType: accessor.propertyType,
            body: body,
            isSuspend: false,
            isInline: false
        ))))
        return (symbol, name)
    }

    private func ensurePropertyReferenceAccessor(
        targetSymbol: SymbolID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind]
    ) -> PropertyReferenceAccessor? {
        guard let propertySymbol = propertySymbol(for: targetSymbol, sema: sema),
              let propertyType = sema.symbols.propertyType(for: propertySymbol)
        else { return nil }

        let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol)
        let ownerKind = ownerSymbol.flatMap { sema.symbols.symbol($0)?.kind }
        // KSP-505: a genuine `.object` owner (companion object or plain
        // `object`) is a singleton — Kotlin guarantees exactly one instance,
        // so the compiler stores such properties in a single module-level
        // global slot rather than a per-instance field (see the matching
        // `pk == .object` branch in ExprLowerer+ControlFlowAndBlocks.swift's
        // ordinary member read path). Passing `ownerType: nil` here routes
        // emitPropertyReferenceAccessor's fallback below (loadGlobal /
        // storeGlobal, no receiver) instead of the field-offset path, which
        // would otherwise read/write through a receiver that is frequently a
        // null placeholder (object singletons that implement no interface
        // and declare no virtual dispatch never allocate a real heap
        // instance) — this used to crash with SIGSEGV.
        //
        // Extension getters receive their declared receiver, not their package.
        // Class/interface/enum properties retain per-instance storage; package
        // and singleton object properties have no instance receiver.
        let ownerType: TypeID?
        if let extensionReceiverType = sema.symbols.extensionPropertyReceiverType(for: propertySymbol) {
            ownerType = extensionReceiverType
        } else if ownerKind == .object || ownerKind == .package {
            ownerType = nil
        } else {
            ownerType = ownerSymbol.flatMap { owner in
                sema.symbols.symbol(owner).map {
                    sema.types.make(.classType(ClassType(
                        classSymbol: $0.id,
                        args: [],
                        nullability: .nonNull
                    )))
                }
            }
        }
        let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol)
            ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: propertySymbol)
        let setterSymbol = sema.symbols.extensionPropertySetterAccessor(for: propertySymbol)
            ?? (sema.symbols.symbol(propertySymbol)?.flags.contains(.mutable) == true
                ? SyntheticSymbolScheme.propertySetterAccessorSymbol(for: propertySymbol)
                : nil)

        // REFL-EXTPROP: an extension property imported from a precompiled
        // stdlib `.kklib` (LibraryImport.swift) already points its
        // accessor's symbol at a real external link name -- it links
        // against the library's own compiled getter/setter the same way any
        // other imported function does, and has no AST `propertyDecl` in
        // *this* compilation for `emitPropertyReferenceAccessor` to read a
        // body from. Synthesizing one anyway falls through to that
        // function's stored-property fallback, which fabricates a
        // load/storeGlobal body for a property that was never a stored
        // global to begin with (`String.length` is a computed getter) and
        // links against a global slot that was never created
        // (`kk_global_root_slot_kotlin_length`, undefined at link time).
        let getterIsExternallyLinked = sema.symbols.externalLinkName(for: getterSymbol)?.isEmpty == false
        if arena.function(for: getterSymbol) == nil, !getterIsExternallyLinked {
            emitPropertyReferenceAccessor(
                propertySymbol: propertySymbol,
                accessorSymbol: getterSymbol,
                ownerType: ownerType,
                propertyType: propertyType,
                kind: .getter,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers
            )
        }
        let setterIsExternallyLinked = setterSymbol.flatMap { sema.symbols.externalLinkName(for: $0) }?.isEmpty == false
        if let setterSymbol,
           arena.function(for: setterSymbol) == nil,
           !setterIsExternallyLinked
        {
            emitPropertyReferenceAccessor(
                propertySymbol: propertySymbol,
                accessorSymbol: setterSymbol,
                ownerType: ownerType,
                propertyType: propertyType,
                kind: .setter,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers
            )
        }
        return PropertyReferenceAccessor(
            propertySymbol: propertySymbol,
            getterSymbol: getterSymbol,
            setterSymbol: setterSymbol,
            propertyType: propertyType,
            ownerType: ownerType
        )
    }

    /// The `$enumConstructorProperty$` / `$enumPropertySetter$` placeholder
    /// callee for an enum-owned property accessor, or nil when the property
    /// keeps ordinary instance/global storage.
    private func enumPropertyAccessorPlaceholder(
        for propertySymbol: SymbolID,
        kind: PropertyAccessorKind,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString? {
        switch kind {
        case .getter:
            return driver.callLowerer.enumPropertyGetterPlaceholder(
                for: propertySymbol, sema: sema, interner: interner
            )
        case .setter:
            return driver.callLowerer.enumPropertySetterPlaceholder(
                for: propertySymbol, sema: sema, interner: interner
            )
        }
    }

    private func emitPropertyReferenceAccessor(
        propertySymbol: SymbolID,
        accessorSymbol: SymbolID,
        ownerType: TypeID?,
        propertyType: TypeID,
        kind: PropertyAccessorKind,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind]
    ) {
        if let property = propertyDecl(for: propertySymbol, ast: ast, sema: sema),
           let body = kind == .getter ? property.getter?.body : property.setter?.body,
           body != .unit
        {
            var decls: [KIRDeclID] = []
            driver.memberLowerer.lowerAccessorBody(
                accessorBody: body,
                propertySymbol: propertySymbol,
                propertyType: propertyType,
                accessorKind: kind,
                setterParamName: property.setter?.parameterName,
                shared: KIRLoweringSharedContext(
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers
                ),
                allDecls: &decls
            )
            for decl in decls {
                driver.ctx.appendGeneratedCallableDecl(decl)
            }
            return
        }

        let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol)
        let fieldKey = sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
        let fieldOffset = ownerSymbol.flatMap {
            sema.symbols.nominalLayout(for: $0)?.fieldOffsets[fieldKey]
        }
        let receiverSymbol = ownerType.map { _ in
            driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: accessorSymbol)
        }
        let valueSymbol: SymbolID? = kind == .setter
            ? sema.symbols.define(
                kind: .valueParameter,
                name: interner.intern("value"),
                fqName: [interner.intern("kk_property_accessor_\(accessorSymbol.rawValue)"), interner.intern("value")],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            : nil
        if let valueSymbol { sema.symbols.setPropertyType(propertyType, for: valueSymbol) }

        var params: [KIRParameter] = []
        if let receiverSymbol, let ownerType {
            params.append(KIRParameter(symbol: receiverSymbol, type: ownerType))
        }
        if let valueSymbol {
            params.append(KIRParameter(symbol: valueSymbol, type: propertyType))
        }
        let accessorName = interner.intern(kind == .getter ? "get" : "set")
        sema.symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: kind == .setter ? [propertyType] : [],
                returnType: kind == .getter ? propertyType : sema.types.unitType,
                valueParameterSymbols: valueSymbol.map { [$0] } ?? []
            ),
            for: accessorSymbol
        )

        var body: [KIRInstruction] = [.beginBlock]
        let receiverExpr = receiverSymbol.flatMap { symbol -> KIRExprID? in
            guard let ownerType else { return nil }
            let expr = arena.appendExpr(.symbolRef(symbol), type: ownerType)
            body.append(.constValue(result: expr, value: .symbolRef(symbol)))
            return expr
        }
        let enumPropertyInfo = sema.symbols.symbol(propertySymbol)
        let isSyntheticEnumNameOrdinalProperty: Bool = {
            guard let enumPropertyInfo,
                  enumPropertyInfo.kind == .property,
                  enumPropertyInfo.flags.contains(.synthetic),
                  enumPropertyInfo.name == interner.intern("name")
                    || enumPropertyInfo.name == interner.intern("ordinal"),
                  let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol)
            else {
                return false
            }
            return sema.symbols.symbol(ownerSymbol)?.kind == .enumClass
        }()
        if kind == .getter,
           let externalLinkName = sema.symbols.externalLinkName(for: propertySymbol),
           !externalLinkName.isEmpty
        {
            // Runtime-backed properties retain their bridge even when bundled
            // source declares the property without a getter body.
            let result = arena.appendTemporary(type: propertyType)
            body.append(.call(
                symbol: propertySymbol,
                callee: interner.intern(externalLinkName),
                arguments: receiverExpr.map { [$0] } ?? [],
                result: result,
                canThrow: false
            ))
            body.append(.returnValue(result))
        } else if let receiverExpr,
                  kind == .getter,
                  isSyntheticEnumNameOrdinalProperty,
                  let enumPropertyInfo
        {
            // Enum headers synthesize these properties on each concrete enum.
            // Route them through the enum name/ordinal lowering instead of the
            // constructor-property slot helpers used by ordinary enum fields.
            let result = arena.appendTemporary(type: propertyType)
            body.append(.call(callee: enumPropertyInfo.name, arguments: [receiverExpr], result: result, canThrow: false))
            body.append(.returnValue(result))
        } else if let receiverExpr,
                  kind == .getter,
                  let enumBaseValue = driver.callLowerer.tryLowerEnumBasePropertyRead(
                      propertySymbol: propertySymbol,
                      receiver: receiverExpr,
                      receiverType: ownerType,
                      resultType: propertyType,
                      sema: sema,
                      arena: arena,
                      interner: interner,
                      instructions: &body
                  )
        {
            // Enum.name and Enum.ordinal are compiler-owned views over the
            // boxed ordinal, not fields in Enum's nominal object layout.
            body.append(.returnValue(enumBaseValue))
        } else if let receiverExpr,
                  let enumHelperCallee = enumPropertyAccessorPlaceholder(
                      for: propertySymbol,
                      kind: kind,
                      sema: sema,
                      interner: interner
                  )
        {
            // Enum member state lives in per-entry ordinal slots behind the
            // `$enumConstructorProperty$` / `$enumPropertySetter$` helpers —
            // there is no instance field to index and no per-property global,
            // so the field/global fallbacks below read a slot that is never
            // written (e.g. `this::value.get()` inside an enum entry returned
            // null). The placeholder callee is rewritten to the ID-free
            // helper by EnumNameAccessLoweringPass, matching the ordinary
            // member read/write paths.
            if kind == .getter {
                let result = arena.appendTemporary(type: propertyType)
                body.append(.call(callee: enumHelperCallee, arguments: [receiverExpr], result: result, canThrow: false))
                body.append(.returnValue(result))
            } else if let valueSymbol {
                let valueExpr = arena.appendExpr(.symbolRef(valueSymbol), type: propertyType)
                body.append(.constValue(result: valueExpr, value: .symbolRef(valueSymbol)))
                let result = arena.appendTemporary(type: sema.types.unitType)
                body.append(.call(callee: enumHelperCallee, arguments: [receiverExpr, valueExpr], result: result, canThrow: false))
                body.append(.returnUnit)
            }
        } else if let fieldOffset,
           let receiverExpr
        {
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
            body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
            if kind == .getter {
                let result = arena.appendTemporary(type: propertyType)
                body.append(.call(
                    callee: interner.intern("kk_array_get_inbounds"),
                    arguments: [receiverExpr, offsetExpr],
                    result: result,
                    canThrow: false
                ))
                body.append(.returnValue(result))
            } else if let valueSymbol {
                let valueExpr = arena.appendExpr(.symbolRef(valueSymbol), type: propertyType)
                body.append(.constValue(result: valueExpr, value: .symbolRef(valueSymbol)))
                let result = arena.appendTemporary(type: sema.types.anyType)
                body.append(.call(
                    callee: interner.intern("kk_array_set"),
                    arguments: [receiverExpr, offsetExpr, valueExpr],
                    result: result,
                    canThrow: true
                ))
                body.append(.returnUnit)
            }
        } else if kind == .getter {
            // KSP-496: an immutable top-level (or object-member) property
            // with a compile-time-constant initializer is never actually
            // written via `.storeGlobal` — every ordinary read inlines the
            // constant directly instead (see the equivalent check in
            // ExprLowerer+ControlFlowAndBlocks.swift). Emitting a bare
            // `.loadGlobal` here read that permanently-unwritten (zero)
            // slot. Mirror the same constant-inlining check before falling
            // back to `.loadGlobal` for genuinely global-backed properties
            // (`var`s, or `val`s with a non-constant initializer).
            let propertyInfo = sema.symbols.symbol(propertySymbol)
            if let constant = propertyConstantInitializers[propertySymbol] ?? sema.symbols.constValueExprKind(for: propertySymbol),
               propertyInfo?.flags.contains(.mutable) != true
            {
                let result = arena.appendExpr(constant, type: propertyType)
                body.append(.constValue(result: result, value: constant))
                body.append(.returnValue(result))
            } else {
                let result = arena.appendTemporary(type: propertyType)
                body.append(.loadGlobal(result: result, symbol: fieldKey))
                body.append(.returnValue(result))
            }
        } else if let valueSymbol {
            let valueExpr = arena.appendExpr(.symbolRef(valueSymbol), type: propertyType)
            body.append(.constValue(result: valueExpr, value: .symbolRef(valueSymbol)))
            body.append(.storeGlobal(value: valueExpr, symbol: fieldKey))
            body.append(.returnUnit)
        } else {
            let result = arena.appendExpr(.null, type: propertyType)
            body.append(.constValue(result: result, value: .null))
            body.append(.returnValue(result))
        }
        body.append(.endBlock)
        driver.ctx.appendGeneratedCallableDecl(arena.appendDecl(.function(KIRFunction(
            symbol: accessorSymbol,
            name: accessorName,
            params: params,
            returnType: kind == .getter ? propertyType : sema.types.unitType,
            body: body,
            isSuspend: false,
            isInline: false
        ))))
    }

    private func definePropertyReferenceMethod(
        name: String,
        wrapperSymbol: SymbolID,
        wrapperFQName: [InternedString],
        parameterTypes: [TypeID],
        returnType: TypeID,
        canThrow: Bool = false,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID {
        let methodName = interner.intern(name)
        let methodSymbol = sema.symbols.define(
            kind: .function,
            name: methodName,
            fqName: wrapperFQName + [methodName],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        sema.symbols.setParentSymbol(wrapperSymbol, for: methodSymbol)
        let parameterSymbols = parameterTypes.enumerated().map { index, type in
            let symbol = sema.symbols.define(
                kind: .valueParameter,
                name: interner.intern("$p\(index)"),
                fqName: wrapperFQName + [methodName, interner.intern("$p\(index)")],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            sema.symbols.setPropertyType(type, for: symbol)
            return symbol
        }
        sema.symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: sema.types.make(.classType(ClassType(
                    classSymbol: wrapperSymbol,
                    args: [],
                    nullability: .nonNull
                ))),
                parameterTypes: parameterTypes,
                returnType: returnType,
                canThrow: canThrow,
                valueParameterSymbols: parameterSymbols
            ),
            for: methodSymbol
        )
        return methodSymbol
    }

    private func emitPropertyReferenceGetter(
        methodSymbol: SymbolID,
        wrapperType: TypeID,
        accessor: PropertyReferenceAccessor,
        captureFields: [SymbolID],
        fieldOffsets: [SymbolID: Int],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner
    ) {
        let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: methodSymbol)
        let parameterSymbols = sema.symbols.functionSignature(for: methodSymbol)?.valueParameterSymbols ?? []
        let params = [KIRParameter(symbol: receiverSymbol, type: wrapperType)] + parameterSymbols.compactMap { symbol in
            sema.symbols.propertyType(for: symbol).map { KIRParameter(symbol: symbol, type: $0) }
        }
        let receiverExpr = arena.appendExpr(.symbolRef(receiverSymbol), type: wrapperType)
        var body: [KIRInstruction] = [.beginBlock, .constValue(result: receiverExpr, value: .symbolRef(receiverSymbol))]
        var captures: [KIRExprID] = []
        for (index, field) in captureFields.enumerated() {
            guard let offset = fieldOffsets[field] else { continue }
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(offset)), type: sema.types.intType)
            body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(offset))))
            let captureType = params.dropFirst().first?.type ?? accessor.ownerType ?? sema.types.anyType
            let capture = arena.appendTemporary(type: captureType)
            body.append(.call(callee: interner.intern("kk_array_get_inbounds"), arguments: [receiverExpr, offsetExpr], result: capture, canThrow: false))
            captures.append(capture)
            _ = index
        }
        var callArgs = captures
        for parameter in params.dropFirst() {
            let parameterExpr = arena.appendExpr(.symbolRef(parameter.symbol), type: parameter.type)
            body.append(.constValue(result: parameterExpr, value: .symbolRef(parameter.symbol)))
            callArgs.append(parameterExpr)
        }
        if let boundOwner = emitPropertyReferenceSingletonOwnerReceiver(
            accessorSymbol: accessor.getterSymbol,
            accessor: accessor,
            captures: captures,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &body
        ) {
            callArgs.insert(boundOwner, at: 0)
        }
        // An interface / open / abstract member property must be read through
        // its itable / vtable, exactly like an ordinary `receiver.prop` read:
        // calling the declaring accessor statically would run the abstract
        // stub (null) or the base getter instead of the implementer's.
        if accessor.ownerType != nil,
           let dispatchReceiver = callArgs.first,
           let dispatched = emitVirtualPropertyReferenceGetterRead(
               accessor: accessor,
               receiver: dispatchReceiver,
               sema: sema,
               arena: arena,
               interner: interner,
               instructions: &body
           )
        {
            body.append(.returnValue(dispatched))
            body.append(.endBlock)
            driver.ctx.appendGeneratedCallableDecl(arena.appendDecl(.function(KIRFunction(
                symbol: methodSymbol,
                name: interner.intern("get"),
                params: params,
                returnType: accessor.propertyType,
                body: body,
                isSuspend: false,
                isInline: false
            ))))
            return
        }
        let result = arena.appendTemporary(type: accessor.propertyType)
        body.append(.call(symbol: accessor.getterSymbol, callee: interner.intern("get"), arguments: callArgs, result: result, canThrow: false))
        body.append(.returnValue(result))
        body.append(.endBlock)
        driver.ctx.appendGeneratedCallableDecl(arena.appendDecl(.function(KIRFunction(
            symbol: methodSymbol,
            name: interner.intern("get"),
            params: params,
            returnType: accessor.propertyType,
            body: body,
            isSuspend: false,
            isInline: false
        ))))
    }

    /// `(receiver) -> value` function-value target for an interface / open /
    /// abstract member property. The plain accessor is the declaring type's
    /// own (possibly abstract-stub) getter, so the function value needs a
    /// thunk that dispatches through the itable / vtable. Returns `nil` when
    /// the property needs no dispatch.
    private func virtualPropertyGetterThunk(
        accessor: PropertyReferenceAccessor,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner
    ) -> (symbol: SymbolID, name: InternedString)? {
        guard let ownerType = accessor.ownerType else { return nil }
        let getName = interner.intern("get")
        let thunkFQName = [interner.intern("kk_property_virtual_getter_\(accessor.propertySymbol.rawValue)"), getName]
        if let existing = sema.symbols.lookup(fqName: thunkFQName) {
            return (existing, getName)
        }
        // Probe applicability before defining anything, so a property that
        // needs no dispatch never leaves a body-less thunk symbol behind.
        var probe: [KIRInstruction] = []
        let probeReceiver = arena.appendExpr(.intLiteral(0), type: ownerType)
        guard emitVirtualPropertyReferenceGetterRead(
            accessor: accessor,
            receiver: probeReceiver,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &probe
        ) != nil else {
            return nil
        }
        let thunkSymbol = sema.symbols.define(
            kind: .function,
            name: getName,
            fqName: thunkFQName,
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: thunkSymbol)
        let receiverExpr = arena.appendExpr(.symbolRef(receiverSymbol), type: ownerType)
        var body: [KIRInstruction] = [.beginBlock, .constValue(result: receiverExpr, value: .symbolRef(receiverSymbol))]
        guard let dispatched = emitVirtualPropertyReferenceGetterRead(
            accessor: accessor,
            receiver: receiverExpr,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &body
        ) else {
            return nil
        }
        body.append(.returnValue(dispatched))
        body.append(.endBlock)
        sema.symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: [],
                returnType: accessor.propertyType,
                valueParameterSymbols: []
            ),
            for: thunkSymbol
        )
        driver.ctx.appendGeneratedCallableDecl(arena.appendDecl(.function(KIRFunction(
            symbol: thunkSymbol,
            name: getName,
            params: [KIRParameter(symbol: receiverSymbol, type: ownerType)],
            returnType: accessor.propertyType,
            body: body,
            isSuspend: false,
            isInline: false
        ))))
        return (thunkSymbol, getName)
    }

    private func emitVirtualPropertyReferenceGetterRead(
        accessor: PropertyReferenceAccessor,
        receiver: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        // Runtime-backed interface properties may have nominal itable slots
        // for Kotlin implementations, while opaque runtime boxes (such as
        // mapOf results) do not register those slots. Their external getter
        // bridge handles both representations, so let the property-reference
        // wrapper call its synthesized accessor instead of dispatching here.
        if sema.symbols.externalLinkName(for: accessor.propertySymbol)?.isEmpty == false {
            return nil
        }
        if let interfaceRead = driver.callLowerer.tryLowerInterfaceItablePropertyGetterRead(
            propertySymbol: accessor.propertySymbol,
            loweredReceiverID: receiver,
            resultType: accessor.propertyType,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) {
            return interfaceRead
        }
        guard let (getterSymbol, dispatch) = driver.callLowerer.resolvePropertyAccessorVirtualDispatch(
            propertySymbol: accessor.propertySymbol,
            accessorKind: .getter,
            sema: sema
        ) else {
            return nil
        }
        let result = arena.appendTemporary(type: accessor.propertyType)
        instructions.append(.virtualCall(
            symbol: getterSymbol,
            callee: interner.intern("get"),
            receiver: receiver,
            arguments: [],
            result: result,
            canThrow: false,
            dispatch: dispatch
        ))
        return result
    }

    private func emitPropertyReferenceSetter(
        methodSymbol: SymbolID,
        wrapperType: TypeID,
        accessor: PropertyReferenceAccessor,
        captureFields: [SymbolID],
        fieldOffsets: [SymbolID: Int],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner
    ) {
        let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: methodSymbol)
        let parameterSymbols = sema.symbols.functionSignature(for: methodSymbol)?.valueParameterSymbols ?? []
        let params = [KIRParameter(symbol: receiverSymbol, type: wrapperType)] + parameterSymbols.compactMap { symbol in
            sema.symbols.propertyType(for: symbol).map { KIRParameter(symbol: symbol, type: $0) }
        }
        let receiverExpr = arena.appendExpr(.symbolRef(receiverSymbol), type: wrapperType)
        var body: [KIRInstruction] = [.beginBlock, .constValue(result: receiverExpr, value: .symbolRef(receiverSymbol))]
        var captures: [KIRExprID] = []
        for field in captureFields {
            guard let offset = fieldOffsets[field] else { continue }
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(offset)), type: sema.types.intType)
            body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(offset))))
            let captureType = accessor.ownerType ?? sema.types.anyType
            let capture = arena.appendTemporary(type: captureType)
            body.append(.call(callee: interner.intern("kk_array_get_inbounds"), arguments: [receiverExpr, offsetExpr], result: capture, canThrow: false))
            captures.append(capture)
        }
        var callArgs = captures
        for parameter in params.dropFirst() {
            let parameterExpr = arena.appendExpr(.symbolRef(parameter.symbol), type: parameter.type)
            body.append(.constValue(result: parameterExpr, value: .symbolRef(parameter.symbol)))
            callArgs.append(parameterExpr)
        }
        if let boundOwner = emitPropertyReferenceSingletonOwnerReceiver(
            accessorSymbol: accessor.setterSymbol,
            accessor: accessor,
            captures: captures,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &body
        ) {
            callArgs.insert(boundOwner, at: 0)
        }
        let result = arena.appendTemporary(type: sema.types.unitType)
        body.append(.call(symbol: accessor.setterSymbol, callee: interner.intern("set"), arguments: callArgs, result: result, canThrow: false))
        body.append(.returnUnit)
        body.append(.endBlock)
        driver.ctx.appendGeneratedCallableDecl(arena.appendDecl(.function(KIRFunction(
            symbol: methodSymbol,
            name: interner.intern("set"),
            params: params,
            returnType: sema.types.unitType,
            body: body,
            isSuspend: false,
            isInline: false
        ))))
    }

    /// KUU-3803: KSP-505 keeps a bound `O::member` on a singleton `object`
    /// from capturing a receiver, because the synthesized accessors for
    /// *stored* object properties are receiver-less globals. A delegated
    /// (`var x by D`) or custom-accessor member instead compiles to a real
    /// accessor whose signature still takes the owner instance as its
    /// leading `t` parameter — `lowerDelegateAccessor`/`lowerAccessorBody`
    /// forward it to `getValue`/`setValue` and the accessor body's `this`.
    /// Calling that accessor one argument short corrupted the call frame
    /// and segfaulted (`O::member.set(v)`). When the resolved accessor
    /// signature declares a receiver that neither a captured field nor an
    /// interface parameter supplies, load the singleton from its global
    /// slot so the call arity matches the accessor's real signature.
    /// Object literals are excluded: their delegates live in instance
    /// fields, not the singleton global this reads.
    private func emitPropertyReferenceSingletonOwnerReceiver(
        accessorSymbol: SymbolID?,
        accessor: PropertyReferenceAccessor,
        captures: [KIRExprID],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard captures.isEmpty,
              accessor.ownerType == nil,
              let accessorSymbol,
              sema.symbols.functionSignature(for: accessorSymbol)?.receiverType != nil,
              let ownerSymbol = sema.symbols.parentSymbol(for: accessor.propertySymbol),
              sema.symbols.symbol(ownerSymbol)?.kind == .object,
              !sema.bindings.isObjectLiteralPropertySymbol(accessor.propertySymbol)
        else { return nil }
        // Reading the singleton's member state triggers its lazy
        // clinit-equivalent, mirroring the ordinary `O.member` access path.
        driver.emitObjectLazyInitGuardIfNeeded(
            objectSymbol: ownerSymbol, arena: arena, sema: sema,
            interner: interner, instructions: &instructions
        )
        let ownerType = sema.types.make(.classType(ClassType(
            classSymbol: ownerSymbol, args: [], nullability: .nonNull
        )))
        let receiverExpr = arena.appendExpr(.symbolRef(ownerSymbol), type: ownerType)
        instructions.append(.constValue(result: receiverExpr, value: .symbolRef(ownerSymbol)))
        return receiverExpr
    }

    /// `getDelegate()` mirrors the JVM contract: `null` for a property with
    /// no `by` delegate, and the stored delegate object for a delegated one.
    /// The delegate lives in the same storage the lowered accessors use — a
    /// global slot for top-level/object/extension properties, an instance
    /// field for class members, or the per-entry enum slot — so the wrapper
    /// reads it directly instead of throwing the old
    /// KotlinReflectionNotSupportedError stub (KUU-3694).
    private func emitPropertyReferenceGetDelegate(
        methodSymbol: SymbolID,
        wrapperType: TypeID,
        shape: PropertyReferenceShape,
        accessor: PropertyReferenceAccessor,
        captureFields: [SymbolID],
        fieldOffsets: [SymbolID: Int],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner
    ) {
        let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: methodSymbol)
        let parameterSymbols = sema.symbols.functionSignature(for: methodSymbol)?.valueParameterSymbols ?? []
        let params = [KIRParameter(symbol: receiverSymbol, type: wrapperType)] + parameterSymbols.compactMap { symbol in
            sema.symbols.propertyType(for: symbol).map { KIRParameter(symbol: symbol, type: $0) }
        }
        let receiverExpr = arena.appendExpr(.symbolRef(receiverSymbol), type: wrapperType)
        var body: [KIRInstruction] = [.beginBlock, .constValue(result: receiverExpr, value: .symbolRef(receiverSymbol))]

        // The instance whose delegate field to read for a member property:
        // the receiver parameter for an unbound `C::m`, or the bound receiver
        // captured into the first wrapper field for a bound `c::m`.
        var memberReceiverExpr: KIRExprID?
        if shape.arity > 0, let parameter = params.dropFirst().first {
            let parameterExpr = arena.appendExpr(.symbolRef(parameter.symbol), type: parameter.type)
            body.append(.constValue(result: parameterExpr, value: .symbolRef(parameter.symbol)))
            memberReceiverExpr = parameterExpr
        } else if shape.arity == 0,
                  let boundField = captureFields.first,
                  let boundOffset = fieldOffsets[boundField]
        {
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(boundOffset)), type: sema.types.intType)
            body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(boundOffset))))
            let boundReceiver = arena.appendTemporary(type: accessor.ownerType ?? sema.types.anyType)
            body.append(.call(
                callee: interner.intern("kk_array_get_inbounds"),
                arguments: [receiverExpr, offsetExpr],
                result: boundReceiver,
                canThrow: false
            ))
            memberReceiverExpr = boundReceiver
        }

        if let delegateStorage = ensurePropertyReferenceDelegateStorage(
            accessor: accessor,
            sema: sema,
            interner: interner
        ) {
            let ownerSymbol = sema.symbols.parentSymbol(for: accessor.propertySymbol)
            let ownerKind = ownerSymbol.flatMap { sema.symbols.symbol($0)?.kind }
            let memberFieldOffset = (ownerKind == .class || ownerKind == .interface)
                ? ownerSymbol.flatMap {
                    sema.symbols.nominalLayout(for: $0)?.fieldOffsets[delegateStorage]
                }
                : nil
            if let memberFieldOffset, let memberReceiverExpr {
                let offsetExpr = arena.appendExpr(.intLiteral(Int64(memberFieldOffset)), type: sema.types.intType)
                body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(memberFieldOffset))))
                let result = arena.appendTemporary(type: sema.types.anyType)
                body.append(.call(
                    callee: interner.intern("kk_array_get_inbounds"),
                    arguments: [memberReceiverExpr, offsetExpr],
                    result: result,
                    canThrow: false
                ))
                body.append(.returnValue(result))
            } else if ownerKind == .enumClass,
                      let ownerSymbol,
                      let memberReceiverExpr,
                      let storageName = sema.symbols.symbol(delegateStorage)?.name
            {
                // Enum values are ordinal-backed: delegate handles live in
                // per-entry slots behind `$enumConstructorProperty$` — the
                // same placeholder the accessor's loadDelegateHandle emits
                // (rewritten by EnumNameAccessLoweringPass).
                let helperName = EnumPropertyHelperNames.placeholder(
                    prefix: EnumPropertyHelperNames.getterPrefix,
                    ownerSymbol: ownerSymbol,
                    propertyName: storageName,
                    interner: interner
                )
                let result = arena.appendTemporary(type: sema.types.anyType)
                body.append(.call(callee: helperName, arguments: [memberReceiverExpr], result: result, canThrow: false))
                body.append(.returnValue(result))
            } else {
                // Top-level, object-member and extension delegates sit in one
                // global slot — `loadGlobal` mirrors loadDelegateHandle.
                let result = arena.appendTemporary(type: sema.types.anyType)
                body.append(.loadGlobal(result: result, symbol: delegateStorage))
                body.append(.returnValue(result))
            }
        } else {
            let nullExpr = arena.appendExpr(.null, type: sema.types.nullableAnyType)
            body.append(.constValue(result: nullExpr, value: .null))
            body.append(.returnValue(nullExpr))
        }
        body.append(.endBlock)
        driver.ctx.appendGeneratedCallableDecl(arena.appendDecl(.function(KIRFunction(
            symbol: methodSymbol,
            name: interner.intern("getDelegate"),
            params: params,
            returnType: sema.types.nullableAnyType,
            body: body,
            isSuspend: false,
            isInline: false
        ))))
    }

    /// Delegate storage is registered when the `by` property itself lowers,
    /// but a `::prop` reference can be emitted before that point (e.g. `main`
    /// sits above the property). Recreate the storage symbol on demand using
    /// the same `$delegate_<name>` scheme `resolveDelegateStorageSymbol` /
    /// `objectLiteralDelegateStorageSymbol` apply, so `getDelegate` reads the
    /// slot the property's init will fill. Member storage already exists from
    /// header collection, so this is a no-op there.
    private func ensurePropertyReferenceDelegateStorage(
        accessor: PropertyReferenceAccessor,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        if let existing = sema.symbols.delegateStorageSymbol(for: accessor.propertySymbol) {
            return existing
        }
        // Order-independent delegated probe: the type checker binds the
        // resolved getValue symbol on every `by` property before KIR
        // lowering, regardless of which declaration lowers first.
        guard sema.symbols.delegateGetValueSymbol(for: accessor.propertySymbol) != nil else {
            return nil
        }
        let extensionSuffix = sema.symbols.hasExtensionPropertyReceiver(accessor.propertySymbol)
            ? "_extension_\(accessor.propertySymbol.rawValue)"
            : ""
        let propertyName = sema.symbols.symbol(accessor.propertySymbol)?.name ?? interner.intern("")
        let storageName = interner.intern(
            "$delegate_\(interner.resolve(propertyName))\(extensionSuffix)"
        )
        let storageFQName = (sema.symbols.symbol(accessor.propertySymbol)?.fqName.dropLast() ?? [])
            + [storageName]
        let storageSymbol = sema.symbols.define(
            kind: .field,
            name: storageName,
            fqName: Array(storageFQName),
            declSite: nil,
            visibility: .private,
            flags: []
        )
        sema.symbols.setDelegateStorageSymbol(storageSymbol, for: accessor.propertySymbol)
        return storageSymbol
    }

    private func registerPropertyReferenceInterfaces(
        wrapperValue: KIRExprID,
        wrapperSymbol: SymbolID,
        interfaceSymbols: [SymbolID],
        getterMethodSymbol: SymbolID,
        setterMethodSymbol: SymbolID?,
        getDelegateMethodSymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        let intType = sema.types.intType
        let classID = RuntimeTypeCheckToken.stableNominalTypeID(symbol: wrapperSymbol, sema: sema, interner: interner)
        let classIDExpr = arena.appendExpr(.intLiteral(classID), type: intType)
        instructions.append(.constValue(result: classIDExpr, value: .intLiteral(classID)))
        let layout = sema.symbols.nominalLayout(for: wrapperSymbol)
        for interfaceSymbol in interfaceSymbols {
            let interfaceID = RuntimeTypeCheckToken.stableNominalTypeID(symbol: interfaceSymbol, sema: sema, interner: interner)
            let interfaceExpr = arena.appendExpr(.intLiteral(interfaceID), type: intType)
            instructions.append(.constValue(result: interfaceExpr, value: .intLiteral(interfaceID)))
            let edgeResult = arena.appendTemporary(type: intType)
            instructions.append(.call(callee: interner.intern("kk_type_register_iface"), arguments: [classIDExpr, interfaceExpr], result: edgeResult, canThrow: false))

            guard let ifaceSlot = layout?.itableSlots[interfaceSymbol] else { continue }
            let ifaceSlotExpr = arena.appendExpr(.intLiteral(Int64(ifaceSlot)), type: intType)
            instructions.append(.constValue(result: ifaceSlotExpr, value: .intLiteral(Int64(ifaceSlot))))
            let registerIfaceResult = arena.appendTemporary(type: intType)
            instructions.append(.call(callee: interner.intern("kk_object_register_itable_iface"), arguments: [wrapperValue, interfaceExpr, ifaceSlotExpr], result: registerIfaceResult, canThrow: false))

            guard let ifaceLayout = sema.symbols.nominalLayout(for: interfaceSymbol) else { continue }
            for (methodSymbol, methodSlot) in ifaceLayout.vtableSlots {
                guard let methodInfo = sema.symbols.symbol(methodSymbol) else { continue }
                let implementation: SymbolID?
                switch interner.resolve(methodInfo.name) {
                case "get", "invoke": implementation = getterMethodSymbol
                case "set": implementation = setterMethodSymbol
                case "getDelegate": implementation = getDelegateMethodSymbol
                default: implementation = nil
                }
                guard let implementation else { continue }
                let methodSlotExpr = arena.appendExpr(.intLiteral(Int64(methodSlot)), type: intType)
                instructions.append(.constValue(result: methodSlotExpr, value: .intLiteral(Int64(methodSlot))))
                let registeredImplementation = propertyReferenceStringReturnBridge(
                    interfaceMethod: methodSymbol,
                    implementation: implementation,
                    driver: driver,
                    arena: arena,
                    sema: sema,
                    interner: interner
                ) ?? itableBridgeSymbolForMethod(
                    interfaceMethod: methodSymbol,
                    implementation: implementation,
                    nominalSymbol: wrapperSymbol,
                    driver: driver,
                    arena: arena,
                    sema: sema,
                    interner: interner
                )
                let methodFnExpr = arena.appendExpr(.symbolRef(registeredImplementation), type: intType)
                instructions.append(.constValue(result: methodFnExpr, value: .symbolRef(registeredImplementation)))
                let registerMethodResult = arena.appendTemporary(type: intType)
                instructions.append(.call(callee: interner.intern("kk_object_register_itable_method"), arguments: [wrapperValue, ifaceSlotExpr, methodSlotExpr, methodFnExpr], result: registerMethodResult, canThrow: false))
            }
        }
    }

    /// Generic KProperty interfaces use the raw Kotlin handle ABI at an
    /// itable boundary even when their substituted type is String. The wrapper
    /// getter intentionally returns the native String aggregate, so provide an
    /// erased bridge for get/invoke before registering the function pointer.
    /// The impl call below must carry the impl function's own KIR name: a
    /// `kk_`/`__kk_` callee spelling is treated as an external runtime name
    /// and would discard the retained symbol, leaving an undeclared
    /// `__kk_*` reference at link time (KUU-1391).
    private func propertyReferenceStringReturnBridge(
        interfaceMethod: SymbolID,
        implementation: SymbolID,
        driver: KIRLoweringDriver,
        arena: KIRArena,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        guard let methodInfo = sema.symbols.symbol(interfaceMethod),
              (interner.resolve(methodInfo.name) == "get" || interner.resolve(methodInfo.name) == "invoke"),
              let implementationFunction = arena.function(for: implementation),
              case .stringStruct = sema.types.kind(of: implementationFunction.returnType),
              let interfaceSignature = sema.symbols.functionSignature(for: interfaceMethod)
        else {
            return nil
        }

        let bridgeSymbol = driver.ctx.allocateSyntheticGeneratedSymbol()
        let bridgeName = interner.intern(
            "kk_kproperty_string_bridge_"
                + String(interfaceMethod.rawValue)
                + "_"
                + String(implementation.rawValue)
                + "_"
                + String(bridgeSymbol.rawValue)
        )
        var bridgeParams: [KIRParameter] = []
        if let receiverType = interfaceSignature.receiverType {
            bridgeParams.append(KIRParameter(
                symbol: driver.ctx.allocateSyntheticGeneratedSymbol(),
                type: receiverType
            ))
        }
        bridgeParams.append(contentsOf: interfaceSignature.parameterTypes.map { type in
            KIRParameter(symbol: driver.ctx.allocateSyntheticGeneratedSymbol(), type: type)
        })

        var body: [KIRInstruction] = [.beginBlock]
        var args: [KIRExprID] = []
        for parameter in bridgeParams {
            let expr = arena.appendExpr(.symbolRef(parameter.symbol), type: parameter.type)
            body.append(.constValue(result: expr, value: .symbolRef(parameter.symbol)))
            args.append(expr)
        }
        let result = arena.appendTemporary(type: implementationFunction.returnType)
        body.append(.call(symbol: implementation, callee: implementationFunction.name, arguments: args, result: result, canThrow: false))
        body.append(.returnValue(result))
        body.append(.endBlock)
        driver.ctx.appendGeneratedCallableDecl(arena.appendDecl(.function(KIRFunction(
            symbol: bridgeSymbol,
            name: bridgeName,
            params: bridgeParams,
            returnType: sema.types.anyType,
            body: body,
            isSuspend: false,
            isInline: false
        ))))
        return bridgeSymbol
    }

    /// KUU-3194: a delegated property hands a `KProperty` object to
    /// getValue/setValue/provideDelegate. The runtime `RuntimeKPropertyStub`
    /// only registered `KCallable` metadata, so `p.get()`/`p.set()` through
    /// the erased `KPropertyN`/`KMutablePropertyN` interfaces crashed
    /// (`useKPropertyLater`). Build the same accessor-backed wrapper object
    /// `::prop` references use: JVM maps each delegate-site property onto a
    /// `PropertyReferenceN` whose `get`/`set` call the real accessor.
    func lowerDelegatedPropertyStubWrapper(
        propertySymbol: SymbolID,
        propertyName: InternedString,
        ast: ASTModule?,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard let propertyType = sema.symbols.propertyType(for: propertySymbol) else { return nil }
        let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol)
        let ownerIsNominal = ownerSymbol.flatMap { sema.symbols.symbol($0)?.kind }
            .map { [.class, .interface, .object, .enumClass, .annotationClass].contains($0) } == true
        let extensionReceiverType = sema.symbols.extensionPropertyReceiverType(for: propertySymbol)
        // JVM receiver order: a member extension binds (dispatch, extension).
        var receiverTypes: [TypeID] = []
        if ownerIsNominal, let ownerSymbol {
            receiverTypes.append(sema.types.make(.classType(ClassType(
                classSymbol: ownerSymbol, args: [], nullability: .nonNull
            ))))
        }
        if let extensionReceiverType {
            receiverTypes.append(extensionReceiverType)
        }
        guard receiverTypes.count <= 2 else { return nil }
        let isMutable = sema.symbols.symbol(propertySymbol)?.flags.contains(.mutable) == true
        let shape: PropertyReferenceShape = switch (receiverTypes.count, isMutable) {
        case (0, false): .property0
        case (0, true): .mutableProperty0
        case (1, false): .property1
        case (1, true): .mutableProperty1
        case (2, false): .property2
        case (2, true): .mutableProperty2
        default: .property0
        }
        let interfaceBase = isMutable ? "KMutableProperty" : "KProperty"
        guard let interfaceSymbol = sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("reflect"),
            interner.intern("\(interfaceBase)\(receiverTypes.count)")
        ]) else { return nil }
        let interfaceSymbols = propertyReferenceInterfaceClosure(root: interfaceSymbol, sema: sema)
        guard !interfaceSymbols.isEmpty else { return nil }

        let referenceArgs = (receiverTypes + [propertyType]).map(TypeArg.invariant)
        let boundType = sema.types.make(.classType(ClassType(
            classSymbol: interfaceSymbol, args: referenceArgs, nullability: .nonNull
        )))
        let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol)
            ?? SyntheticSymbolScheme.propertyAccessorSymbol(for: propertySymbol, kind: .getter)
        let accessorSetterSymbol = shape.isMutable
            ? (sema.symbols.extensionPropertySetterAccessor(for: propertySymbol)
               ?? SyntheticSymbolScheme.propertyAccessorSymbol(for: propertySymbol, kind: .setter))
            : nil
        let accessor = PropertyReferenceAccessor(
            propertySymbol: propertySymbol,
            getterSymbol: getterSymbol,
            setterSymbol: accessorSetterSymbol,
            propertyType: propertyType,
            // Only a genuine class/object member can be overridden and needs
            // virtual dispatch inside `get`; extension receivers resolve
            // statically, so keep them off the dispatch-probe path.
            ownerType: extensionReceiverType == nil ? receiverTypes.first : nil
        )

        let wrapperName = interner.intern("kk_kproperty_delegate_stub_\(propertySymbol.rawValue)")
        let wrapperFQName = [wrapperName]
        let getName = interner.intern("get")
        let setName = interner.intern("set")
        let getDelegateName = interner.intern("getDelegate")
        let getterMethodSymbol: SymbolID
        let setterMethodSymbol: SymbolID?
        let getDelegateMethodSymbol: SymbolID
        let wrapperSymbol: SymbolID
        if let existing = sema.symbols.lookup(fqName: wrapperFQName) {
            wrapperSymbol = existing
            guard let getter = sema.symbols.lookup(fqName: wrapperFQName + [getName]),
                  let getDelegate = sema.symbols.lookup(fqName: wrapperFQName + [getDelegateName])
            else { return nil }
            getterMethodSymbol = getter
            getDelegateMethodSymbol = getDelegate
            setterMethodSymbol = shape.isMutable
                ? sema.symbols.lookup(fqName: wrapperFQName + [setName])
                : nil
        } else {
            wrapperSymbol = sema.symbols.define(
                kind: .class, name: wrapperName, fqName: wrapperFQName,
                declSite: nil, visibility: .private, flags: [.synthetic]
            )
            sema.symbols.setDirectSupertypes([interfaceSymbol], for: wrapperSymbol)
            sema.types.setNominalDirectSupertypes([interfaceSymbol], for: wrapperSymbol)
            sema.symbols.setSupertypeTypeArgs(referenceArgs, for: wrapperSymbol, supertype: interfaceSymbol)
            sema.types.setNominalSupertypeTypeArgs(referenceArgs, for: wrapperSymbol, supertype: interfaceSymbol)
            let itableSlots = Dictionary(
                uniqueKeysWithValues: interfaceSymbols.enumerated().map { index, symbol in
                    (symbol, index)
                }
            )
            sema.symbols.setNominalLayout(
                NominalLayout(
                    objectHeaderWords: 2,
                    instanceFieldCount: 0,
                    instanceSizeWords: 2,
                    fieldOffsets: [:],
                    vtableSlots: [:],
                    itableSlots: itableSlots,
                    vtableSize: 0,
                    itableSize: interfaceSymbols.count,
                    superClass: nil
                ),
                for: wrapperSymbol
            )
            driver.ctx.appendGeneratedCallableDecl(
                arena.appendDecl(.nominalType(KIRNominalType(symbol: wrapperSymbol)))
            )
            getterMethodSymbol = definePropertyReferenceMethod(
                name: "get",
                wrapperSymbol: wrapperSymbol,
                wrapperFQName: wrapperFQName,
                parameterTypes: receiverTypes,
                returnType: propertyType,
                canThrow: true,
                sema: sema,
                interner: interner
            )
            setterMethodSymbol = shape.isMutable
                ? definePropertyReferenceMethod(
                    name: "set",
                    wrapperSymbol: wrapperSymbol,
                    wrapperFQName: wrapperFQName,
                    parameterTypes: receiverTypes + [propertyType],
                    returnType: sema.types.unitType,
                    canThrow: true,
                    sema: sema,
                    interner: interner
                )
                : nil
            getDelegateMethodSymbol = definePropertyReferenceMethod(
                name: "getDelegate",
                wrapperSymbol: wrapperSymbol,
                wrapperFQName: wrapperFQName,
                parameterTypes: receiverTypes,
                returnType: sema.types.nullableAnyType,
                canThrow: true,
                sema: sema,
                interner: interner
            )
            let wrapperType = sema.types.make(.classType(ClassType(
                classSymbol: wrapperSymbol, args: [], nullability: .nonNull
            )))
            emitPropertyReferenceGetter(
                methodSymbol: getterMethodSymbol,
                wrapperType: wrapperType,
                accessor: accessor,
                captureFields: [],
                fieldOffsets: [:],
                sema: sema,
                arena: arena,
                interner: interner
            )
            if let setterMethodSymbol, let accessorSetterSymbol {
                emitDelegatedStubSetter(
                    methodSymbol: setterMethodSymbol,
                    wrapperType: wrapperType,
                    setterSymbol: accessorSetterSymbol,
                    sema: sema,
                    arena: arena,
                    interner: interner
                )
            }
            emitPropertyReferenceGetDelegate(
                methodSymbol: getDelegateMethodSymbol,
                wrapperType: wrapperType,
                shape: shape,
                accessor: accessor,
                captureFields: [],
                fieldOffsets: [:],
                sema: sema,
                arena: arena,
                interner: interner
            )
        }

        let intType = sema.types.intType
        let slotCountExpr = arena.appendExpr(.intLiteral(2), type: intType)
        instructions.append(.constValue(result: slotCountExpr, value: .intLiteral(2)))
        let classID = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: wrapperSymbol, sema: sema, interner: interner
        )
        let classIDExpr = arena.appendExpr(.intLiteral(classID), type: intType)
        instructions.append(.constValue(result: classIDExpr, value: .intLiteral(classID)))
        let wrapperValue = arena.appendTemporary(type: boundType)
        instructions.append(.call(
            callee: interner.intern("kk_object_new"),
            arguments: [slotCountExpr, classIDExpr],
            result: wrapperValue,
            canThrow: false
        ))
        registerPropertyReferenceInterfaces(
            wrapperValue: wrapperValue,
            wrapperSymbol: wrapperSymbol,
            interfaceSymbols: interfaceSymbols,
            getterMethodSymbol: getterMethodSymbol,
            setterMethodSymbol: setterMethodSymbol,
            getDelegateMethodSymbol: getDelegateMethodSymbol,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )

        let nameExpr = arena.appendExpr(.stringLiteral(propertyName), type: sema.types.stringType)
        instructions.append(.constValue(result: nameExpr, value: .stringLiteral(propertyName)))
        let returnTypeName = interner.intern(
            sema.types.displayName(of: propertyType, symbols: sema.symbols, interner: interner)
        )
        let returnTypeExpr = arena.appendExpr(.stringLiteral(returnTypeName), type: sema.types.stringType)
        instructions.append(.constValue(result: returnTypeExpr, value: .stringLiteral(returnTypeName)))
        let arityExpr = arena.appendExpr(.intLiteral(Int64(receiverTypes.count)), type: intType)
        instructions.append(.constValue(result: arityExpr, value: .intLiteral(Int64(receiverTypes.count))))
        let taggedValue = arena.appendTemporary(type: boundType)
        instructions.append(.call(
            callee: interner.intern("kk_callable_ref_tag_kproperty"),
            arguments: [wrapperValue, nameExpr, returnTypeExpr, arityExpr],
            result: taggedValue,
            canThrow: false
        ))
        emitCallableReferenceIdentity(
            callableExpr: taggedValue,
            targetSymbol: getterSymbol,
            captures: [],
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        driver.ctx.registerCallableValue(
            taggedValue,
            symbol: getterMethodSymbol,
            callee: getName,
            captureArguments: [wrapperValue],
            hasClosureParam: false
        )
        registerCallableReflection(
            value: taggedValue,
            callableSymbol: getterMethodSymbol,
            callableName: getName,
            targetSymbol: accessor.propertySymbol,
            parameterTypes: receiverTypes,
            returnType: propertyType,
            captures: [wrapperValue],
            receiverCount: receiverTypes.count,
            setterSymbol: setterMethodSymbol,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        return taggedValue
    }

    /// `set` on a delegated stub forwards every receiver parameter plus the
    /// trailing value to the real setter accessor. The accessor body calls
    /// `Delegate.setValue`, which can throw, so the call keeps its thrown
    /// channel rather than `emitPropertyReferenceSetter`'s non-throwing form.
    private func emitDelegatedStubSetter(
        methodSymbol: SymbolID,
        wrapperType: TypeID,
        setterSymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner
    ) {
        let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: methodSymbol)
        let parameterSymbols = sema.symbols.functionSignature(for: methodSymbol)?.valueParameterSymbols ?? []
        let params = [KIRParameter(symbol: receiverSymbol, type: wrapperType)] + parameterSymbols.compactMap { symbol in
            sema.symbols.propertyType(for: symbol).map { KIRParameter(symbol: symbol, type: $0) }
        }
        let receiverExpr = arena.appendExpr(.symbolRef(receiverSymbol), type: wrapperType)
        var body: [KIRInstruction] = [.beginBlock, .constValue(result: receiverExpr, value: .symbolRef(receiverSymbol))]
        var callArgs: [KIRExprID] = []
        for parameter in params.dropFirst() {
            let parameterExpr = arena.appendExpr(.symbolRef(parameter.symbol), type: parameter.type)
            body.append(.constValue(result: parameterExpr, value: .symbolRef(parameter.symbol)))
            callArgs.append(parameterExpr)
        }
        let result = arena.appendTemporary(type: sema.types.unitType)
        body.append(.call(symbol: setterSymbol, callee: interner.intern("set"), arguments: callArgs, result: result, canThrow: true))
        body.append(.returnUnit)
        body.append(.endBlock)
        driver.ctx.appendGeneratedCallableDecl(arena.appendDecl(.function(KIRFunction(
            symbol: methodSymbol,
            name: interner.intern("set"),
            params: params,
            returnType: sema.types.unitType,
            body: body,
            isSuspend: false,
            isInline: false
        ))))
    }
}
