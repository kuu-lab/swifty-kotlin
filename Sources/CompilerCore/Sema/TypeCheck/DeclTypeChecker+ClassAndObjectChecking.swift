extension DeclTypeChecker {
    func typeCheckBoundPropertyDecl(
        _ property: PropertyDecl,
        declID: DeclID,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        initialLocals: LocalBindings = [:],
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
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
                if !hasNewErrors,
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
            diagnostics: diagnostics
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
        diagnostics: DiagnosticEngine
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
        if let companionDeclID = classDecl.companionObject {
            // Infer both sides first: companion bodies may use inferred instance members.
            let diagnosticSnapshot = diagnostics.count
            inferClassLikeMemberTypes(
                memberFunctions: classDecl.memberFunctions,
                memberProperties: classDecl.memberProperties,
                nestedClasses: classDecl.nestedClasses,
                ctx: classCtx,
                propertyInitializerLocals: primaryCtorLocals,
                solver: solver,
                diagnostics: diagnostics
            )
            typeCheckNestedObjectDecl(companionDeclID, ctx: classCtx, solver: solver, diagnostics: diagnostics)
            diagnostics.truncate(to: diagnosticSnapshot)
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
            propertyInitializerLocals: primaryCtorLocals,
            solver: solver,
            diagnostics: diagnostics
        )
        typeCheckInitBlocks(classDecl.initBlocks, ctx: classCtx, baseLocals: primaryCtorLocals)
        typeCheckPrimaryConstructorDefaultValues(classDecl, ctx: classCtx, solver: solver, diagnostics: diagnostics)
        if classDecl.modifiers.contains(.annotationClass) {
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
            outerReceiversToKeep: ctx.singletonObjectOuterReceivers
        )
        let explicitSuperclassSymbol = explicitClassSuperclassSymbol(classDecl, ctx: classCtx)
        typeCheckSecondaryConstructors(
            classDecl.secondaryConstructors,
            ctx: classCtx,
            solver: solver,
            diagnostics: diagnostics,
            ownerSymbol: symbol,
            hasPrimaryConstructor: classDecl.hasPrimaryConstructorSyntax,
            explicitSuperclassSymbol: explicitSuperclassSymbol
        )
        typeCheckClassDelegation(classDecl, symbol: symbol, ctx: classCtx, solver: solver, diagnostics: diagnostics)
        typeCheckEnumEntryMemberBodies(
            classDecl,
            enumSymbol: symbol,
            enumType: classType,
            ctx: classCtx,
            solver: solver,
            diagnostics: diagnostics
        )
    }

    /// Type-checks functions declared in enum entry bodies with the enum type as
    /// their receiver. The runtime representation is still the enum ordinal;
    /// the separate entry scope only keeps these implementations out of normal
    /// enum-member lookup until the ordinal dispatch helper is selected.
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

        // Superclass constructor arguments are evaluated in the enclosing
        // declaration scope, so visit them before lowering can emit the
        // constructor call. This also records constant-property bindings for
        // expressions such as `Base64(STANDARD_ALPHABET, 0)`.
        // They run before this object is initialized, so `this` and the
        // enclosing instance's members stay out of scope; only enclosing
        // singleton objects (and other kept outer receivers) remain —
        // `object Inner : Base(this.foo())` inside `object Outer` resolves
        // `this` to Outer, while the same expression inside a class is
        // rejected (KUU-3595).
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

    /// Records the full call binding under the object symbol, so KIR
    /// lowering can apply the same named-argument / default normalization as
    /// for a class header's `super(...)` call
    /// (`typeCheckPrimaryConstructorSuperDelegation`).
    func bindObjectSuperConstructorCall(
        _ objectDecl: ObjectDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) {
        let sema = ctx.sema
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
        let resolved = inferConstructorDelegationArguments(
            objectDecl.superTypeConstructorArgs,
            candidates: candidates,
            range: objectDecl.range,
            targetType: constructorSuperclassType(
                ownerSymbol: symbol, superclassSymbol: superclassSymbol, ctx: ctx
            ),
            ctx: ctx,
            locals: &locals
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
                typeCheckFunctionDecl(
                    function,
                    symbol: symbol,
                    ctx: ctx.with(currentDeclSymbol: symbol),
                    solver: solver,
                    diagnostics: diagnostics
                )
                diagnostics.truncate(to: diagnosticSnapshot)

            case let .propertyDecl(property):
                guard !driver.precheckedPropertyDecls.contains(declID) else {
                    continue
                }
                let diagnosticSnapshot = diagnostics.count
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
                    // Keep speculative diagnostics for properties that can
                    // depend on inferred nested member returns until their
                    // bodies have been checked.
                    diagnostics.truncate(to: diagnosticSnapshot)
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
            solver: solver,
            diagnostics: diagnostics
        )

        // Infer companion types before the authoritative function pass;
        // companion bodies can in turn depend on those function return types.
        let diagnosticSnapshot = diagnostics.count
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

        // Nested types can also expose inferred companion properties. Resolve
        // them before enclosing functions see the header's `Any?` placeholder.
        for declID in nestedClasses {
            typeCheckNestedClassDecl(declID: declID, ctx: ctx, solver: solver, diagnostics: diagnostics)
        }

        // Recheck properties after nested classes publish inferred member
        // return types. Initializers and delegates can use those returns to
        // determine their own types, including the effective delegate returned
        // by provideDelegate.
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
                diagnostics: diagnostics
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
        diagnostics: DiagnosticEngine
    ) {
        guard let decl = ctx.ast.arena.decl(declID),
              let symbol = ctx.sema.bindings.declSymbols[declID]
        else { return }
        switch decl {
        case let .classDecl(classDecl):
            // Non-inner nested classes do not capture instances, while singleton objects remain lexical receivers.
            let nestedCtx = ctx.nestedClassContext(isInner: classDecl.isInner)
            typeCheckClassDecl(
                classDecl,
                symbol: symbol,
                ctx: nestedCtx.with(currentDeclSymbol: symbol),
                solver: solver,
                diagnostics: diagnostics
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
                    guard let ownerInfo = sema.symbols.symbol(owner) else { continue }
                    for memberSymbol in sema.symbols.children(ofFQName: ownerInfo.fqName) {
                        guard let member = sema.symbols.symbol(memberSymbol),
                              member.kind == .function
                                || !functionsOnly && (member.kind == .property || member.kind == .field),
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
                insertMembers(of: owners, into: inheritedScope, inherited: true, functionsOnly: true)
                memberScopeParent = inheritedScope
            }

            let ownScope = BaseScope(parent: memberScopeParent, symbols: sema.symbols)
            insertMembers(of: [companionSymbol], into: ownScope, inherited: false, functionsOnly: false)
            return ownScope
        }

        // A class inherits the unqualified companion shorthand of its class
        // supertypes. Keep each superclass in its own scope so the nearest
        // companion wins while lookup continues through the rest of the chain.
        var companionScopeParent: Scope = ctx.scope
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

        // Property initializers (and accessors) are checked directly in this
        // scope rather than a function scope, so the class's own type
        // parameters must be visible for explicit type arguments such as
        // `val items = mutableListOf<T>()` to resolve.
        for typeParameterSymbol in sema.types.nominalTypeParameterSymbols(for: ownerSymbol) {
            classScope.insert(typeParameterSymbol)
        }

        for declID in memberFunctions + memberProperties + nestedClasses + nestedObjects {
            if let symbol = sema.bindings.declSymbols[declID] {
                classScope.insert(symbol)
            }
        }

        // Class delegation forwarders are synthetic symbols, not AST members,
        // but must be visible to unqualified calls in the delegating class body.
        for forwardingSymbol in sema.symbols.classDelegationForwardingMethodSymbols(forClass: ownerSymbol)
            + sema.symbols.classDelegationForwardingPropertySymbols(forClass: ownerSymbol)
        {
            classScope.insert(forwardingSymbol)
        }

        // Inner classes declared in a supertype are inherited members, so
        // `Inner(...)` resolves without qualification in a derived class.
        // Own declarations shadow inherited ones of the same name.
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
                  let superInfo = sema.symbols.symbol(superSymbol)
            else {
                continue
            }
            for childSymbol in sema.symbols.children(ofFQName: superInfo.fqName) {
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

        // Enum entries are not in memberFunctions/memberProperties/nested*,
        // but they must be visible without qualification inside the enum class
        // and inside its companion object (e.g. `A` in `companion object { fun pick(): D = A }`).
        if let owner = sema.symbols.symbol(ownerSymbol),
           owner.kind == .enumClass
        {
            // `values()` is a synthetic static member rather than an AST
            // declaration. Header collection inserts it into its class scope,
            // so preserve it when rebuilding the scope used for member bodies
            // and companion initializers.
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

            for childSymbol in sema.symbols.children(ofFQName: owner.fqName) {
                if let child = sema.symbols.symbol(childSymbol),
                   child.kind == .field
                {
                    classScope.insert(childSymbol)
                }
            }
        }

        return classScope
    }

    /// Resolves and type-checks each enum entry's constructor call. Without
    /// this the expressions are never visited by Sema, and lowering cannot
    /// use the selected constructor or its argument-to-parameter mapping.
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

            // Enum entry arguments are constructor calls in the enum's lexical
            // scope. Use the same candidate preparation, overload selection,
            // literal adaptation, and contextual lambda inference as an
            // ordinary constructor call, then retain its exact mapping for KIR.
            var locals: LocalBindings = [:]
            let resolved = inferConstructorDelegationArguments(
                entry.constructorArgs,
                candidates: constructors,
                range: entry.range,
                targetType: enumType,
                ctx: argCtx,
                locals: &locals
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
                        argument.expr, ctx: argCtx, locals: &locals, expectedType: expectedType
                    )
                    driver.emitSubtypeConstraint(
                        left: actualType,
                        right: expectedType,
                        range: ctx.ast.arena.exprRange(argument.expr),
                        solver: solver,
                        sema: sema,
                        diagnostics: diagnostics
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
