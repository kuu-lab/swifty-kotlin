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
            let objectType = objectLiteralType(for: objectSymbol, sema: sema)
            // A named `object`'s name is both a type name and the singleton
            // value name, so it registers in the lexical scope as well —
            // `val x: Local` resolves, while `Local` in expression position
            // hits `locals` first and yields the objectType value.
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

        default:
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType
        }
    }

    /// The nominal is discovered too late for `synthesizeNominalLayouts`,
    /// so it builds its own.
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

        if let existing = sema.bindings.declSymbols[declID] {
            return existing
        }

        let outerLocalsSnapshot = locals
        let outerSymbols = Set(outerLocalsSnapshot.values.map(\.symbol))

        // Same as `ensureObjectLiteralSymbol`: an outer local can also be
        // reached through the enclosing class receiver, so stored properties
        // of that receiver (and its class supertypes) join the capture set.
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
        // Same as the object path: `this@Outer` receiver symbols captured by
        // the enclosing literal are reachable here too.
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
        // Abstract and sealed classes are implicitly open, matching the
        // flags assigned to class declarations during header collection.
        if classDecl.modifiers.contains(.abstract) {
            classFlags.insert(.openType)
        }
        if classDecl.modifiers.contains(.sealed) {
            classFlags.formUnion([.abstractType, .openType])
        }
        let classSymbol = sema.symbols.define(
            kind: .class,
            name: classDecl.name,
            fqName: classFQName,
            declSite: classDecl.range,
            visibility: .private,
            flags: classFlags
        )
        sema.bindings.bindDecl(declID, symbol: classSymbol)
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
        // Class type parameters and the class itself are visible in headers
        // and members without escaping into the enclosing lexical scope.
        classScope.insert(classSymbol)
        for typeParameterSymbol in typeParameterResult.symbols {
            classScope.insert(typeParameterSymbol)
        }
        let classCtx = ctx.withoutSuspensionContext().withOuterReceiver(
            label: classDecl.name,
            type: classType
        ).copying(
            scope: classScope,
            implicitReceiverType: classType,
            enclosingClassSymbol: classSymbol
        )

        let declIsBundledStdlib = driver.sourceManager?
            .origin(of: ctx.currentFileID)?.isBundledStdlib == true
        var directSuperSymbols: [SymbolID] = []
        directSuperSymbols.reserveCapacity(classDecl.superTypeEntries.count)
        var directSuperTypeArgs: [SymbolID: [TypeArg]] = [:]
        var directSuperTypes: [TypeID] = []
        for entry in classDecl.superTypeEntries {
            let resolved = driver.helpers.resolveTypeRef(
                entry.typeRef,
                ast: ast,
                sema: sema,
                interner: interner,
                scope: classScope,
                diagnostics: ctx.sema.diagnostics
            )
            directSuperTypes.append(resolved)
            if case let .classType(classType) = sema.types.kind(of: resolved) {
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
                directSuperSymbols.append(classType.classSymbol)
                directSuperTypeArgs[classType.classSymbol] = classType.args
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
        var constructorHeaders: [(params: [ValueParamDecl], range: SourceRange)] = []
        if hasPrimaryConstructor {
            constructorHeaders.append((classDecl.primaryConstructorParams, classDecl.range))
        }
        constructorHeaders.append(contentsOf: classDecl.secondaryConstructors.map { ($0.valueParams, $0.range) })
        var constructorSymbols: [SymbolID] = []
        for header in constructorHeaders {
            let ctorSymbol = sema.symbols.define(
                kind: .constructor,
                name: initName,
                fqName: classFQName + [initName],
                declSite: header.range,
                visibility: .public,
                flags: [.synthetic]
            )
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
        if let compilationContext = driver.compilationContext {
            DataFlowSemaPhase().collectMemberHeaders(
                members: MemberDeclarations(
                    functions: [],
                    properties: [],
                    nestedClasses: classDecl.nestedClasses,
                    nestedObjects: classDecl.nestedObjects
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
                interner: interner
            )
        }
        // Synthetic local owners do not encode lexical nesting in their FQ
        // names. Preserve every surrounding class, including other locals.
        var lexicalEnclosingFQNames: [[InternedString]] = []
        var lexicalScope: Scope? = ctx.scope
        while let scope = lexicalScope as? BaseScope {
            if let memberScope = scope as? ClassMemberScope,
               let owner = sema.symbols.symbol(memberScope.owner) {
                lexicalEnclosingFQNames.append(owner.fqName)
            }
            lexicalScope = scope.parent
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
            for nestedDeclID in classDecl.nestedClasses + classDecl.nestedObjects {
                DataFlowSemaPhase().bindInheritanceEdges(
                    declID: nestedDeclID,
                    currentPackage: sourceFile?.packageFQName ?? [],
                    imports: sourceFile?.imports ?? [],
                    enclosingTypeParameters: [:],
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
                diagnostics: ctx.sema.diagnostics
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
            // Local declarations are discovered during body inference, after
            // the module-wide post-inheritance pass. Their superclass edges
            // are already bound here, so collect the generated override now.
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
        for ctorSymbol in constructorSymbols {
            classScope.insert(ctorSymbol)
        }
        for nestedClassDeclID in classDecl.nestedClasses {
            driver.declChecker.typeCheckNestedClassDecl(
                declID: nestedClassDeclID,
                ctx: classCtx,
                solver: driver.solver,
                diagnostics: sema.diagnostics
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

        // Constructor-parameter locals shadow outer locals of the same name
        // (Kotlin scopes header params inside `<init>`/init blocks/
        // initializers), so merge outer first, ctor params on top.
        let primaryCtorLocals = outerLocalsSnapshot
            .merging(
                driver.declChecker.primaryConstructorParameterLocals(classDecl: classDecl, ctx: classCtx)
            ) { _, new in new }

        driver.declChecker.typeCheckClassDelegation(
            classDecl,
            symbol: classSymbol,
            ctx: ctx,
            solver: driver.solver,
            diagnostics: sema.diagnostics,
            baseLocals: outerLocalsSnapshot
        )

        // Unlike an object literal (KSP-CAP-018), a local class's superclass
        // constructor arguments are evaluated inside `<init>`, so they infer
        // against ctor-param + captured locals. The enclosing receiver tower
        // (`ctx`, not `classCtx` — that already holds `this@<local class>`)
        // stays visible so `class Y : C(x)` can resolve `x` on the captured
        // outer `this`; `excludingEnclosingClassReceiver` inside the
        // delegation path still hides the local class's own `this`.
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
        let explicitSuperclassSymbol = driver.declChecker.explicitClassSuperclassSymbol(classDecl, ctx: classCtx)
        driver.declChecker.typeCheckSecondaryConstructors(
            classDecl.secondaryConstructors,
            ctx: classCtx,
            solver: driver.solver,
            diagnostics: ctx.sema.diagnostics,
            ownerSymbol: classSymbol,
            hasPrimaryConstructor: hasPrimaryConstructor,
            explicitSuperclassSymbol: explicitSuperclassSymbol,
            baseLocals: outerLocalsSnapshot
        )
        driver.declChecker.typeCheckInitBlocks(
            classDecl.initBlocks,
            ctx: classCtx,
            baseLocals: primaryCtorLocals
        )
        typeCheckLocalNominalMemberProperties(
            classDecl.memberProperties,
            propertySymbolsByDecl: propertySymbolsByDecl,
            memberScope: classScope,
            memberCtx: classCtx,
            initializerLocals: primaryCtorLocals,
            accessorBaseLocals: outerLocalsSnapshot,
            ctx: ctx
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
        // Every initializer-side root of a local class (property
        // initializers, `init {}` blocks, superclass ctor args) lowers inside
        // `<init>`, so outer-local references there need capture fields —
        // unlike an object literal where they run inline.
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
        capturedSymbols.formUnion(collectNestedInnerClassCaptures(
            classDecl.nestedClasses,
            outerReceiverSymbols: Set(
                ctx.outerReceiverTypes.compactMap(\.symbol) + ctx.implicitReceiverStack.map(\.symbol)
            ),
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
                extraExprRoots: nestedClass.superTypeEntries.flatMap(\.constructorArgs).map(\.expr)
                    + nestedClass.primaryConstructorParams.compactMap(\.defaultValue)
                    + nestedClass.secondaryConstructors.flatMap { constructor in
                        constructor.valueParams.compactMap(\.defaultValue)
                            + (constructor.delegationCall?.args.map(\.expr) ?? [])
                    },
                captureOuterSymbols: outerReceiverSymbols,
                ast: ast,
                sema: sema
            ))
            pendingDeclIDs.append(contentsOf: nestedClass.nestedClasses)
        }
        return capturedSymbols
    }
}
