extension DeclTypeChecker {
    func typeCheckBoundPropertyDecl(
        _ property: PropertyDecl,
        declID _: DeclID,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        initialLocals: LocalBindings = [:],
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
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
                if let receiver = signature.receiverType {
                    for parameter in signature.typeParameterSymbols.dropFirst(signature.classTypeParameterCount)
                        where !ctx.sema.types.typeContainsTypeParam(receiver, symbol: parameter) {
                        diagnostics.error("KSWIFTK-SEMA-0005", "Property type parameter must occur in its receiver type.", range: property.range)
                    }
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
        typeCheckEnumEntryConstructorArguments(classDecl, symbol: symbol, ctx: classCtx, solver: solver, diagnostics: diagnostics)
        typeCheckPrimaryConstructorSuperDelegation(classDecl, symbol: symbol, ctx: classCtx)
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
        for entry in classDecl.enumEntries where !entry.memberFunctions.isEmpty || !entry.memberProperties.isEmpty {
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
                nestedClasses: [],
                nestedObjects: [],
                ctx: ctx
            )
            let entryCtx = ctx.copying(
                scope: entryScope,
                implicitReceiverType: enumType,
                currentDeclSymbol: entrySymbol,
                enclosingClassSymbol: enumSymbol
            )
            typeCheckClassLikeMembers(
                memberFunctions: entry.memberFunctions,
                memberProperties: entry.memberProperties,
                nestedClasses: [],
                nestedObjects: [],
                ctx: entryCtx,
                solver: solver,
                diagnostics: diagnostics
            )
        }
    }

    func typeCheckClassDelegation(
        _ classDecl: ClassDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        typeCheckInterfaceDelegation(
            entries: classDecl.superTypeEntries,
            range: classDecl.range,
            symbol: symbol,
            ctx: ctx,
            solver: solver,
            diagnostics: diagnostics
        )
    }

    private func typeCheckInterfaceDelegation(
        entries: [SuperTypeEntry],
        range: SourceRange,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
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
            var locals: LocalBindings = [:]
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
        let sema = ctx.sema
        let objectType = sema.types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))
        let objectScope = buildClassMemberScope(
            ownerSymbol: symbol,
            ownerType: objectType,
            memberFunctions: objectDecl.memberFunctions,
            memberProperties: objectDecl.memberProperties,
            nestedClasses: objectDecl.nestedClasses,
            nestedObjects: objectDecl.nestedObjects,
            ctx: ctx
        )
        let objectLabel = sema.symbols.symbol(symbol)?.name ?? ctx.interner.intern("")
        let objectCtx = ctx.withoutSuspensionContext()
            .withOuterReceiver(label: objectLabel, type: objectType)
            .copying(
                scope: objectScope,
                implicitReceiverType: objectType,
                currentDeclSymbol: symbol,
                enclosingClassSymbol: symbol
            )

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
        var superclassArgumentLocals: LocalBindings = [:]
        bindObjectSuperConstructorCall(
            objectDecl,
            symbol: symbol,
            ctx: ctx,
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

    /// Resolves the superclass constructor named by `object O : Base(args)`
    /// and records the full call binding under the object symbol, so KIR
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
            .filter { sema.symbols.symbol($0)?.kind == .constructor }
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
        let sema = ctx.sema
        var allNestedObjects = interfaceDecl.nestedObjects
        if let companionDeclID = interfaceDecl.companionObject {
            allNestedObjects.append(companionDeclID)
        }
        let interfaceTypeArgs: [TypeArg] = sema.types.nominalTypeParameterSymbols(for: symbol).map {
            .invariant(sema.types.make(.typeParam(TypeParamType(symbol: $0))))
        }
        let interfaceType = sema.types.make(.classType(ClassType(
            classSymbol: symbol, args: interfaceTypeArgs, nullability: .nonNull
        )))
        let interfaceScope = buildClassMemberScope(
            ownerSymbol: symbol,
            ownerType: interfaceType,
            memberFunctions: interfaceDecl.memberFunctions,
            memberProperties: interfaceDecl.memberProperties,
            nestedClasses: interfaceDecl.nestedClasses,
            nestedObjects: allNestedObjects,
            ctx: ctx
        )
        let label = sema.symbols.symbol(symbol)?.name ?? ctx.interner.intern("")
        let interfaceCtx = ctx
            .withOuterReceiver(label: label, type: interfaceType)
            .copying(
                scope: interfaceScope,
                implicitReceiverType: interfaceType,
                currentDeclSymbol: symbol,
                enclosingClassSymbol: symbol
            )

        if let companionDeclID = interfaceDecl.companionObject {
            let diagnosticSnapshot = diagnostics.count
            inferClassLikeMemberTypes(
                memberFunctions: interfaceDecl.memberFunctions,
                memberProperties: interfaceDecl.memberProperties,
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
                typeCheckBoundPropertyDecl(
                    property,
                    declID: declID,
                    symbol: symbol,
                    ctx: ctx.with(currentDeclSymbol: symbol),
                    initialLocals: propertyInitializerLocals,
                    solver: solver,
                    diagnostics: diagnostics
                )

            default:
                continue
            }
        }
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

    private func typeCheckNestedObjectDecl(
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

    private func typeCheckNestedClassDecl(
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
            // Inner classes inherit outer receiver context (can use this@Outer).
            // Non-inner nested classes are effectively static: clear outer receivers.
            let nestedCtx: TypeInferenceContext = classDecl.isInner ? ctx : ctx.copying(outerReceiverTypes: [])
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

    // MARK: - Class Member Scope Building

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
        let companionScope = BaseScope(parent: ctx.scope, symbols: sema.symbols)
        if let companionSymbol = sema.symbols.companionObjectSymbol(for: ownerSymbol),
           let companion = sema.symbols.symbol(companionSymbol)
        {
            for memberSymbol in sema.symbols.children(ofFQName: companion.fqName) {
                guard let member = sema.symbols.symbol(memberSymbol),
                      member.kind == .property || member.kind == .field || member.kind == .function
                else {
                    continue
                }
                companionScope.insert(memberSymbol)
            }
        }
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

        // Enum entries are not in memberFunctions/memberProperties/nested*,
        // but they must be visible without qualification inside the enum class
        // and inside its companion object (e.g. `A` in `companion object { fun pick(): D = A }`).
        if let owner = sema.symbols.symbol(ownerSymbol),
           owner.kind == .enumClass
        {
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

    /// Type-checks enum entry constructor argument expressions against the
    /// primary constructor parameter types. Without this the expressions are
    /// never visited by Sema, so KIR lowering cannot resolve constants or
    /// produce correct type information for constructor property dispatch.
    private func typeCheckEnumEntryConstructorArguments(
        _ classDecl: ClassDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        guard !classDecl.enumEntries.isEmpty,
              !classDecl.primaryConstructorParams.isEmpty
        else {
            return
        }
        let sema = ctx.sema
        let primaryCtorSymbol = sema.symbols.symbols(atDeclSite: classDecl.range)
            .compactMap { sema.symbols.symbol($0) }
            .first { $0.kind == .constructor }
        guard let primaryCtorSymbol,
              let signature = sema.symbols.functionSignature(for: primaryCtorSymbol.id)
        else {
            return
        }

        let argCtx = ctx.copying(scope: ctx.scope, implicitReceiverType: nil)
        let parameterNames = classDecl.primaryConstructorParams.map(\.name)
        for entry in classDecl.enumEntries {
            // Named entry arguments (`X(g = 1, r = 2)`) bind by label, exactly
            // like an ordinary constructor call; checking them positionally
            // validated each argument against the wrong parameter type.
            let (argumentIndexByParameter, unmatched) = entry.constructorArgumentMapping(
                parameterNames: parameterNames
            )
            if !unmatched.isEmpty {
                diagnostics.error(
                    "KSWIFTK-SEMA-0250",
                    "Enum entry '\(ctx.interner.resolve(entry.name))' has too many constructor arguments",
                    range: entry.range
                )
            }
            for (paramIndex, argIndex) in argumentIndexByParameter.enumerated() {
                guard let argIndex, paramIndex < signature.parameterTypes.count else { continue }
                let arg = entry.constructorArgs[argIndex]
                let paramType = signature.parameterTypes[paramIndex]
                var locals: LocalBindings = [:]
                let argType = driver.inferExpr(arg.expr, ctx: argCtx, locals: &locals, expectedType: paramType)
                driver.emitSubtypeConstraint(
                    left: argType,
                    right: paramType,
                    range: ctx.ast.arena.exprRange(arg.expr),
                    solver: solver,
                    sema: sema,
                    diagnostics: diagnostics
                )
            }
        }
    }
}
