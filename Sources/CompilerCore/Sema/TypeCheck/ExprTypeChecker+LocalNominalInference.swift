extension ExprTypeChecker {
    /// KUU-555: a named `class`/`object` declared as a block statement
    /// (`{ class L { ... } }`). The name binds like a `localFunDecl` — into
    /// `locals`, visible only to statements after it in the same block —
    /// while the nominal's symbols, layout, captures and member type
    /// checking mirror the object-literal pipeline (`ensureObjectLiteralSymbol`).
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
            let objectSymbol = ensureObjectLiteralSymbol(
                declID: declID,
                objectDecl: objectDecl,
                superTypes: objectDecl.superTypes,
                fqNamePrefix: fqNamePrefix,
                symbolKind: .object,
                ctx: ctx,
                locals: &locals
            )
            let objectType = sema.types.make(.classType(ClassType(
                classSymbol: objectSymbol,
                args: [],
                nullability: .nonNull
            )))
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
            let classSymbol = ensureLocalClassSymbol(
                declID: declID,
                classDecl: classDecl,
                fqNamePrefix: fqNamePrefix,
                ctx: ctx,
                locals: &locals
            )
            let classType = sema.types.make(.classType(ClassType(
                classSymbol: classSymbol,
                args: [],
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

    /// Sema registration for a local `class` body statement, mirroring
    /// `ensureObjectLiteralSymbol` for the object side: symbol + ctor
    /// signature + member symbols, member type checking seeded with the
    /// enclosing locals (captures), supertype wiring, and the deferred
    /// layout synthesis — the nominal is discovered too late for
    /// `synthesizeNominalLayouts`, so it builds its own.
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
                      let ownerSymbol = sema.symbols.parentSymbol(for: symbol.id),
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

        let classFQName = fqNamePrefix + [classDecl.name]
        let classSymbol = sema.symbols.define(
            kind: .class,
            name: classDecl.name,
            fqName: classFQName,
            declSite: classDecl.range,
            visibility: .private,
            flags: [.synthetic]
        )
        sema.bindings.bindDecl(declID, symbol: classSymbol)
        sema.symbols.setSourceFileID(ctx.currentFileID, for: classSymbol)

        var directSuperSymbols: [SymbolID] = []
        directSuperSymbols.reserveCapacity(classDecl.superTypeEntries.count)
        var directSuperTypeArgs: [SymbolID: [TypeArg]] = [:]
        for entry in classDecl.superTypeEntries {
            let resolved = driver.helpers.resolveTypeRef(
                entry.typeRef,
                ast: ast,
                sema: sema,
                interner: interner,
                scope: ctx.scope,
                diagnostics: ctx.semaCtx.diagnostics
            )
            if case let .classType(classType) = sema.types.kind(of: resolved) {
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
            ctx.semaCtx.diagnostics.error(
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

        let classType = sema.types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))

        // Primary constructor: a synthetic `.constructor` symbol at the
        // class's decl site so `primaryConstructorParameterLocals` /
        // `typeCheckPrimaryConstructorSuperDelegation` find it via
        // `symbols(atDeclSite:)`, plus one `.valueParameter` per header
        // parameter for `emitPrimaryConstructorPropertyInitializers`.
        let initName = interner.intern("<init>")
        let ctorSymbol = sema.symbols.define(
            kind: .constructor,
            name: initName,
            fqName: classFQName + [initName],
            declSite: classDecl.range,
            visibility: .public,
            flags: [.synthetic]
        )
        sema.symbols.setParentSymbol(classSymbol, for: ctorSymbol)
        var paramTypes: [TypeID] = []
        var paramSymbols: [SymbolID] = []
        for param in classDecl.primaryConstructorParams {
            let paramType: TypeID = if let typeRefID = param.type {
                driver.helpers.resolveTypeRef(
                    typeRefID,
                    ast: ast,
                    sema: sema,
                    interner: interner,
                    scope: ctx.scope,
                    diagnostics: ctx.semaCtx.diagnostics,
                    inferenceContext: ctx,
                    usageRange: classDecl.range
                )
            } else {
                sema.types.anyType
            }
            let paramSymbol = sema.symbols.define(
                kind: .valueParameter,
                name: param.name,
                fqName: classFQName + [initName, param.name],
                declSite: classDecl.range,
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
                valueParameterHasDefaultValues: classDecl.primaryConstructorParams.map(\.hasDefaultValue),
                valueParameterIsVararg: classDecl.primaryConstructorParams.map(\.isVararg)
            ),
            for: ctorSymbol
        )

        let classScope = ClassMemberScope(
            parent: ctx.scope,
            symbols: sema.symbols,
            ownerSymbol: classSymbol,
            thisType: classType
        )
        let propertySymbolsByDecl = registerLocalNominalMemberProperties(
            classDecl.memberProperties,
            ownerFQName: classFQName,
            ownerSymbol: classSymbol,
            ctx: ctx
        )
        for propertySymbol in propertySymbolsByDecl.values {
            classScope.insert(propertySymbol)
        }
        let memberFunctionSymbolsByDecl = collectObjectLiteralMemberFunctions(
            classDecl.memberFunctions,
            memberFQNamePrefix: classFQName,
            objectSymbol: classSymbol,
            objectType: classType,
            objectScope: classScope,
            ctx: ctx
        )
        classScope.insert(ctorSymbol)
        let classCtx = ctx.withOuterReceiver(
            label: classDecl.name,
            type: classType
        ).copying(
            scope: classScope,
            implicitReceiverType: classType,
            enclosingClassSymbol: classSymbol
        )

        // Constructor-parameter locals shadow outer locals of the same name
        // (Kotlin scopes header params inside `<init>`/init blocks/
        // initializers), so merge outer first, ctor params on top.
        let primaryCtorLocals = outerLocalsSnapshot
            .merging(
                driver.declChecker.primaryConstructorParameterLocals(classDecl: classDecl, ctx: classCtx)
            ) { _, new in new }

        // Unlike an object literal (KSP-CAP-018), a local class's superclass
        // constructor arguments are evaluated inside `<init>`, so they infer
        // against ctor-param + captured locals.
        var delegationLocals = primaryCtorLocals
        for entry in classDecl.superTypeEntries {
            for arg in entry.constructorArgs {
                _ = driver.inferExpr(arg.expr, ctx: classCtx, locals: &delegationLocals, expectedType: nil)
            }
        }
        driver.declChecker.typeCheckPrimaryConstructorSuperDelegation(
            classDecl,
            symbol: classSymbol,
            ctx: classCtx,
            extraLocals: outerLocalsSnapshot
        )
        driver.declChecker.typeCheckPrimaryConstructorDefaultValues(
            classDecl,
            ctx: classCtx,
            solver: driver.solver,
            diagnostics: ctx.semaCtx.diagnostics
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
                ctx: classCtx.with(currentDeclSymbol: functionSymbol),
                solver: driver.solver,
                diagnostics: ctx.semaCtx.diagnostics,
                baseLocals: outerLocalsSnapshot
            )
            capturedSymbols.formUnion(driver.captureAnalyzer.collectCapturedOuterSymbols(
                inBody: functionDecl.body,
                ast: ast,
                sema: sema,
                outerSymbols: captureOuterSymbols
            ))
        }
        // Every initializer-side root of a local class (property
        // initializers, `init {}` blocks, superclass ctor args) lowers inside
        // `<init>`, so outer-local references there need capture fields —
        // unlike an object literal where they run inline.
        capturedSymbols.formUnion(collectLocalNominalCaptureSymbols(
            memberProperties: classDecl.memberProperties,
            includePropertyInitializers: true,
            extraBodies: classDecl.initBlocks,
            extraExprRoots: classDecl.superTypeEntries.flatMap(\.constructorArgs).map(\.expr),
            captureOuterSymbols: captureOuterSymbols,
            ast: ast,
            sema: sema
        ))
        bindLocalNominalCaptures(
            capturedSymbols,
            ownerSymbol: classSymbol,
            outerLocalsSnapshot: outerLocalsSnapshot,
            outerReceiverTypes: ctx.outerReceiverTypes,
            sema: sema
        )

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
        return classSymbol
    }
}
