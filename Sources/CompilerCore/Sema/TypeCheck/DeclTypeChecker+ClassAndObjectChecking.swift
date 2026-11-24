extension DeclTypeChecker {
    func typeCheckBoundPropertyDecl(
        _ property: PropertyDecl,
        declID: DeclID,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        initialLocals: LocalBindings = [:],
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine,
        checkAccessorBodies: Bool = true
    ) {
        let tracksInferredProperty = driver.inferredPropertyDeclarations[symbol] != nil
        let tracksPendingProperty = driver.pendingPropertyTypes.contains(symbol)
        if tracksPendingProperty {
            driver.deferredInferredProperties.remove(symbol)
        }
        if tracksInferredProperty {
            guard !driver.precheckedPropertyDecls.contains(declID),
                  driver.checkingInferredProperties.insert(symbol).inserted
            else { return }
        }
        let diagnosticCheckpoint = tracksPendingProperty || tracksInferredProperty ? diagnostics.checkpoint() : 0
        defer {
            let currentDiagnostics = tracksPendingProperty || tracksInferredProperty ? diagnostics.diagnostics : []
            let hasNewErrors = currentDiagnostics.dropFirst(diagnosticCheckpoint).contains { $0.severity == .error }
            let hasOwnErrors = currentDiagnostics.contains {
                $0.severity == .error && ($0.primaryRange.map(property.range.contains) ?? true)
            }
            if tracksPendingProperty, !hasNewErrors, !hasOwnErrors,
               !driver.deferredInferredProperties.contains(symbol)
            {
                driver.pendingPropertyTypes.remove(symbol)
            }
            if tracksInferredProperty {
                driver.checkingInferredProperties.remove(symbol)
                if checkAccessorBodies,
                   !hasNewErrors,
                   !driver.deferredInferredProperties.contains(symbol),
                   !currentDiagnostics.contains(where: {
                       $0.primaryRange.map(property.range.contains) ?? true
                   })
                {
                    driver.precheckedPropertyDecls.insert(declID)
                }
            }
        }
        let propertyCtx = propertyTypeParameterContext(property, symbol: symbol, ctx: ctx, diagnostics: diagnostics)
        validatePropertyHeaderOptInTypes(
            symbol,
            ctx: propertyCtx
        )
        typeCheckPropertyDecl(
            property,
            symbol: symbol,
            ctx: propertyCtx,
            initialLocals: initialLocals,
            solver: solver,
            diagnostics: diagnostics,
            checkAccessorBodies: checkAccessorBodies
        )
    }

    func propertyTypeParameterContext(
        _ property: PropertyDecl, symbol: SymbolID, ctx: TypeInferenceContext, diagnostics: DiagnosticEngine
    ) -> TypeInferenceContext {
        var propertyCtx = ctx.with(currentDeclSymbol: symbol)
        if !property.typeParams.isEmpty {
            let propertyScope = FunctionScope(parent: ctx.scope, symbols: ctx.sema.symbols)
            if let getter = ctx.sema.symbols.extensionPropertyGetterAccessor(for: symbol),
               let signature = ctx.sema.symbols.functionSignature(for: getter) {
                for parameter in signature.typeParameterSymbols.dropFirst(signature.classTypeParameterCount) { propertyScope.insert(parameter) }
                let receiverTypes = signature.contextReceiverTypes + (signature.receiverType.map { [$0] } ?? [])
                for parameter in signature.typeParameterSymbols.dropFirst(signature.classTypeParameterCount)
                    where !receiverTypes.contains(where: {
                        ctx.sema.types.typeContainsTypeParamThroughUpperBounds($0, symbol: parameter)
                    }) {
                    diagnostics.error("KSWIFTK-SEMA-0005", "Property type parameter must occur in its receiver type.", range: property.range)
                }
            } else {
                diagnostics.error("KSWIFTK-SEMA-0005", "Only extension properties can declare type parameters.", range: property.range)
            }
            var names: Set<InternedString> = []
            for parameter in property.typeParams {
                if !names.insert(parameter.name).inserted {
                    diagnostics.error("KSWIFTK-SEMA-0005", "Duplicate property type parameter.", range: property.range)
                }
                if parameter.isReified, !property.allAccessorsAreInline {
                    diagnostics.error("KSWIFTK-SEMA-0020", "Reified property type parameters require inline accessors.", range: property.range)
                }
                if parameter.variance != .invariant {
                    diagnostics.error("KSWIFTK-SEMA-0005", "Variance is not allowed on property type parameters.", range: property.range)
                }
            }
            propertyCtx = propertyCtx.copying(scope: propertyScope)
        }
        return propertyCtx
    }

    func typeCheckClassDecl(
        _ classDecl: ClassDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine,
        baseLocals: LocalBindings = [:]
    ) {
        typeCheckAnnotationFactories(classDecl.annotations, symbol: symbol, ctx: ctx)
        if let classSymbol = ctx.sema.symbols.symbol(symbol) {
            let constructorPath = classSymbol.fqName + [ctx.interner.intern("<init>")]
            let constructors = ctx.sema.symbols.lookupAll(fqName: constructorPath)
            if !classDecl.primaryConstructorAnnotations.isEmpty,
               let constructor = constructors.first(where: {
                   ctx.sema.symbols.symbol($0)?.declSite == classDecl.range
               })
            {
                typeCheckAnnotationFactories(classDecl.primaryConstructorAnnotations, symbol: constructor, ctx: ctx)
            }
            for declaration in classDecl.secondaryConstructors where !declaration.annotations.isEmpty {
                if let constructor = constructors.first(where: {
                    ctx.sema.symbols.symbol($0)?.declSite == declaration.range
                }) {
                    typeCheckAnnotationFactories(declaration.annotations, symbol: constructor, ctx: ctx)
                }
            }
        }
        var allNestedObjects = classDecl.nestedObjects
        if let companionDeclID = classDecl.companionObject {
            allNestedObjects.append(companionDeclID)
        }
        let (classType, classCtx, primaryCtorLocals) = makeClassTypeCheckContext(
            classDecl: classDecl,
            symbol: symbol,
            nestedObjects: allNestedObjects,
            ctx: ctx
        )
        let classBodyLocals = baseLocals.merging(primaryCtorLocals) { _, new in new }
        let primaryConstructor = ctx.sema.symbols.symbols(atDeclSite: classDecl.range)
            .compactMap({ ctx.sema.symbols.symbol($0) })
            .first(where: { $0.kind == .constructor })
        typeCheckPrimaryConstructorAnnotationFactories(
            classDecl.primaryConstructorAnnotations,
            symbol: primaryConstructor?.id,
            ctx: classCtx
        )
        if let companionDeclID = classDecl.companionObject {
            let diagnosticSnapshot = diagnostics.count
            let nominalDeclsCheckedBefore = driver.localNominalDeclChecks.count
            inferClassLikeMemberTypes(
                memberFunctions: classDecl.memberFunctions,
                memberProperties: classDecl.memberProperties,
                nestedClasses: classDecl.nestedClasses,
                ctx: classCtx,
                propertyInitializerLocals: classBodyLocals,
                memberFunctionBaseLocals: baseLocals,
                solver: solver,
                diagnostics: diagnostics
            )
            typeCheckNestedObjectDecl(companionDeclID, ctx: classCtx, solver: solver, diagnostics: diagnostics)
            diagnostics.truncate(to: diagnosticSnapshot)
            driver.markLocalNominalRechecks(since: nominalDeclsCheckedBefore)
        }

        validateClassLikeHeaderOptInTypes(
            symbol: symbol,
            ctx: classCtx,
            range: classDecl.range
        )

        typeCheckClassLikeMembers(
            memberFunctions: classDecl.memberFunctions,
            memberProperties: classDecl.memberProperties,
            nestedClasses: classDecl.nestedClasses,
            nestedObjects: allNestedObjects,
            ctx: classCtx,
            propertyInitializerLocals: classBodyLocals,
            memberFunctionBaseLocals: baseLocals,
            nestedClassBaseLocals: baseLocals,
            solver: solver,
            diagnostics: diagnostics
        )
        typeCheckInitBlocks(classDecl.initBlocks, ctx: classCtx, baseLocals: classBodyLocals)
        typeCheckPrimaryConstructorDefaultValues(
            classDecl, ctx: classCtx, solver: solver, diagnostics: diagnostics,
            baseLocals: baseLocals
        )
        if classDecl.modifiers.contains(.annotationClass),
           driver.compilationContext?.jvmImports?.classpathStubFiles.contains(classDecl.range.start.file) != true {
            for parameter in classDecl.primaryConstructorParams {
                if let value = parameter.defaultValue { validateAnnotationDefaultValue(value, ctx: classCtx) }
            }
        }
        typeCheckEnumEntryConstructorArguments(
            classDecl, symbol: symbol, ctx: classCtx, solver: solver, diagnostics: diagnostics
        )
        typeCheckPrimaryConstructorSuperDelegation(
            classDecl,
            symbol: symbol,
            ctx: classCtx,
            extraLocals: baseLocals,
            outerReceiversToKeep: classDecl.isInner ? ctx.outerReceiverTypes : ctx.singletonObjectOuterReceivers
        )
        let superclassSymbol = constructorSuperclassSymbol(classDecl, ctx: classCtx)
        typeCheckSecondaryConstructors(
            classDecl.secondaryConstructors,
            ctx: classCtx,
            solver: solver,
            diagnostics: diagnostics,
            ownerSymbol: symbol,
            hasPrimaryConstructor: classDecl.hasPrimaryConstructorSyntax,
            superclassSymbol: superclassSymbol,
            baseLocals: baseLocals
        )
        typeCheckClassDelegation(
            classDecl, symbol: symbol, ctx: classCtx, solver: solver,
            diagnostics: diagnostics, baseLocals: baseLocals
        )
        typeCheckEnumEntryMemberBodies(
            classDecl,
            enumSymbol: symbol,
            enumType: classType,
            ctx: classCtx,
            solver: solver,
            diagnostics: diagnostics
        )
    }

    private func typeCheckEnumEntryMemberBodies(
        _ classDecl: ClassDecl,
        enumSymbol: SymbolID,
        enumType: TypeID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        for entry in classDecl.enumEntries where !entry.memberFunctions.isEmpty
            || !entry.memberProperties.isEmpty || !entry.nestedClasses.isEmpty || !entry.initBlocks.isEmpty
        {
            let entryFQName = (ctx.sema.symbols.symbol(enumSymbol)?.fqName ?? []) + [entry.name]
            guard let entrySymbol = ctx.sema.symbols.lookupAll(fqName: entryFQName).first(where: { symbolID in
                ctx.sema.symbols.symbol(symbolID)?.kind == .field
                    && ctx.sema.symbols.parentSymbol(for: symbolID) == enumSymbol
            }) else {
                continue
            }
            let entryScope = buildClassMemberScope(
                ownerSymbol: entrySymbol,
                ownerType: enumType,
                memberFunctions: entry.memberFunctions,
                memberProperties: entry.memberProperties,
                nestedClasses: entry.nestedClasses,
                nestedObjects: [],
                ctx: ctx
            )
            let entryCtx = ctx
                .withOuterReceiver(label: entry.name, type: enumType, symbol: enumSymbol)
                .copying(
                    scope: entryScope,
                    implicitReceiverType: enumType,
                    currentDeclSymbol: entrySymbol,
                    enclosingClassSymbol: enumSymbol
                )
                .withEnumEntrySuperContext(ownerSymbol: enumSymbol, type: enumType)
            typeCheckClassLikeMembers(
                memberFunctions: entry.memberFunctions,
                memberProperties: entry.memberProperties,
                nestedClasses: entry.nestedClasses,
                nestedObjects: [],
                ctx: entryCtx,
                solver: solver,
                diagnostics: diagnostics
            )
            typeCheckInitBlocks(entry.initBlocks, ctx: entryCtx)
        }
    }

    func typeCheckClassDelegation(
        _ classDecl: ClassDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine,
        baseLocals: LocalBindings = [:]
    ) {
        typeCheckInterfaceDelegation(
            entries: classDecl.superTypeEntries,
            range: classDecl.range,
            symbol: symbol,
            ctx: ctx,
            solver: solver,
            diagnostics: diagnostics,
            baseLocals: baseLocals
        )
    }

    private func typeCheckInterfaceDelegation(
        entries: [SuperTypeEntry],
        range: SourceRange,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine,
        baseLocals: LocalBindings = [:]
    ) {
        let sema = ctx.sema
        let delegatedEntries = entries.filter { $0.delegateExpression != nil }
        guard !delegatedEntries.isEmpty else { return }

        var delegationCtx = ctx
        let ctorSymbols = sema.symbols.symbols(atDeclSite: range)
            .compactMap { sema.symbols.symbol($0) }
            .filter { $0.kind == .constructor }

        if let ctorSymbol = ctorSymbols.first,
           let signature = sema.symbols.functionSignature(for: ctorSymbol.id)
        {
            let ctorScope = BaseScope(parent: ctx.scope, symbols: sema.symbols)
            for paramSym in signature.valueParameterSymbols {
                ctorScope.insert(paramSym)
            }
            delegationCtx = ctx.copying(scope: ctorScope)
        }

        for delegation in delegatedEntries {
            guard let expr = delegation.delegateExpression else { continue }
            var locals = baseLocals
            if let ctorSymbol = ctorSymbols.first,
               let signature = sema.symbols.functionSignature(for: ctorSymbol.id)
            {
                for (index, paramSym) in signature.valueParameterSymbols.enumerated() {
                    guard let paramInfo = sema.symbols.symbol(paramSym) else { continue }
                    let paramType = index < signature.parameterTypes.count
                        ? signature.parameterTypes[index]
                        : sema.types.anyType
                    locals[paramInfo.name] = (
                        type: paramType,
                        symbol: paramSym,
                        isMutable: false,
                        isInitialized: true
                    )
                }
            }
            let expectedDelegateType: TypeID? = sema.symbols
                .delegatedInterfaces(forClass: symbol)
                .first(where: { interfaceSymbol in
                    sema.symbols.classDelegationExpr(
                        forClass: symbol,
                        interface: interfaceSymbol
                    ) == expr
                })
                .flatMap { interfaceSymbol in
                    sema.symbols.classDelegationField(
                        forClass: symbol,
                        interface: interfaceSymbol
                    )
                }
                .flatMap { sema.symbols.propertyType(for: $0) }

            let delegateType = driver.inferExpr(
                expr,
                ctx: delegationCtx,
                locals: &locals,
                expectedType: expectedDelegateType
            )
            if let expectedDelegateType {
                driver.emitSubtypeConstraint(
                    left: delegateType,
                    right: expectedDelegateType,
                    range: ctx.ast.arena.exprRange(expr),
                    solver: solver,
                    sema: sema,
                    diagnostics: diagnostics
                )
            }
        }
    }

    func typeCheckObjectDecl(
        _ objectDecl: ObjectDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        typeCheckAnnotationFactories(objectDecl.annotations, symbol: symbol, ctx: ctx)
        let objectCtx = makeObjectTypeCheckContext(objectDecl: objectDecl, symbol: symbol, ctx: ctx)

        validateClassLikeHeaderOptInTypes(
            symbol: symbol,
            ctx: objectCtx,
            range: objectDecl.range
        )

        typeCheckInterfaceDelegation(
            entries: objectDecl.superTypeEntries,
            range: objectDecl.range,
            symbol: symbol,
            ctx: ctx,
            solver: solver,
            diagnostics: diagnostics
        )

        var superclassArgumentLocals: LocalBindings = [:]
        bindObjectSuperConstructorCall(
            objectDecl,
            symbol: symbol,
            ctx: ctx.copying(
                implicitReceiverType: .some(nil),
                outerReceiverTypes: ctx.singletonObjectOuterReceivers
            ).excludingEnclosingClassReceiver(),
            locals: &superclassArgumentLocals
        )

        typeCheckClassLikeMembers(
            memberFunctions: objectDecl.memberFunctions,
            memberProperties: objectDecl.memberProperties,
            nestedClasses: objectDecl.nestedClasses,
            nestedObjects: objectDecl.nestedObjects,
            ctx: objectCtx,
            solver: solver,
            diagnostics: diagnostics
        )
        typeCheckInitBlocks(objectDecl.initBlocks, ctx: objectCtx)
    }

    func bindObjectSuperConstructorCall(
        _ objectDecl: ObjectDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) {
        let sema = ctx.sema
        guard sema.symbols.symbol(symbol)?.flags.contains(.expectDeclaration) != true else { return }
        guard let superclassSymbol = superclassSymbol(of: symbol, sema: sema),
              let superclassInfo = sema.symbols.symbol(superclassSymbol)
        else {
            return
        }
        let candidates = sema.symbols
            .lookupAll(fqName: superclassInfo.fqName + [ctx.interner.intern("<init>")])
            .filter {
                sema.symbols.symbol($0)?.kind == .constructor
                    && sema.symbols.parentSymbol(for: $0) == superclassSymbol
            }
        guard !candidates.isEmpty else { return }
        var delegation = companionHeaderDelegationContext(
            superclassSymbol: superclassSymbol,
            ctx: ctx,
            locals: locals
        )
        let resolved = inferConstructorDelegationArguments(
            objectDecl.superTypeConstructorArgs,
            candidates: candidates,
            range: objectDecl.range,
            targetType: constructorSuperclassType(
                ownerSymbol: symbol, superclassSymbol: superclassSymbol, ctx: ctx
            ),
            ctx: delegation.ctx,
            locals: &delegation.locals
        )
        guard let chosenCallee = resolved.chosenCallee else { return }
        sema.bindings.bindConstructorDelegationCall(
            symbol,
            binding: CallBinding(
                chosenCallee: chosenCallee,
                substitutedTypeArguments: resolved.substitutedTypeArguments
                    .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                    .map(\.value),
                parameterMapping: resolved.parameterMapping
            )
        )
    }

    func typeCheckInterfaceDecl(
        _ interfaceDecl: InterfaceDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        typeCheckAnnotationFactories(interfaceDecl.annotations, symbol: symbol, ctx: ctx)
        var allNestedObjects = interfaceDecl.nestedObjects
        if let companionDeclID = interfaceDecl.companionObject {
            allNestedObjects.append(companionDeclID)
        }
        let interfaceCtx = makeInterfaceTypeCheckContext(
            interfaceDecl: interfaceDecl,
            symbol: symbol,
            ctx: ctx
        )

        if let companionDeclID = interfaceDecl.companionObject {
            let diagnosticSnapshot = diagnostics.count
            let nominalDeclsCheckedBefore = driver.localNominalDeclChecks.count
            inferClassLikeMemberTypes(
                memberFunctions: interfaceDecl.memberFunctions,
                memberProperties: interfaceDecl.memberProperties,
                nestedClasses: interfaceDecl.nestedClasses,
                ctx: interfaceCtx,
                solver: solver,
                diagnostics: diagnostics
            )
            typeCheckNestedObjectDecl(companionDeclID, ctx: interfaceCtx, solver: solver, diagnostics: diagnostics)
            diagnostics.truncate(to: diagnosticSnapshot)
            driver.markLocalNominalRechecks(since: nominalDeclsCheckedBefore)
        }

        validateClassLikeHeaderOptInTypes(
            symbol: symbol,
            ctx: interfaceCtx,
            range: interfaceDecl.range
        )

        typeCheckClassLikeMembers(
            memberFunctions: interfaceDecl.memberFunctions,
            memberProperties: interfaceDecl.memberProperties,
            nestedClasses: interfaceDecl.nestedClasses,
            nestedObjects: allNestedObjects,
            ctx: interfaceCtx,
            solver: solver,
            diagnostics: diagnostics
        )
    }

    private func inferClassLikeMemberTypes(
        memberFunctions: [DeclID],
        memberProperties: [DeclID],
        nestedClasses: [DeclID] = [],
        ctx: TypeInferenceContext,
        propertyInitializerLocals: LocalBindings = [:],
        memberFunctionBaseLocals: LocalBindings = [:],
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        let ast = ctx.ast
        let sema = ctx.sema

        // Functions and properties are type-checked together, in source
        // declaration order, rather than as two separate function-then-property
        // batches. A property without an explicit type annotation only gets its
        // real inferred type once its own PropertyDecl is checked; before that,
        // the header pass has it pinned to a placeholder `Any?`. Batching all
        // functions first meant any function referencing such a property — even
        // one declared textually above it — would see the placeholder and fail
        // with a spurious KSWIFTK-TYPE-0001.
        //
        // A function that textually precedes such a property still only sees
        // the placeholder on this first pass, so every member function is
        // re-checked once more below, after every property in this loop has
        // been resolved to its real type. Diagnostics from this first,
        // speculative function check are truncated away immediately: they may
        // be blaming a placeholder that the second, authoritative pass below
        // will no longer see (DEBT-SEMA-001).
        let orderedMembers = (memberFunctions + memberProperties).sorted {
            (memberDeclStartOffset($0, ast: ast) ?? 0) < (memberDeclStartOffset($1, ast: ast) ?? 0)
        }

        for declID in orderedMembers {
            guard let decl = ast.arena.decl(declID),
                  let symbol = sema.bindings.declSymbols[declID]
            else {
                continue
            }
            switch decl {
            case let .funDecl(function):
                let diagnosticSnapshot = diagnostics.count
                let nominalDeclsCheckedBefore = driver.localNominalDeclChecks.count
                typeCheckFunctionDecl(
                    function,
                    symbol: symbol,
                    ctx: ctx.with(currentDeclSymbol: symbol),
                    solver: solver,
                    diagnostics: diagnostics,
                    baseLocals: memberFunctionBaseLocals
                )
                diagnostics.truncate(to: diagnosticSnapshot)
                driver.markLocalNominalRechecks(since: nominalDeclsCheckedBefore)

            case let .propertyDecl(property):
                guard !driver.precheckedPropertyDecls.contains(declID) else {
                    continue
                }
                let diagnosticSnapshot = diagnostics.count
                let nominalDeclsCheckedBefore = driver.localNominalDeclChecks.count
                typeCheckBoundPropertyDecl(
                    property,
                    declID: declID,
                    symbol: symbol,
                    ctx: ctx.with(currentDeclSymbol: symbol),
                    initialLocals: propertyInitializerLocals,
                    solver: solver,
                    diagnostics: diagnostics
                )
                if needsMemberPropertyRecheck(property, nestedClasses: nestedClasses) {
                    diagnostics.truncate(to: diagnosticSnapshot)
                    driver.markLocalNominalRechecks(since: nominalDeclsCheckedBefore)
                }

            default:
                continue
            }
        }
    }

    private func needsAccessorRecheck(_ property: PropertyDecl) -> Bool {
        property.getter != nil && property.initializer == nil
            && property.delegateExpression == nil && property.explicitBackingField == nil
    }

    private func needsMemberPropertyRecheck(
        _ property: PropertyDecl,
        nestedClasses: [DeclID]
    ) -> Bool {
        needsAccessorRecheck(property)
            || (!nestedClasses.isEmpty
                && (property.initializer != nil || property.delegateExpression != nil))
    }

    func typeCheckClassLikeMembers(
        memberFunctions: [DeclID],
        memberProperties: [DeclID],
        nestedClasses: [DeclID],
        nestedObjects: [DeclID],
        ctx: TypeInferenceContext,
        propertyInitializerLocals: LocalBindings = [:],
        memberFunctionBaseLocals: LocalBindings = [:],
        nestedClassBaseLocals: LocalBindings = [:],
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        let ast = ctx.ast
        let sema = ctx.sema
        inferClassLikeMemberTypes(
            memberFunctions: memberFunctions,
            memberProperties: memberProperties,
            nestedClasses: nestedClasses,
            ctx: ctx,
            propertyInitializerLocals: propertyInitializerLocals,
            memberFunctionBaseLocals: memberFunctionBaseLocals,
            solver: solver,
            diagnostics: diagnostics
        )

        let diagnosticSnapshot = diagnostics.count
        let nominalDeclsCheckedBefore = driver.localNominalDeclChecks.count
        for declID in nestedObjects {
            guard let decl = ast.arena.decl(declID),
                  case let .objectDecl(objectDecl) = decl,
                  let symbol = sema.bindings.declSymbols[declID],
                  let ownerSymbol = ctx.enclosingClassSymbol,
                  sema.symbols.companionObjectSymbol(for: ownerSymbol) == symbol
            else {
                continue
            }
            typeCheckObjectDecl(
                objectDecl,
                symbol: symbol,
                ctx: ctx.with(currentDeclSymbol: symbol),
                solver: solver,
                diagnostics: diagnostics
            )
        }
        diagnostics.truncate(to: diagnosticSnapshot)
        driver.markLocalNominalRechecks(since: nominalDeclsCheckedBefore)

        for declID in nestedClasses {
            typeCheckNestedClassDecl(
                declID: declID,
                ctx: ctx,
                solver: solver,
                diagnostics: diagnostics,
                baseLocals: nestedClassBaseLocals
            )
        }

        for declID in memberProperties {
            guard case let .propertyDecl(property)? = ast.arena.decl(declID),
                  needsMemberPropertyRecheck(property, nestedClasses: nestedClasses),
                  !driver.precheckedPropertyDecls.contains(declID),
                  let symbol = sema.bindings.declSymbols[declID]
            else {
                continue
            }
            typeCheckBoundPropertyDecl(
                property,
                declID: declID,
                symbol: symbol,
                ctx: ctx.with(currentDeclSymbol: symbol),
                initialLocals: propertyInitializerLocals,
                solver: solver,
                diagnostics: diagnostics
            )
        }

        for declID in memberFunctions {
            guard let decl = ast.arena.decl(declID),
                  case let .funDecl(function) = decl,
                  let symbol = sema.bindings.declSymbols[declID]
            else {
                continue
            }
            typeCheckFunctionDecl(
                function,
                symbol: symbol,
                ctx: ctx.with(currentDeclSymbol: symbol),
                solver: solver,
                diagnostics: diagnostics,
                baseLocals: memberFunctionBaseLocals
            )
        }

        for declID in nestedObjects {
            typeCheckNestedObjectDecl(declID, ctx: ctx, solver: solver, diagnostics: diagnostics)
        }
    }

    func typeCheckNestedObjectDecl(
        _ declID: DeclID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        guard let decl = ctx.ast.arena.decl(declID),
              case let .objectDecl(objectDecl) = decl,
              let symbol = ctx.sema.bindings.declSymbols[declID]
        else {
            return
        }
        typeCheckObjectDecl(
            objectDecl,
            symbol: symbol,
            ctx: ctx.with(currentDeclSymbol: symbol),
            solver: solver,
            diagnostics: diagnostics
        )
    }

    private func memberDeclStartOffset(_ declID: DeclID, ast: ASTModule) -> Int? {
        guard let decl = ast.arena.decl(declID) else { return nil }
        switch decl {
        case let .funDecl(function): return function.range.start.offset
        case let .propertyDecl(property): return property.range.start.offset
        default: return nil
        }
    }

    func typeCheckNestedClassDecl(
        declID: DeclID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine,
        baseLocals: LocalBindings = [:]
    ) {
        guard let decl = ctx.ast.arena.decl(declID),
              let symbol = ctx.sema.bindings.declSymbols[declID]
        else { return }
        switch decl {
        case let .classDecl(classDecl):
            let nestedCtx = ctx.nestedClassContext(isInner: classDecl.isInner)
            typeCheckClassDecl(
                classDecl,
                symbol: symbol,
                ctx: nestedCtx.with(currentDeclSymbol: symbol),
                solver: solver,
                diagnostics: diagnostics,
                baseLocals: classDecl.isInner ? baseLocals : [:]
            )
        case let .interfaceDecl(nestedInterface):
            let nestedCtx = ctx.copying(outerReceiverTypes: [])
            typeCheckInterfaceDecl(
                nestedInterface,
                symbol: symbol,
                ctx: nestedCtx.with(currentDeclSymbol: symbol),
                solver: solver,
                diagnostics: diagnostics
            )
        default:
            break
        }
    }

    private func enclosingClassifierScopeForObject(
        ownerSymbol: SymbolID,
        ctx: TypeInferenceContext
    ) -> Scope? {
        let sema = ctx.sema
        guard let owner = sema.symbols.symbol(ownerSymbol), owner.kind == .object,
              let parentSymbol = sema.symbols.parentSymbol(for: ownerSymbol),
              let parent = sema.symbols.symbol(parentSymbol),
              [.class, .interface, .enumClass, .annotationClass].contains(parent.kind),
              let enclosingScope = ctx.scope as? ClassMemberScope,
              enclosingScope.owner == parentSymbol,
              let outerParent = enclosingScope.parent
        else { return nil }
        let classifiers = ClassMemberScope(
            parent: outerParent,
            symbols: sema.symbols,
            ownerSymbol: parentSymbol,
            thisType: nil
        )
        if parent.kind == .enumClass {
            let valuesName = ctx.interner.intern("values")
            for valuesSymbol in sema.symbols.lookupAll(fqName: parent.fqName + [valuesName]) {
                guard let values = sema.symbols.symbol(valuesSymbol),
                      values.kind == .function,
                      values.flags.contains([.synthetic, .static]),
                      sema.symbols.parentSymbol(for: valuesSymbol) == parentSymbol
                else {
                    continue
                }
                classifiers.insert(valuesSymbol)
            }
            for child in sema.symbols.declaredChildren(of: parentSymbol) {
                guard let childInfo = sema.symbols.symbol(child), childInfo.kind == .field else { continue }
                classifiers.insert(child)
            }
        }
        return classifiers
    }

    func buildClassMemberScope(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        memberFunctions: [DeclID],
        memberProperties: [DeclID],
        nestedClasses: [DeclID],
        nestedObjects: [DeclID],
        ctx: TypeInferenceContext
    ) -> ClassMemberScope {
        let sema = ctx.sema
        func companionMemberScope(of classSymbol: SymbolID, parent: Scope) -> Scope {
            guard let companionSymbol = sema.symbols.companionObjectSymbol(for: classSymbol),
                  sema.symbols.symbol(companionSymbol) != nil
            else {
                return parent
            }

            var inheritedOwnersByDepth: [[SymbolID]] = []
            var pending = sema.symbols.directSupertypes(for: companionSymbol).map { ($0, 1) }
            var visitedOwners: Set<SymbolID> = [companionSymbol]
            var index = 0
            while index < pending.count {
                let (owner, depth) = pending[index]
                index += 1
                guard visitedOwners.insert(owner).inserted,
                      sema.symbols.symbol(owner) != nil
                else {
                    continue
                }
                while inheritedOwnersByDepth.count < depth {
                    inheritedOwnersByDepth.append([])
                }
                inheritedOwnersByDepth[depth - 1].append(owner)
                pending.append(contentsOf: sema.symbols.directSupertypes(for: owner).map { ($0, depth + 1) })
            }

            func insertMembers(
                of owners: [SymbolID],
                into scope: BaseScope,
                inherited: Bool,
                functionsOnly: Bool
            ) {
                for owner in owners {
                    guard sema.symbols.symbol(owner) != nil else { continue }
                    for memberSymbol in sema.symbols.declaredChildren(of: owner) {
                        guard let member = sema.symbols.symbol(memberSymbol),
                              member.kind == .function
                                || !functionsOnly && (member.kind == .property || member.kind == .field
                                    || member.kind == .class || member.kind == .interface
                                    || member.kind == .object || member.kind == .enumClass
                                    || member.kind == .annotationClass || member.kind == .typeAlias),
                              !inherited || member.visibility != .private
                        else {
                            continue
                        }
                        scope.insert(memberSymbol)
                    }
                }
            }

            var memberScopeParent = parent
            for owners in inheritedOwnersByDepth.reversed() {
                let inheritedScope = BaseScope(parent: memberScopeParent, symbols: sema.symbols)
                insertMembers(of: owners, into: inheritedScope, inherited: true, functionsOnly: false)
                memberScopeParent = inheritedScope
            }

            let ownScope = BaseScope(parent: memberScopeParent, symbols: sema.symbols)
            insertMembers(of: [companionSymbol], into: ownScope, inherited: false, functionsOnly: false)
            return ownScope
        }

        var companionScopeParent: Scope = enclosingClassifierScopeForObject(ownerSymbol: ownerSymbol, ctx: ctx) ?? ctx.scope
        if let owner = sema.symbols.symbol(ownerSymbol), owner.kind == .class || owner.kind == .object {
            var inheritedClassSymbols: [SymbolID] = []
            var classQueue = sema.symbols.directSupertypes(for: ownerSymbol).filter {
                sema.symbols.symbol($0)?.kind == .class
            }
            var visitedClasses: Set<SymbolID> = [ownerSymbol]
            while !classQueue.isEmpty {
                let superclass = classQueue.removeFirst()
                guard visitedClasses.insert(superclass).inserted,
                      sema.symbols.symbol(superclass)?.kind == .class
                else {
                    continue
                }
                inheritedClassSymbols.append(superclass)
                classQueue.append(contentsOf: sema.symbols.directSupertypes(for: superclass).filter {
                    sema.symbols.symbol($0)?.kind == .class
                })
            }

            for superclass in inheritedClassSymbols.reversed() {
                companionScopeParent = companionMemberScope(of: superclass, parent: companionScopeParent)
            }
        }
        let companionScope = companionMemberScope(of: ownerSymbol, parent: companionScopeParent)

        let classScope = ClassMemberScope(
            parent: companionScope,
            symbols: sema.symbols,
            ownerSymbol: ownerSymbol,
            thisType: ownerType
        )

        for typeParameterSymbol in sema.types.nominalTypeParameterSymbols(for: ownerSymbol) {
            classScope.insert(typeParameterSymbol)
        }

        for declID in memberFunctions + memberProperties + nestedClasses + nestedObjects {
            if let symbol = sema.bindings.declSymbols[declID] {
                classScope.insert(symbol)
            }
        }

        for forwardingSymbol in sema.symbols.classDelegationForwardingMethodSymbols(forClass: ownerSymbol)
            + sema.symbols.classDelegationForwardingPropertySymbols(forClass: ownerSymbol)
        {
            classScope.insert(forwardingSymbol)
        }

        var ownNames: Set<InternedString> = []
        for declID in nestedClasses + nestedObjects {
            if let symbol = sema.bindings.declSymbols[declID],
               let name = sema.symbols.symbol(symbol)?.name
            {
                ownNames.insert(name)
            }
        }
        var superQueue = sema.symbols.directSupertypes(for: ownerSymbol)
        var visitedSupers: Set<SymbolID> = [ownerSymbol]
        while !superQueue.isEmpty {
            let superSymbol = superQueue.removeFirst()
            guard visitedSupers.insert(superSymbol).inserted,
                  sema.symbols.symbol(superSymbol) != nil
            else {
                continue
            }
            for childSymbol in sema.symbols.declaredChildren(of: superSymbol) {
                if let child = sema.symbols.symbol(childSymbol),
                   child.kind == .class,
                   child.flags.contains(.innerClass),
                   !ownNames.contains(child.name)
                {
                    classScope.insert(childSymbol)
                }
            }
            superQueue.append(contentsOf: sema.symbols.directSupertypes(for: superSymbol))
        }

        if let owner = sema.symbols.symbol(ownerSymbol),
           owner.kind == .enumClass
        {
            let valuesName = ctx.interner.intern("values")
            for valuesSymbol in sema.symbols.lookupAll(fqName: owner.fqName + [valuesName]) {
                guard let values = sema.symbols.symbol(valuesSymbol),
                      values.kind == .function,
                      values.flags.contains([.synthetic, .static]),
                      sema.symbols.parentSymbol(for: valuesSymbol) == ownerSymbol
                else {
                    continue
                }
                classScope.insert(valuesSymbol)
            }

            for childSymbol in sema.symbols.declaredChildren(of: ownerSymbol) {
                if let child = sema.symbols.symbol(childSymbol),
                   child.kind == .field
                {
                    classScope.insert(childSymbol)
                }
            }
        }

        return classScope
    }

    private func typeCheckEnumEntryConstructorArguments(
        _ classDecl: ClassDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        guard !classDecl.enumEntries.isEmpty else {
            return
        }
        let sema = ctx.sema
        guard let owner = sema.symbols.symbol(symbol) else { return }
        let constructorName = ctx.interner.intern("<init>")
        let constructors = sema.symbols.lookupAll(fqName: owner.fqName + [constructorName]).filter { candidate in
            sema.symbols.symbol(candidate)?.kind == .constructor
                && sema.symbols.parentSymbol(for: candidate) == symbol
        }
        let enumType = sema.types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
        let argCtx = ctx.copying(scope: ctx.scope, implicitReceiverType: nil)
        for entry in classDecl.enumEntries {
            let entryFQName = owner.fqName + [entry.name]
            guard let entrySymbol = sema.symbols.lookupAll(fqName: entryFQName).first(where: { candidate in
                sema.symbols.symbol(candidate)?.kind == .field
                    && sema.symbols.parentSymbol(for: candidate) == symbol
            }) else {
                continue
            }

            typeCheckAnnotationFactories(entry.annotations, symbol: entrySymbol, ctx: ctx)

            var delegation = companionHeaderDelegationContext(
                superclassSymbol: symbol,
                ctx: argCtx,
                locals: [:]
            )
            let resolved = inferConstructorDelegationArguments(
                entry.constructorArgs,
                candidates: constructors,
                range: entry.range,
                targetType: enumType,
                ctx: delegation.ctx,
                locals: &delegation.locals
            )
            guard let chosenCallee = resolved.chosenCallee else {
                if resolved.diagnostic == nil {
                    diagnostics.error(
                        "KSWIFTK-SEMA-0250",
                        "Invalid constructor arguments for enum entry '\(ctx.interner.resolve(entry.name))'",
                        range: entry.range
                    )
                }
                continue
            }

            if let signature = sema.symbols.functionSignature(for: chosenCallee) {
                let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
                for (argumentIndex, argument) in entry.constructorArgs.enumerated() {
                    guard let parameterIndex = resolved.parameterMapping[argumentIndex],
                          let contextualType = driver.callChecker.contextualCallArgumentType(
                              argument, parameterIndex: parameterIndex, in: signature, ctx: argCtx
                          )
                    else { continue }
                    let expectedType = sema.types.substituteTypeParameters(
                        in: contextualType,
                        substitution: resolved.substitutedTypeArguments,
                        typeVarBySymbol: typeVarBySymbol
                    )
                    let actualType = driver.inferExpr(
                        argument.expr,
                        ctx: delegation.ctx,
                        locals: &delegation.locals,
                        expectedType: expectedType
                    )
                    driver.emitSubtypeConstraint(
                        left: actualType,
                        right: expectedType,
                        range: ctx.ast.arena.exprRange(argument.expr),
                        solver: solver,
                        sema: sema,
                        diagnostics: diagnostics,
                        diagnosticCode: "KSWIFTK-SEMA-0473",
                        failureMessage: "Argument type mismatch."
                    )
                }
            }
            sema.bindings.bindEnumEntryConstructor(
                entrySymbol,
                binding: CallBinding(
                    chosenCallee: chosenCallee,
                    substitutedTypeArguments: resolved.substitutedTypeArguments
                        .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                        .map(\.value),
                    parameterMapping: resolved.parameterMapping,
                    defaultArgumentOwner: resolved.defaultArgumentOwner
                )
            )
        }
    }
}
