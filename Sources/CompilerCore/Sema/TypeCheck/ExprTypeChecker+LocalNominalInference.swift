extension ExprTypeChecker {
    func inferLocalNominalDeclExpr(
        _ id: ExprID,
        declID: DeclID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        guard let decl = ast.arena.decl(declID) else {
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        // A local nominal can share its name with a file-scope declaration;
        // its FQ name gets a per-expression prefix so `<init>` and member
        // lookups (`lookupAll(ownerFQ + [member])`) can never collide.
        let fqNamePrefix = [interner.intern("__localdecl_\(id.rawValue)")]
        switch decl {
        case let .objectDecl(objectDecl):
            driver.diagnoseLocalValueOrClassifierRedeclaration(
                named: objectDecl.name,
                expression: id,
                range: range,
                ctx: ctx
            )
            let objectSymbol = ensureObjectLiteralSymbol(
                declID: declID,
                objectDecl: objectDecl,
                superTypes: objectDecl.superTypes,
                fqNamePrefix: fqNamePrefix,
                symbolKind: .object,
                ctx: ctx,
                locals: &locals
            )
            sema.symbols.insertFlags(.localDeclSynthetic, for: objectSymbol)
            let objectType = objectLiteralType(for: objectSymbol, sema: sema)
            ctx.scope.insert(objectSymbol)
            locals[objectDecl.name] = (objectType, objectSymbol, false, true)
            sema.bindings.bindIdentifier(id, symbol: objectSymbol)
            // `exprTypes[id]` feeds the object instance's KIR arena type in
            // `lowerStoredObjectLiteralExpr` — bind it to the object type
            // (not `unit`) even though the decl statement itself yields Unit
            // to its enclosing block.
            sema.bindings.bindExprType(id, type: objectType)
            return sema.types.unitType

        case let .classDecl(classDecl):
            driver.diagnoseLocalValueOrClassifierRedeclaration(
                named: classDecl.name,
                expression: id,
                range: range,
                ctx: ctx
            )
            let classSymbol = ensureLocalClassSymbol(
                declID: declID,
                classDecl: classDecl,
                fqNamePrefix: fqNamePrefix,
                ctx: ctx,
                locals: &locals
            )
            sema.symbols.insertFlags(.localDeclSynthetic, for: classSymbol)
            let typeArgs = sema.types.nominalTypeParameterSymbols(for: classSymbol).map { typeParameterSymbol in
                TypeArg.invariant(sema.types.make(.typeParam(TypeParamType(symbol: typeParameterSymbol))))
            }
            let classType = sema.types.make(.classType(ClassType(
                classSymbol: classSymbol,
                args: typeArgs,
                nullability: .nonNull
            )))
            // Scope insertion lives here rather than inside
            // `ensureLocalClassSymbol`: member-function bodies are
            // type-checked twice under different scopes, and the early
            // return on an already-bound declID would skip it.
            ctx.scope.insert(classSymbol)
            locals[classDecl.name] = (classType, classSymbol, false, true)
            sema.bindings.bindIdentifier(id, symbol: classSymbol)
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            _ = range
            return sema.types.unitType

        case let .typeAliasDecl(typeAliasDecl):
            driver.diagnoseLocalValueOrClassifierRedeclaration(
                named: typeAliasDecl.name,
                expression: id,
                range: range,
                ctx: ctx
            )
            let aliasSymbol = ensureLocalTypeAliasSymbol(
                declID: declID,
                typeAliasDecl: typeAliasDecl,
                fqNamePrefix: fqNamePrefix,
                ctx: ctx
            )
            sema.symbols.insertFlags(.localDeclSynthetic, for: aliasSymbol)
            ctx.scope.insert(aliasSymbol)
            sema.bindings.bindIdentifier(id, symbol: aliasSymbol)
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType

        default:
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType
        }
    }

    private func ensureLocalTypeAliasSymbol(
        declID: DeclID,
        typeAliasDecl: TypeAliasDecl,
        fqNamePrefix: [InternedString],
        ctx: TypeInferenceContext
    ) -> SymbolID {
        let sema = ctx.sema

        let pendingRecheck = driver.pendingLocalNominalRechecks.remove(declID) != nil
        if let existing = sema.bindings.declSymbols[declID],
           !pendingRecheck
        {
            return existing
        }
        if driver.sourceManager?.origin(of: ctx.currentFileID)?.isBundledStdlib != true {
            driver.localNominalDeclChecks.append(declID)
        }

        let aliasFQName = fqNamePrefix + [typeAliasDecl.name]
        let aliasSymbol: SymbolID
        if let existing = sema.bindings.declSymbols[declID] {
            aliasSymbol = existing
        } else {
            aliasSymbol = sema.symbols.define(
                kind: .typeAlias,
                name: typeAliasDecl.name,
                fqName: aliasFQName,
                declSite: typeAliasDecl.range,
                visibility: .private,
                flags: [.synthetic]
            )
            sema.bindings.bindDecl(declID, symbol: aliasSymbol)
        }
        sema.symbols.setSourceFileID(ctx.currentFileID, for: aliasSymbol)

        resolveLocalTypeAliasUnderlying(
            typeAliasDecl,
            aliasSymbol: aliasSymbol,
            aliasFQName: aliasFQName,
            lexicalScope: ctx.scope,
            ctx: ctx
        )
        return aliasSymbol
    }

    private func collectLocalNestedTypeAliases(
        _ aliases: [TypeAliasDecl],
        ownerFQName: [InternedString],
        ownerSymbol: SymbolID,
        ownerScope: Scope,
        ctx: TypeInferenceContext
    ) {
        let sema = ctx.sema
        for alias in aliases {
            let aliasFQName = ownerFQName + [alias.name]
            let aliasSymbol = sema.symbols.define(
                kind: .typeAlias,
                name: alias.name,
                fqName: aliasFQName,
                declSite: alias.range,
                visibility: Visibility(modifiers: alias.modifiers),
                flags: [.synthetic]
            )
            sema.symbols.setSourceFileID(ctx.currentFileID, for: aliasSymbol)
            sema.symbols.setParentSymbol(ownerSymbol, for: aliasSymbol)
            resolveLocalTypeAliasUnderlying(
                alias,
                aliasSymbol: aliasSymbol,
                aliasFQName: aliasFQName,
                lexicalScope: ownerScope,
                ctx: ctx
            )
        }
    }

    private func resolveLocalTypeAliasUnderlying(
        _ typeAliasDecl: TypeAliasDecl,
        aliasSymbol: SymbolID,
        aliasFQName: [InternedString],
        lexicalScope: Scope,
        ctx: TypeInferenceContext
    ) {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let localTypeParameters = DataFlowSemaPhase().registerTypeAliasTypeParameters(
            typeAliasDecl.typeParams,
            aliasSymbol: aliasSymbol,
            parentFQName: aliasFQName,
            declSite: typeAliasDecl.range,
            symbols: sema.symbols,
            interner: interner,
            diagnostics: sema.diagnostics
        )
        let aliasScope = BlockScope(parent: lexicalScope, symbols: sema.symbols)
        for typeParameterSymbol in localTypeParameters.values {
            aliasScope.insert(typeParameterSymbol)
        }
        if typeAliasDecl.underlyingType == nil {
            sema.diagnostics.error(
                "KSWIFTK-SEMA-0061",
                "Type alias '\(interner.resolve(typeAliasDecl.name))' must have a right-hand side type.",
                range: typeAliasDecl.range
            )
        } else if let underlyingTypeRef = typeAliasDecl.underlyingType {
            let resolved = driver.helpers.resolveTypeRef(
                underlyingTypeRef,
                ast: ast,
                sema: sema,
                interner: interner,
                scope: aliasScope,
                diagnostics: sema.diagnostics,
                inferenceContext: ctx,
                usageRange: typeAliasDecl.range
            )
            if resolved != sema.types.errorType {
                sema.symbols.setTypeAliasUnderlyingType(resolved, for: aliasSymbol)
            }
        }
    }

    private func ensureLocalClassSymbol(
        declID: DeclID,
        classDecl: ClassDecl,
        fqNamePrefix: [InternedString],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> SymbolID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner

        let pendingRecheck = driver.pendingLocalNominalRechecks.remove(declID) != nil
        if let existing = sema.bindings.declSymbols[declID],
           !pendingRecheck
        {
            return existing
        }
        if driver.sourceManager?.origin(of: ctx.currentFileID)?.isBundledStdlib != true {
            driver.localNominalDeclChecks.append(declID)
        }

        let outerLocalsSnapshot = locals
        let outerSymbols = Set(outerLocalsSnapshot.values.map(\.symbol))

        var outerReceiverOwners: Set<SymbolID> = []
        var pendingOuterReceiverOwners: [SymbolID] = []
        if let enclosingClassSymbol = ctx.enclosingClassSymbol {
            pendingOuterReceiverOwners.append(enclosingClassSymbol)
        } else if let implicitReceiverType = ctx.implicitReceiverType,
                  let receiverSymbol = driver.helpers.nominalSymbol(
                      of: sema.types.makeNonNullable(implicitReceiverType),
                      types: sema.types
                  )
        {
            pendingOuterReceiverOwners.append(receiverSymbol)
        }
        while let ownerSymbol = pendingOuterReceiverOwners.popLast() {
            guard outerReceiverOwners.insert(ownerSymbol).inserted else {
                continue
            }
            pendingOuterReceiverOwners.append(contentsOf: sema.symbols.directSupertypes(for: ownerSymbol))
        }
        let outerReceiverPropertySymbols = Set(
            sema.symbols.allSymbols().compactMap { symbol -> SymbolID? in
                guard symbol.kind == .property,
                      let ownerSymbol = sema.symbols.parentSymbolIfKnown(for: symbol.id),
                      outerReceiverOwners.contains(ownerSymbol),
                      sema.symbols.symbol(ownerSymbol)?.kind == .class,
                      !symbol.flags.contains(.mutable)
                else {
                    return nil
                }
                return symbol.id
            }
        )
        let captureOuterSymbols = outerSymbols
            .union(outerReceiverPropertySymbols)
            .union(ctx.outerReceiverTypes.compactMap(\.symbol))
            .union(ctx.implicitReceiverStack.map(\.symbol))
            .union(driver.helpers.lexicalTypeParameterSymbols(in: ctx).filter {
                sema.symbols.symbol($0)?.flags.contains(.reifiedTypeParameter) == true
            })

        let classFQName = fqNamePrefix + [classDecl.name]
        var classFlags: SymbolFlags = [.synthetic]
        classFlags.formUnion(SymbolFlags(modifiers: classDecl.modifiers))
        if classDecl.modifiers.contains(.abstract) {
            classFlags.insert(.openType)
        }
        if classDecl.modifiers.contains(.sealed) {
            classFlags.formUnion([.abstractType, .openType])
        }
        let classSymbol: SymbolID
        if let existing = sema.bindings.declSymbols[declID] {
            classSymbol = existing
        } else {
            classSymbol = sema.symbols.define(
                kind: .class,
                name: classDecl.name,
                fqName: classFQName,
                declSite: classDecl.range,
                visibility: .private,
                flags: classFlags
            )
            sema.bindings.bindDecl(declID, symbol: classSymbol)
        }
        if let enclosingClassSymbol = ctx.enclosingClassSymbol {
            sema.symbols.setParentSymbol(enclosingClassSymbol, for: classSymbol)
        }
        sema.symbols.setSourceFileID(ctx.currentFileID, for: classSymbol)

        let sourceFile = ast.file(for: ctx.currentFileID)
        var enclosingTypeParameters: [InternedString: SymbolID] = [:]
        for typeParameterSymbol in driver.helpers.lexicalTypeParameterSymbols(in: ctx) {
            guard let name = sema.symbols.symbol(typeParameterSymbol)?.name,
                  let visibleSymbol = driver.helpers.resolveTypeParameterSymbol(
                      name, scope: ctx.scope, sema: sema
                  )
            else {
                continue
            }
            enclosingTypeParameters[name] = visibleSymbol
        }
        let typeParameterResult = DataFlowSemaPhase().registerNominalTypeParameters(
            classDecl.typeParams,
            ownerSymbol: classSymbol,
            fqName: classFQName,
            namespacePrefix: "$localClass",
            declSite: classDecl.range,
            currentPackageFQName: sourceFile?.packageFQName,
            imports: sourceFile?.imports ?? [],
            ast: ast,
            symbols: sema.symbols,
            types: sema.types,
            interner: interner,
            sourceManager: ctx.visibilityChecker.sourceManager,
            diagnostics: sema.diagnostics,
            enclosingTypeParameters: enclosingTypeParameters
        )
        let classTypeArgs = typeParameterResult.symbols.map { typeParameterSymbol in
            TypeArg.invariant(sema.types.make(.typeParam(TypeParamType(symbol: typeParameterSymbol))))
        }
        let classType = sema.types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: classTypeArgs,
            nullability: .nonNull
        )))
        let classScope = ClassMemberScope(
            parent: ctx.scope,
            symbols: sema.symbols,
            ownerSymbol: classSymbol,
            thisType: classType
        )
        classScope.insert(classSymbol)
        for typeParameterSymbol in typeParameterResult.symbols {
            classScope.insert(typeParameterSymbol)
        }
        collectLocalNestedTypeAliases(
            classDecl.nestedTypeAliases,
            ownerFQName: classFQName,
            ownerSymbol: classSymbol,
            ownerScope: classScope,
            ctx: ctx
        )
        // A function-local nominal captures the enclosing function's receiver
        // *value*. The enclosing class's outer-receiver entry normally carries
        // the class symbol — a `this@Class` label placeholder — which cannot
        // root the smart-cast flow reference, because those are keyed by the
        // receiver value symbol (`receiverParameterSymbol(for:)`). Resolve that
        // entry to the enclosing function's receiver parameter so stable
        // property smart casts on the captured `this` survive into the local
        // nominal's member bodies (KUU-4605).
        //
        // Only rewrite when `receiverParameterSymbol(for:)` denotes the
        // enclosing class instance. That holds for a plain member function —
        // including when the local class sits inside a lambda that has its own
        // receiver, because a lambda does not change `enclosingFunctionSymbol`
        // — whose declared receiver type is the enclosing class. It does NOT
        // hold for a member *extension* function (its `this` is the extension
        // receiver, e.g. `String`, not the `this@Outer` dispatch receiver) or
        // for a receiver-less local function (which has no `this` at all, so
        // `receiverParameterSymbol(for:)` would name a non-existent receiver
        // and the instance would not be captured). Rewriting there would bind
        // the outer entry to the wrong value, so skip it. Default to skipping:
        // only a concrete class receiver type matching the enclosing class
        // proves the receiver parameter is the captured instance.
        var memberOuterReceiverTypes = ctx.outerReceiverTypes
        if let enclosingFunctionSymbol = ctx.enclosingFunctionSymbol,
           let enclosingClassSymbol = ctx.enclosingClassSymbol
        {
            var receiverIsEnclosingClassInstance = false
            if let signature = sema.symbols.functionSignature(for: enclosingFunctionSymbol),
               let receiverType = signature.receiverType,
               case let .classType(receiverClass) = sema.types.kind(of: receiverType)
            {
                receiverIsEnclosingClassInstance = receiverClass.classSymbol == enclosingClassSymbol
            }
            if receiverIsEnclosingClassInstance {
                let receiverValueSymbol = SyntheticSymbolScheme.receiverParameterSymbol(for: enclosingFunctionSymbol)
                for index in memberOuterReceiverTypes.indices {
                    let entry = memberOuterReceiverTypes[index]
                    guard entry.symbol == enclosingClassSymbol,
                          case let .classType(entryClassType) = sema.types.kind(of: entry.type),
                          entryClassType.classSymbol == enclosingClassSymbol
                    else {
                        continue
                    }
                    memberOuterReceiverTypes[index].symbol = receiverValueSymbol
                }
            }
        }
        let classCtx = ctx.copying(outerReceiverTypes: memberOuterReceiverTypes)
            .withoutSuspensionContext().withOuterReceiver(
                label: classDecl.name,
                type: classType
            ).copying(
                scope: classScope,
                implicitReceiverType: classType,
                enclosingClassSymbol: classSymbol
            )

        var lexicalEnclosingFQNames: [[InternedString]] = []
        var lexicalScope: Scope? = ctx.scope
        while let scope = lexicalScope as? BaseScope {
            if let memberScope = scope as? ClassMemberScope,
               let owner = sema.symbols.symbol(memberScope.owner) {
                lexicalEnclosingFQNames.append(owner.fqName)
            }
            lexicalScope = scope.parent
        }

        var lexicalReceiverSymbols = Set(ctx.outerReceiverTypes.compactMap(\.symbol))
        lexicalReceiverSymbols.formUnion(ctx.implicitReceiverStack.map(\.symbol))
        if let implicitReceiverType = ctx.implicitReceiverType,
           let receiverSymbol = driver.helpers.nominalSymbol(
               of: sema.types.makeNonNullable(implicitReceiverType),
               types: sema.types
           ) {
            lexicalReceiverSymbols.insert(receiverSymbol)
        }

        let declIsBundledStdlib = driver.sourceManager?
            .origin(of: ctx.currentFileID)?.isBundledStdlib == true
        var directSuperSymbols: [SymbolID] = []
        directSuperSymbols.reserveCapacity(classDecl.superTypeEntries.count)
        var directSuperTypeArgs: [SymbolID: [TypeArg]] = [:]
        var directSuperTypes: [TypeID] = []
        for entry in classDecl.superTypeEntries {
            if entry.hasConstructorCallSyntax,
               !classDecl.hasPrimaryConstructorSyntax,
               !classDecl.secondaryConstructors.isEmpty,
               !declIsBundledStdlib
            {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0474",
                    "supertype initialization is impossible without a primary constructor.",
                    range: entry.range ?? classDecl.range
                )
            }
            let resolved = driver.helpers.resolveTypeRef(
                entry.typeRef,
                ast: ast,
                sema: sema,
                interner: interner,
                scope: classScope,
                diagnostics: ctx.sema.diagnostics,
                usageRange: entry.range ?? classDecl.range
            )
            let resolvedNominal = driver.helpers.nominalFunctionInterfaceSupertype(
                for: resolved,
                owner: classSymbol,
                sema: sema,
                interner: interner
            )
            directSuperTypes.append(resolvedNominal)
            if case let .classType(classType) = sema.types.kind(of: resolvedNominal) {
                if classType.classSymbol == classSymbol {
                    ctx.sema.diagnostics.error(
                        "KSWIFTK-SEMA-SUPER-CYCLE",
                        "Cyclic supertype reference involving \(interner.resolve(classDecl.name)); the edge is ignored.",
                        range: classDecl.range
                    )
                    continue
                }
                if !entry.hasConstructorCallSyntax,
                   entry.delegateExpression == nil,
                   sema.symbols.symbol(classType.classSymbol)?.kind == .class,
                   classDecl.hasPrimaryConstructorSyntax || classDecl.secondaryConstructors.isEmpty,
                   !declIsBundledStdlib
                {
                    ctx.sema.diagnostics.error(
                        "KSWIFTK-SEMA-0436",
                        "this type has a constructor, so it must be initialized here.",
                        range: entry.range ?? classDecl.range
                    )
                }
                if entry.hasConstructorCallSyntax,
                   !declIsBundledStdlib,
                   sema.symbols.symbol(classType.classSymbol)?.kind == .interface
                {
                    ctx.sema.diagnostics.error(
                        "KSWIFTK-SEMA-0481",
                        "this type does not have a constructor.",
                        range: entry.range ?? classDecl.range
                    )
                }
                directSuperSymbols.append(classType.classSymbol)
                directSuperTypeArgs[classType.classSymbol] = sema.types
                    .allTypeArguments(for: classType)
                DataFlowSemaPhase().validateInnerClassSupertypeReceiver(
                    resolvedSymbol: classType.classSymbol,
                    context: .lexical,
                    declRange: classDecl.range,
                    declSymbol: classSymbol,
                    enclosingClassScopes: Array(lexicalEnclosingFQNames.reversed()),
                    lexicalReceiverSymbols: lexicalReceiverSymbols,
                    symbols: sema.symbols,
                    types: sema.types,
                    diagnostics: ctx.sema.diagnostics,
                    sourceManager: ctx.visibilityChecker.sourceManager,
                    interner: interner
                )
            }
        }
        let concreteClassSupers = directSuperSymbols.filter {
            sema.symbols.symbol($0)?.kind != .interface
        }
        if concreteClassSupers.count > 1 {
            let classNames = concreteClassSupers.compactMap { sema.symbols.symbol($0)?.fqName.last }
                .map { interner.resolve($0) }
                .joined(separator: ", ")
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0170",
                "Local class '\(interner.resolve(classDecl.name))' cannot inherit from more than one class. Found: \(classNames).",
                range: classDecl.range
            )
        }
        sema.symbols.setDirectSupertypes(directSuperSymbols, for: classSymbol)
        sema.types.setNominalDirectSupertypes(directSuperSymbols, for: classSymbol)
        for (superSymbol, args) in directSuperTypeArgs {
            sema.symbols.setSupertypeTypeArgs(args, for: classSymbol, supertype: superSymbol)
            sema.types.setNominalSupertypeTypeArgs(args, for: classSymbol, supertype: superSymbol)
        }

        let inheritance = DataFlowSemaPhase()
        for (entry, interfaceType) in zip(classDecl.superTypeEntries, directSuperTypes) {
            guard let delegateExpression = entry.delegateExpression else { continue }
            inheritance.registerClassDelegation(
                delegateExpression: delegateExpression,
                interfaceType: interfaceType,
                classSymbol: classSymbol,
                range: classDecl.range,
                symbols: sema.symbols,
                types: sema.types,
                diagnostics: sema.diagnostics,
                interner: interner
            )
        }


        let initName = interner.intern("<init>")
        let hasPrimaryConstructor = classDecl.hasPrimaryConstructorSyntax || classDecl.secondaryConstructors.isEmpty
        var constructorHeaders: [(params: [ValueParamDecl], range: SourceRange, modifiers: Modifiers)] = []
        if hasPrimaryConstructor {
            constructorHeaders.append((classDecl.primaryConstructorParams, classDecl.range, classDecl.primaryConstructorModifiers))
        }
        constructorHeaders.append(contentsOf: classDecl.secondaryConstructors.map { ($0.valueParams, $0.range, $0.modifiers) })
        var constructorSymbols: [SymbolID] = []
        let dataFlow = DataFlowSemaPhase()
        for header in constructorHeaders {
            let ctorVisibilityDetail = dataFlow.constructorVisibilityDetail(
                explicitModifiers: header.modifiers,
                classKind: .class,
                isSealedClass: classDecl.modifiers.contains(.sealed),
                declarationVisibility: .private
            )
            var ctorFlags: SymbolFlags = [.synthetic]
            if ctorVisibilityDetail.isInheritedFromOwner {
                ctorFlags.insert(.constructorVisibilityInherited)
            }
            let ctorFQName = classFQName + [initName]
            let ctorSymbol: SymbolID
            if let existingCtor = sema.symbols.lookupAll(fqName: ctorFQName).first(where: { id in
                guard let sym = sema.symbols.symbol(id) else { return false }
                return sym.kind == .constructor
                    && sema.symbols.parentSymbol(for: id) == classSymbol
                    && sym.declSite == header.range
            }) {
                ctorSymbol = existingCtor
            } else {
                ctorSymbol = sema.symbols.define(
                    kind: .constructor,
                    name: initName,
                    fqName: ctorFQName,
                    declSite: header.range,
                    visibility: ctorVisibilityDetail.visibility,
                    flags: ctorFlags
                )
            }
            constructorSymbols.append(ctorSymbol)
            sema.symbols.setParentSymbol(classSymbol, for: ctorSymbol)
            var paramTypes: [TypeID] = []
            var paramSymbols: [SymbolID] = []
            for param in header.params {
                let parameterCtx = driver.helpers.primaryConstructorParameterOptInContext(
                    param, ctx: driver.helpers.localFunctionOptInContext(classCtx).with(currentDeclSymbol: ctorSymbol)
                )
                let paramType: TypeID = if let typeRefID = param.type {
                    driver.helpers.resolveTypeRef(
                        typeRefID,
                        ast: ast,
                        sema: sema,
                        interner: interner,
                        scope: classScope,
                        diagnostics: ctx.sema.diagnostics,
                        inferenceContext: parameterCtx,
                        usageRange: header.range
                    )
                } else {
                    sema.types.anyType
                }
                let paramSymbol = sema.symbols.define(
                    kind: .valueParameter,
                    name: param.name,
                    fqName: classFQName + [initName, interner.intern("$\(ctorSymbol.rawValue)"), param.name],
                    declSite: header.range,
                    visibility: .private,
                    flags: [.synthetic]
                )
                sema.symbols.setParentSymbol(ctorSymbol, for: paramSymbol)
                sema.symbols.setPropertyType(paramType, for: paramSymbol)
                paramTypes.append(paramType)
                paramSymbols.append(paramSymbol)
            }
            sema.symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: classType,
                    parameterTypes: paramTypes,
                    returnType: classType,
                    valueParameterSymbols: paramSymbols,
                    valueParameterHasDefaultValues: header.params.map(\.hasDefaultValue),
                    valueParameterIsVararg: header.params.map(\.isVararg),
                    typeParameterSymbols: typeParameterResult.symbols,
                    classTypeParameterCount: typeParameterResult.symbols.count
                ),
                for: ctorSymbol
            )
        }

        let annotationSema = DataFlowSemaPhase()
        if hasPrimaryConstructor, let primaryConstructor = constructorSymbols.first {
            annotationSema.registerAnnotations(
                classDecl.primaryConstructorAnnotations,
                symbol: primaryConstructor,
                declRange: classDecl.range,
                sourceFileID: ctx.currentFileID,
                sourceFile: sourceFile,
                sourceManager: ctx.visibilityChecker.sourceManager,
                interner: interner,
                symbols: sema.symbols,
                diagnostics: sema.diagnostics
            )
            driver.declChecker.typeCheckPrimaryConstructorAnnotationFactories(
                classDecl.primaryConstructorAnnotations,
                symbol: primaryConstructor,
                ctx: classCtx
            )
        }
        for (index, constructor) in classDecl.secondaryConstructors.enumerated() {
            let symbolIndex = index + (hasPrimaryConstructor ? 1 : 0)
            guard constructorSymbols.indices.contains(symbolIndex) else { continue }
            annotationSema.registerAnnotations(
                constructor.annotations,
                symbol: constructorSymbols[symbolIndex],
                declRange: annotationSema.declarationRangeIncludingAnnotationTokens(
                    constructor.annotations, declarationRange: constructor.range
                ),
                sourceFileID: ctx.currentFileID,
                sourceFile: sourceFile,
                sourceManager: ctx.visibilityChecker.sourceManager,
                interner: interner,
                symbols: sema.symbols,
                diagnostics: sema.diagnostics
            )
        }

        let propertySymbolsByDecl = registerLocalNominalMemberProperties(
            classDecl.memberProperties,
            ownerFQName: classFQName,
            ownerSymbol: classSymbol,
            markAsSynthetic: !classDecl.modifiers.contains(.data),
            primaryConstructorParameters: Dictionary(uniqueKeysWithValues: zip(
                classDecl.memberProperties.filter {
                    guard case let .propertyDecl(property) = ast.arena.decl($0) else { return false }
                    return property.isSynthesizedPrimaryConstructorProperty
                },
                classDecl.primaryConstructorParams.filter(\.isProperty)
            )),
            ctx: classCtx
        )
        for propertySymbol in propertySymbolsByDecl.values {
            classScope.insert(propertySymbol)
        }
        let uncollectedNestedClasses = classDecl.nestedClasses.filter { sema.bindings.declSymbols[$0] == nil }
        let uncollectedNestedObjects = classDecl.nestedObjects.filter { sema.bindings.declSymbols[$0] == nil }
        for nestedDeclID in classDecl.nestedClasses + classDecl.nestedObjects {
            if let existingNested = sema.bindings.declSymbols[nestedDeclID] {
                classScope.insert(existingNested)
            }
        }
        var nestedLocalTypeParameters = enclosingTypeParameters
        for (name, sym) in typeParameterResult.localMap {
            nestedLocalTypeParameters[name] = sym
        }
        if let compilationContext = driver.compilationContext,
           !uncollectedNestedClasses.isEmpty || !uncollectedNestedObjects.isEmpty
        {
            DataFlowSemaPhase().collectMemberHeaders(
                members: MemberDeclarations(
                    functions: [],
                    properties: [],
                    nestedClasses: uncollectedNestedClasses,
                    nestedObjects: uncollectedNestedObjects
                ),
                owner: OwnerContext(fqName: classFQName, symbol: classSymbol, type: classType),
                sourceFileID: ctx.currentFileID,
                ctx: compilationContext,
                ast: ast,
                symbols: sema.symbols,
                types: sema.types,
                bindings: sema.bindings,
                scope: classScope,
                diagnostics: sema.diagnostics,
                interner: interner,
                classTypeParameterSymbols: typeParameterResult.symbols,
                classLocalTypeParameters: nestedLocalTypeParameters
            )
        }
        let lexicalLocalNominalScopes = outerLocalsSnapshot.values
            .sorted(by: { $0.symbol.rawValue < $1.symbol.rawValue })
            .compactMap { binding -> [InternedString]? in
            guard let localNominal = sema.symbols.symbol(binding.symbol),
                  !localNominal.fqName.isEmpty
            else {
                return nil
            }
            switch localNominal.kind {
            case .class, .interface, .enumClass, .annotationClass:
                return Array(localNominal.fqName.dropLast())
            default:
                return nil
            }
        }
        var nestedEnclosingClassScopes = Array(lexicalEnclosingFQNames.reversed())
        nestedEnclosingClassScopes.append(contentsOf: lexicalLocalNominalScopes)
        nestedEnclosingClassScopes.append(classFQName)
        if sourceFile != nil {
            for nestedDeclID in uncollectedNestedClasses + uncollectedNestedObjects {
                DataFlowSemaPhase().bindInheritanceEdges(
                    declID: nestedDeclID,
                    currentPackage: sourceFile?.packageFQName ?? [],
                    imports: sourceFile?.imports ?? [],
                    enclosingTypeParameters: nestedLocalTypeParameters,
                    enclosingClassScopes: nestedEnclosingClassScopes,
                    ast: ast,
                    symbols: sema.symbols,
                    bindings: sema.bindings,
                    types: sema.types,
                    diagnostics: sema.diagnostics,
                    sourceManager: ctx.visibilityChecker.sourceManager,
                    interner: interner
                )
            }
        }
        sema.bindings.deferAnnotationTargets(declID, lexicalEnclosingFQNames: lexicalEnclosingFQNames)
        DataFlowSemaPhase().registerPrimaryConstructorPropertyAnnotations(
            for: classDecl, ast: ast, symbols: sema.symbols, types: sema.types, bindings: sema.bindings,
            sourceManager: ctx.visibilityChecker.sourceManager, diagnostics: ctx.sema.diagnostics, interner: interner,
            lexicalEnclosingFQNames: lexicalEnclosingFQNames
        )
        if classDecl.modifiers.contains(.data) {
            DataFlowSemaPhase().collectSyntheticDataClassComponentsAndCopy(
                classDecl: classDecl, ast: ast, ownerSymbol: classSymbol,
                ownerFQName: classFQName, ownerType: classType,
                symbols: sema.symbols, types: sema.types,
                scope: classScope, interner: interner,
                diagnostics: ctx.sema.diagnostics,
                ownerIsLocal: true
            )
        }
        let memberFunctionSymbolsByDecl = collectObjectLiteralMemberFunctions(
            classDecl.memberFunctions,
            memberFQNamePrefix: classFQName,
            objectSymbol: classSymbol,
            objectType: classType,
            classTypeParameterSymbols: typeParameterResult.symbols,
            objectScope: classScope,
            ctx: classCtx
        )
        if !pendingRecheck {
            inheritance.synthesizeDelegationForwardingForClass(
                range: classDecl.range,
                memberFunctions: classDecl.memberFunctions,
                memberProperties: classDecl.memberProperties,
                classSymbol: classSymbol,
                classFQName: classFQName,
                symbols: sema.symbols,
                bindings: sema.bindings,
                types: sema.types,
                interner: interner
            )
        }
        for forwardingSymbol in sema.symbols.classDelegationForwardingMethodSymbols(forClass: classSymbol)
            + sema.symbols.classDelegationForwardingPropertySymbols(forClass: classSymbol)
        {
            classScope.insert(forwardingSymbol)
        }
        if classDecl.modifiers.contains(.data) {
            let dataFlow = DataFlowSemaPhase()
            dataFlow.collectSyntheticHashCode(
                ownerSymbol: classSymbol,
                ownerFQName: classFQName, ownerType: classType,
                requireDataTypeFlag: true, symbols: sema.symbols, types: sema.types,
                scope: classScope, interner: interner
            )
            dataFlow.collectSyntheticEquals(
                ownerSymbol: classSymbol,
                ownerFQName: classFQName, ownerType: classType,
                requireDataTypeFlag: true, symbols: sema.symbols, types: sema.types,
                scope: classScope, interner: interner
            )
            dataFlow.collectSyntheticToString(
                ownerSymbol: classSymbol,
                ownerFQName: classFQName,
                ownerType: classType,
                requireDataTypeFlag: true,
                symbols: sema.symbols,
                types: sema.types,
                scope: classScope,
                interner: interner
            )
        }
        if driver.compilationContext?.options.emit.isJVM != true,
           sema.symbols.symbol(classSymbol)?.flags.contains(.valueType) == true,
           sema.symbols.valueClassImplementsInterface(classSymbol)
        {
            let dataFlow = DataFlowSemaPhase()
            dataFlow.collectSyntheticHashCode(
                ownerSymbol: classSymbol,
                ownerFQName: classFQName, ownerType: classType,
                requireDataTypeFlag: false, symbols: sema.symbols, types: sema.types,
                scope: classScope, interner: interner
            )
            dataFlow.collectSyntheticEquals(
                ownerSymbol: classSymbol,
                ownerFQName: classFQName, ownerType: classType,
                requireDataTypeFlag: false, symbols: sema.symbols, types: sema.types,
                scope: classScope, interner: interner
            )
        }
        for ctorSymbol in constructorSymbols {
            classScope.insert(ctorSymbol)
        }
        for nestedClassDeclID in classDecl.nestedClasses {
            driver.declChecker.typeCheckNestedClassDecl(
                declID: nestedClassDeclID,
                ctx: classCtx,
                solver: driver.solver,
                diagnostics: sema.diagnostics,
                baseLocals: outerLocalsSnapshot
            )
        }
        for nestedObjectDeclID in classDecl.nestedObjects {
            driver.declChecker.typeCheckNestedObjectDecl(
                nestedObjectDeclID,
                ctx: classCtx,
                solver: driver.solver,
                diagnostics: sema.diagnostics
            )
        }

        let primaryCtorLocals = outerLocalsSnapshot
            .merging(
                driver.declChecker.primaryConstructorParameterLocals(classDecl: classDecl, ctx: classCtx)
            ) { _, new in new }

        // KUU-4595: an expression-bodied member function keeps the `Any`
        // return placeholder collected above until its body is checked at
        // the end of this pass, but super-delegation arguments, constructor
        // default values, property initializers and `by lazy` lambdas below
        // can already call it. Register each for the same on-demand return
        // inference named members get, seeded with the outer locals the
        // authoritative pass uses so a speculative check binds identical
        // symbols — an unseeded check could resolve an outer local through
        // the member scope and cache that binding permanently. Inferred
        // member properties likewise stay `pending` until this pass (or an
        // on-demand read from an early-inferred function) resolves them.
        let localMemberFunctionCtx = driver.helpers.localFunctionOptInContext(classCtx)
        for functionDeclID in classDecl.memberFunctions {
            driver.registerInferredReturnFunction(
                for: functionDeclID,
                context: localMemberFunctionCtx,
                baseLocals: outerLocalsSnapshot
            )
        }
        for propertyDeclID in classDecl.memberProperties {
            guard case let .propertyDecl(property)? = ast.arena.decl(propertyDeclID),
                  property.type == nil,
                  let symbol = propertySymbolsByDecl[propertyDeclID]
            else { continue }
            driver.pendingPropertyTypes.insert(symbol)
        }
        driver.registerInferredMemberProperties(
            classDecl.memberProperties,
            context: classCtx,
            initialLocals: primaryCtorLocals
        )

        driver.declChecker.typeCheckClassDelegation(
            classDecl,
            symbol: classSymbol,
            ctx: ctx,
            solver: driver.solver,
            diagnostics: sema.diagnostics,
            baseLocals: outerLocalsSnapshot
        )

        driver.declChecker.typeCheckPrimaryConstructorSuperDelegation(
            classDecl,
            symbol: classSymbol,
            ctx: classCtx,
            extraLocals: outerLocalsSnapshot,
            outerReceiversToKeep: ctx.outerReceiverTypes
        )
        driver.declChecker.typeCheckPrimaryConstructorDefaultValues(
            classDecl,
            ctx: classCtx,
            solver: driver.solver,
            diagnostics: ctx.sema.diagnostics,
            baseLocals: outerLocalsSnapshot
        )
        // Member property types must be final before constructor bodies and
        // `init {}` blocks run: registration seeds inference-initialized
        // properties with an `Any` placeholder, and bodies checked against it
        // cannot resolve compound-assignment or other type-directed member
        // operations (KUU-3596). Named classes, named objects, and object
        // literals all check members before init blocks for the same reason.
        typeCheckLocalNominalMemberProperties(
            classDecl.memberProperties,
            propertySymbolsByDecl: propertySymbolsByDecl,
            memberCtx: classCtx,
            initializerLocals: primaryCtorLocals,
            accessorBaseLocals: outerLocalsSnapshot,
            ctx: ctx
        )
        let superclassSymbol = driver.declChecker.constructorSuperclassSymbol(classDecl, ctx: classCtx)
        driver.declChecker.typeCheckSecondaryConstructors(
            classDecl.secondaryConstructors,
            ctx: classCtx,
            solver: driver.solver,
            diagnostics: ctx.sema.diagnostics,
            ownerSymbol: classSymbol,
            hasPrimaryConstructor: hasPrimaryConstructor,
            superclassSymbol: superclassSymbol,
            baseLocals: outerLocalsSnapshot
        )
        driver.declChecker.typeCheckInitBlocks(
            classDecl.initBlocks,
            ctx: classCtx,
            baseLocals: primaryCtorLocals
        )

        var capturedSymbols: Set<SymbolID> = []
        var defaultExprRoots = classDecl.primaryConstructorParams.compactMap(\.defaultValue)
        for constructor in classDecl.secondaryConstructors {
            defaultExprRoots.append(contentsOf: constructor.valueParams.compactMap(\.defaultValue))
            defaultExprRoots.append(contentsOf: constructor.delegationCall?.args.map(\.expr) ?? [])
            capturedSymbols.formUnion(driver.captureAnalyzer.collectCapturedOuterSymbols(
                inBody: constructor.body,
                ast: ast,
                sema: sema,
                outerSymbols: captureOuterSymbols,
                skipNestedClosures: false
            ))
        }
        for functionDeclID in classDecl.memberFunctions {
            guard let functionSymbol = memberFunctionSymbolsByDecl[functionDeclID],
                  let decl = ast.arena.decl(functionDeclID),
                  case let .funDecl(functionDecl) = decl
            else {
                continue
            }
            driver.declChecker.typeCheckFunctionDecl(
                functionDecl,
                symbol: functionSymbol,
                ctx: driver.helpers.localFunctionOptInContext(classCtx)
                    .with(currentDeclSymbol: functionSymbol),
                solver: driver.solver,
                diagnostics: ctx.sema.diagnostics,
                baseLocals: outerLocalsSnapshot
            )
            defaultExprRoots.append(contentsOf: functionDecl.valueParams.compactMap(\.defaultValue))
            capturedSymbols.formUnion(driver.captureAnalyzer.collectCapturedOuterSymbols(
                inBody: functionDecl.body,
                ast: ast,
                sema: sema,
                outerSymbols: captureOuterSymbols,
                skipNestedClosures: false
            ))
        }
        capturedSymbols.formUnion(collectLocalNominalCaptureSymbols(
            memberProperties: classDecl.memberProperties,
            includePropertyInitializers: true,
            extraBodies: classDecl.initBlocks + classDecl.enumEntries.flatMap(\.initBlocks),
            extraExprRoots: classDecl.superTypeEntries.flatMap(\.constructorArgs).map(\.expr)
                + classDecl.superTypeEntries.compactMap(\.delegateExpression)
                + defaultExprRoots,
            captureOuterSymbols: captureOuterSymbols,
            ast: ast,
            sema: sema
        ))
        // Nested inner-class member bodies resolve outer receivers through the
        // rewritten `memberOuterReceiverTypes` (see above), so the capture
        // candidate set must include those receiver value symbols as well as the
        // original tower symbols; otherwise a receiver referenced only from a
        // nested inner class would be dropped (KUU-4605).
        capturedSymbols.formUnion(collectNestedInnerClassCaptures(
            classDecl.nestedClasses,
            outerReceiverSymbols: Set(
                ctx.outerReceiverTypes.compactMap(\.symbol)
                    + memberOuterReceiverTypes.compactMap(\.symbol)
                    + ctx.implicitReceiverStack.map(\.symbol)
            ),
            superConstructorCaptureSymbols: captureOuterSymbols,
            ast: ast,
            sema: sema
        ))
        for superSymbol in directSuperSymbols where sema.symbols.symbol(superSymbol)?.kind == .class {
            capturedSymbols.formUnion(sema.bindings.objectLiteralCaptureSymbols(for: superSymbol))
        }
        // KUU-2955: `class FooC : A.AB(...)` — an inner-class supertype's
        // inherited `$outer` slot must point at the enclosing `A` instance
        // when `FooC.<init>` delegates to `AB.<init>`. `FooC` itself is not
        // inner so nothing else captures that receiver; record the innermost
        // matching `this` so the value is materialized into a `FooC` field
        // and reachable inside `<init>`'s independent KIR function.
        for superSymbol in directSuperSymbols {
            guard sema.symbols.symbol(superSymbol)?.flags.contains(.innerClass) == true,
                  let outerOwner = sema.symbols.parentSymbol(for: superSymbol)
            else {
                continue
            }
            let outerOwnerArgs = sema.types.nominalTypeParameterSymbols(for: outerOwner).map {
                TypeArg.invariant(sema.types.make(.typeParam(TypeParamType(symbol: $0))))
            }
            let outerOwnerType = sema.types.make(.classType(ClassType(
                classSymbol: outerOwner, args: outerOwnerArgs, nullability: .nonNull
            )))
            var receiverCandidates: [(type: TypeID, symbol: SymbolID?)] = ctx.outerReceiverTypes.map {
                (type: $0.type, symbol: $0.symbol)
            }
            receiverCandidates.append(contentsOf: ctx.implicitReceiverStack.map {
                (type: $0.type, symbol: $0.symbol)
            })
            for candidate in receiverCandidates.reversed() {
                guard let receiverSymbol = candidate.symbol,
                      sema.types.isSubtype(
                          sema.types.makeNonNullable(candidate.type), outerOwnerType
                      )
                else {
                    continue
                }
                capturedSymbols.insert(receiverSymbol)
                break
            }
        }
        bindLocalNominalCaptures(
            capturedSymbols,
            ownerSymbol: classSymbol,
            outerLocalsSnapshot: outerLocalsSnapshot,
            outerReceiverTypes: ctx.outerReceiverTypes,
            receiverStack: ctx.implicitReceiverStack,
            sema: sema
        )

        var pendingNestedNominalDecls = classDecl.nestedClasses + classDecl.nestedObjects
        var nestedNominalSymbols: [SymbolID] = []
        while let nestedDeclID = pendingNestedNominalDecls.popLast() {
            guard let nestedSymbol = sema.bindings.declSymbols[nestedDeclID],
                  let nestedDecl = ast.arena.decl(nestedDeclID)
            else {
                continue
            }
            nestedNominalSymbols.append(nestedSymbol)
            switch nestedDecl {
            case let .classDecl(nestedClass):
                pendingNestedNominalDecls.append(contentsOf: nestedClass.nestedClasses + nestedClass.nestedObjects)
                if let companionObject = nestedClass.companionObject {
                    pendingNestedNominalDecls.append(companionObject)
                }
            case let .interfaceDecl(nestedInterface):
                pendingNestedNominalDecls.append(contentsOf: nestedInterface.nestedClasses + nestedInterface.nestedObjects)
                if let companionObject = nestedInterface.companionObject {
                    pendingNestedNominalDecls.append(companionObject)
                }
            case let .objectDecl(nestedObject):
                pendingNestedNominalDecls.append(contentsOf: nestedObject.nestedClasses + nestedObject.nestedObjects)
            default:
                break
            }
        }
        for nestedSymbol in nestedNominalSymbols {
            guard let nestedInfo = sema.symbols.symbol(nestedSymbol),
                  nestedInfo.kind == .class || nestedInfo.kind == .object
            else {
                continue
            }
            var inheritedCaptures = sema.bindings.objectLiteralCaptureSymbols(for: nestedSymbol)
            for superSymbol in sema.symbols.directSupertypes(for: nestedSymbol)
                where sema.symbols.symbol(superSymbol)?.kind == .class
            {
                inheritedCaptures.append(contentsOf: sema.bindings.objectLiteralCaptureSymbols(for: superSymbol))
            }
            sema.bindings.bindObjectLiteralCaptureSymbols(
                nestedSymbol,
                symbols: Array(Set(inheritedCaptures)).sorted(by: { $0.rawValue < $1.rawValue })
            )
        }
        synthesizeLocalNominalLayout(
            ownerSymbol: classSymbol,
            memberFunctionDecls: classDecl.memberFunctions,
            memberFunctionSymbolsByDecl: memberFunctionSymbolsByDecl,
            memberPropertyDecls: classDecl.memberProperties,
            propertySymbolsByDecl: propertySymbolsByDecl,
            capturedSymbols: capturedSymbols,
            directSuperSymbols: directSuperSymbols,
            declRange: classDecl.range,
            subjectDescription: "Class '\(interner.resolve(classDecl.name))'",
            ctx: ctx
        )
        DataFlowSemaPhase().synthesizeNominalLayouts(
            for: nestedNominalSymbols,
            symbols: sema.symbols,
            types: sema.types,
            interner: interner,
            diagnostics: sema.diagnostics
        )
        return classSymbol
    }

    private func collectNestedInnerClassCaptures(
        _ nestedClassDeclIDs: [DeclID],
        outerReceiverSymbols: Set<SymbolID>,
        superConstructorCaptureSymbols: Set<SymbolID>,
        ast: ASTModule,
        sema: SemaModule
    ) -> Set<SymbolID> {
        var capturedSymbols: Set<SymbolID> = []
        var pendingDeclIDs = nestedClassDeclIDs
        while let nestedDeclID = pendingDeclIDs.popLast() {
            guard let decl = ast.arena.decl(nestedDeclID),
                  case let .classDecl(nestedClass) = decl,
                  nestedClass.isInner
            else {
                continue
            }
            for functionDeclID in nestedClass.memberFunctions {
                guard let functionDecl = ast.arena.decl(functionDeclID),
                      case let .funDecl(function) = functionDecl
                else {
                    continue
                }
                capturedSymbols.formUnion(driver.captureAnalyzer.collectCapturedOuterSymbols(
                    inBody: function.body,
                    ast: ast,
                    sema: sema,
                    outerSymbols: outerReceiverSymbols,
                    skipNestedClosures: false
                ))
            }
            capturedSymbols.formUnion(collectLocalNominalCaptureSymbols(
                memberProperties: nestedClass.memberProperties,
                includePropertyInitializers: true,
                extraBodies: nestedClass.initBlocks + nestedClass.secondaryConstructors.map(\.body),
                extraExprRoots: nestedClass.primaryConstructorParams.compactMap(\.defaultValue)
                    + nestedClass.secondaryConstructors.flatMap { $0.valueParams.compactMap(\.defaultValue) },
                captureOuterSymbols: outerReceiverSymbols,
                ast: ast,
                sema: sema
            ))
            let superConstructorExprRoots = nestedClass.superTypeEntries.flatMap(\.constructorArgs).map(\.expr)
                + nestedClass.secondaryConstructors.flatMap { constructor -> [ExprID] in
                    guard let delegationCall = constructor.delegationCall,
                          delegationCall.kind == .super_
                    else {
                        return []
                    }
                    return delegationCall.args.map(\.expr)
                }
            capturedSymbols.formUnion(collectLocalNominalCaptureSymbols(
                memberProperties: [],
                includePropertyInitializers: false,
                extraBodies: [],
                extraExprRoots: superConstructorExprRoots,
                captureOuterSymbols: superConstructorCaptureSymbols,
                ast: ast,
                sema: sema
            ))
            pendingDeclIDs.append(contentsOf: nestedClass.nestedClasses)
        }
        return capturedSymbols
    }
}
