
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
        let propertyCtx = ctx.with(currentDeclSymbol: symbol)
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

    func typeCheckClassDecl(
        _ classDecl: ClassDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        let sema = ctx.sema
        var allNestedObjects = classDecl.nestedObjects
        if let companionDeclID = classDecl.companionObject {
            allNestedObjects.append(companionDeclID)
        }
        // Mirror the header pass: a generic class's `this` type carries its own
        // type parameters as arguments. Member functions get this through their
        // signature receiver type, but property accessors fall back to the
        // context's implicit receiver, so a raw type here would make calls like
        // `f(this)` (where `f` takes `C<T>`) fail to resolve.
        let classTypeArgs: [TypeArg] = sema.types.nominalTypeParameterSymbols(for: symbol).map {
            .invariant(sema.types.make(.typeParam(TypeParamType(symbol: $0))))
        }
        let classType = sema.types.make(.classType(ClassType(
            classSymbol: symbol, args: classTypeArgs, nullability: .nonNull
        )))
        let classScope = buildClassMemberScope(
            ownerSymbol: symbol,
            ownerType: classType,
            memberFunctions: classDecl.memberFunctions,
            memberProperties: classDecl.memberProperties,
            nestedClasses: classDecl.nestedClasses,
            nestedObjects: allNestedObjects,
            ctx: ctx
        )
        let classLabel = sema.symbols.symbol(symbol)?.name ?? ctx.interner.intern("")
        let classCtx = ctx
            .withOuterReceiver(label: classLabel, type: classType)
            .copying(
                scope: classScope,
                implicitReceiverType: classType,
                currentDeclSymbol: symbol,
                enclosingClassSymbol: symbol
            )

        validateClassLikeHeaderOptInTypes(
            symbol: symbol,
            ctx: classCtx,
            range: classDecl.range
        )

        // Primary constructor parameters without `val`/`var` are only in scope
        // for property initializers and `init {}` blocks, not for member
        // functions — so they're threaded through as `locals` rather than
        // inserted into `classScope`.
        let primaryCtorLocals = primaryConstructorParameterLocals(classDecl: classDecl, ctx: classCtx)

        typeCheckInitBlocks(classDecl.initBlocks, ctx: classCtx, baseLocals: primaryCtorLocals)
        typeCheckPrimaryConstructorDefaultValues(classDecl, ctx: classCtx, solver: solver, diagnostics: diagnostics)
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
    }

    func typeCheckClassDelegation(
        _ classDecl: ClassDecl,
        symbol _: SymbolID,
        ctx: TypeInferenceContext,
        solver _: ConstraintSolver,
        diagnostics _: DiagnosticEngine
    ) {
        let sema = ctx.sema
        let delegatedEntries = classDecl.superTypeEntries.filter { $0.delegateExpression != nil }
        guard !delegatedEntries.isEmpty else { return }

        var delegationCtx = ctx
        let ctorSymbols = sema.symbols.symbols(atDeclSite: classDecl.range)
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
            _ = driver.inferExpr(
                expr,
                ctx: delegationCtx,
                locals: &locals,
                expectedType: nil
            )
        }
    }

    func typeCheckObjectDecl(
        _ objectDecl: ObjectDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
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
        let objectCtx = ctx
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

        typeCheckInitBlocks(objectDecl.initBlocks, ctx: objectCtx)
        typeCheckClassLikeMembers(
            memberFunctions: objectDecl.memberFunctions,
            memberProperties: objectDecl.memberProperties,
            nestedClasses: objectDecl.nestedClasses,
            nestedObjects: objectDecl.nestedObjects,
            ctx: objectCtx,
            solver: solver,
            diagnostics: diagnostics
        )
    }

    func typeCheckInterfaceDecl(
        _ interfaceDecl: InterfaceDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
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

        for declID in nestedClasses {
            typeCheckNestedClassDecl(declID: declID, ctx: ctx, solver: solver, diagnostics: diagnostics)
        }

        for declID in nestedObjects {
            guard let decl = ast.arena.decl(declID),
                  case let .objectDecl(objectDecl) = decl,
                  let symbol = sema.bindings.declSymbols[declID]
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
        let classScope = ClassMemberScope(
            parent: ctx.scope,
            symbols: sema.symbols,
            ownerSymbol: ownerSymbol,
            thisType: ownerType
        )

        for declID in memberFunctions + memberProperties + nestedClasses + nestedObjects {
            if let symbol = sema.bindings.declSymbols[declID] {
                classScope.insert(symbol)
            }
        }

        // Make companion properties available as unqualified names inside the
        // owning class/interface scope (e.g. `MAX_COUNT` instead of
        // `Companion.MAX_COUNT`).
        if let companionSymbol = sema.symbols.companionObjectSymbol(for: ownerSymbol),
           let companion = sema.symbols.symbol(companionSymbol)
        {
            for memberSymbol in sema.symbols.children(ofFQName: companion.fqName) {
                guard let member = sema.symbols.symbol(memberSymbol),
                      member.kind == .property || member.kind == .field
                else {
                    continue
                }
                classScope.insert(memberSymbol)
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
        for entry in classDecl.enumEntries {
            for (index, arg) in entry.constructorArgs.enumerated() {
                guard index < signature.parameterTypes.count else {
                    diagnostics.error(
                        "KSWIFTK-SEMA-0250",
                        "Enum entry '\(ctx.interner.resolve(entry.name))' has too many constructor arguments",
                        range: entry.range
                    )
                    break
                }
                let paramType = signature.parameterTypes[index]
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
