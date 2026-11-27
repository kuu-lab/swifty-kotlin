
extension ExprTypeChecker {
    func inferObjectLiteralExpr(
        _ id: ExprID,
        superTypes: [TypeRefID],
        declID: DeclID?,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner

        guard let declID,
              let decl = ast.arena.decl(declID),
              case let .objectDecl(objectDecl) = decl
        else {
            if let firstSuperType = superTypes.first {
                let resolved = driver.helpers.resolveTypeRef(
                    firstSuperType,
                    ast: ast,
                    sema: sema,
                    interner: interner,
                    diagnostics: ctx.sema.diagnostics
                )
                sema.bindings.bindExprType(id, type: resolved)
                return resolved
            }
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }

        let objectSymbol = ensureObjectLiteralSymbol(
            declID: declID,
            objectDecl: objectDecl,
            superTypes: superTypes,
            ctx: ctx,
            locals: &locals
        )
        let objectType = objectLiteralType(for: objectSymbol, sema: sema)
        sema.bindings.bindExprType(id, type: objectType)
        return objectType
    }

    func ensureObjectLiteralSymbol(
        declID: DeclID,
        objectDecl: ObjectDecl,
        superTypes: [TypeRefID],
        fqNamePrefix: [InternedString] = [],
        symbolKind: SymbolKind = .class,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> SymbolID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner

        let pendingRecheck = driver.pendingLocalNominalRechecks.remove(declID) != nil
        if let existing = sema.bindings.declSymbols[declID],
           driver.predeclaredObjectLiteralDecls.remove(declID) == nil,
           !pendingRecheck
        {
            return existing
        }

        let outerLocalsSnapshot = locals
        let outerSymbols = Set(outerLocalsSnapshot.values.map(\.symbol))

        // KSP-CAP-001: an object-literal member function can also resolve a
        // bare name through the enclosing class receiver. Include stored
        // properties owned by that receiver (and its class supertypes) in the
        // capture set so the member function does not later read the same
        // field offset from the object literal's own receiver.
        // BUG-inner-outer: a property or `this@Label` on an enclosing class
        // reachable only through two or more `inner class` `$outer` hops
        // (e.g. an object literal inside `inner class Deep` inside `inner
        // class Inner` inside `class Outer`, referencing `Outer`'s own
        // property) is otherwise never collected here -- only the
        // *immediate* enclosing class is. Walk the chain of enclosing
        // classes while each visited class is itself `inner` (that is what
        // gives it an `$outer` field to hop through) so every ancestor
        // reachable that way is treated the same as the immediate one below.
        var outerClassChain: [SymbolID] = []
        if let enclosingClassSymbol = ctx.enclosingClassSymbol {
            var current = enclosingClassSymbol
            while sema.symbols.symbol(current)?.flags.contains(.innerClass) == true,
                  let outerOwner = sema.symbols.parentSymbol(for: current),
                  sema.symbols.symbol(outerOwner)?.kind == .class
            {
                outerClassChain.append(outerOwner)
                current = outerOwner
            }
        }
        var outerReceiverOwners: Set<SymbolID> = []
        var pendingOuterReceiverOwners: [SymbolID] = outerClassChain
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
                      sema.symbols.symbol(ownerSymbol)?.kind == .class
                else {
                    return nil
                }
                return symbol.id
            }
        )
        let mutableOuterReceiverPropertySymbols = Set(outerReceiverPropertySymbols.filter {
            sema.symbols.symbol($0)?.flags.contains(.mutable) == true
        })
        var captureOuterSymbols = outerSymbols
            .union(outerReceiverPropertySymbols)
            .union(ctx.outerReceiverTypes.compactMap(\.symbol))
            .union(ctx.implicitReceiverStack.map(\.symbol))
            .union(driver.helpers.lexicalTypeParameterSymbols(in: ctx).filter {
                sema.symbols.symbol($0)?.flags.contains(.reifiedTypeParameter) == true
            })
        if let enclosingClassSymbol = ctx.enclosingClassSymbol {
            captureOuterSymbols.insert(enclosingClassSymbol)
        }
        captureOuterSymbols.formUnion(outerClassChain)

        let objectSymbol = predeclareObjectLiteralSymbol(
            declID: declID,
            objectDecl: objectDecl,
            superTypes: superTypes,
            fqNamePrefix: fqNamePrefix,
            symbolKind: symbolKind,
            ctx: ctx
        )
        driver.predeclaredObjectLiteralDecls.remove(declID)
        if driver.sourceManager?.origin(of: ctx.currentFileID)?.isBundledStdlib != true {
            driver.localNominalDeclChecks.append(declID)
        }
        let directSuperSymbols = sema.symbols.directSupertypes(for: objectSymbol)
        let inheritance = DataFlowSemaPhase()

        var lexicalEnclosingFQNames: [[InternedString]] = []
        var lexicalScope: Scope? = ctx.scope
        while let scope = lexicalScope as? BaseScope {
            if let memberScope = scope as? ClassMemberScope,
               let owner = sema.symbols.symbol(memberScope.owner) {
                lexicalEnclosingFQNames.append(owner.fqName)
            }
            lexicalScope = scope.parent
        }
        let enclosingClassScopes = Array(lexicalEnclosingFQNames.reversed())
        var lexicalReceiverSymbols = Set(ctx.outerReceiverTypes.compactMap(\.symbol))
        lexicalReceiverSymbols.formUnion(ctx.implicitReceiverStack.map(\.symbol))
        if let implicitReceiverType = ctx.implicitReceiverType,
           let receiverSymbol = driver.helpers.nominalSymbol(
               of: sema.types.makeNonNullable(implicitReceiverType),
               types: sema.types
           ) {
            lexicalReceiverSymbols.insert(receiverSymbol)
        }
        for superSymbol in directSuperSymbols {
            inheritance.validateInnerClassSupertypeReceiver(
                resolvedSymbol: superSymbol,
                context: .lexical,
                declRange: objectDecl.range,
                declSymbol: objectSymbol,
                enclosingClassScopes: enclosingClassScopes,
                lexicalReceiverSymbols: lexicalReceiverSymbols,
                symbols: sema.symbols,
                types: sema.types,
                diagnostics: sema.diagnostics,
                sourceManager: ctx.visibilityChecker.sourceManager,
                interner: interner
            )
        }

        for entry in objectDecl.superTypeEntries {
            guard let delegateExpr = entry.delegateExpression else { continue }
            let interfaceType = driver.helpers.resolveTypeRef(
                entry.typeRef,
                ast: ast,
                sema: sema,
                interner: interner,
                scope: ctx.scope,
                diagnostics: ctx.sema.diagnostics,
                usageRange: entry.range ?? objectDecl.range
            )
            let field = inheritance.registerClassDelegation(
                delegateExpression: delegateExpr,
                interfaceType: interfaceType,
                classSymbol: objectSymbol,
                range: objectDecl.range,
                symbols: sema.symbols,
                types: sema.types,
                diagnostics: ctx.sema.diagnostics,
                interner: interner
            )
            let expectedType = field.flatMap { sema.symbols.propertyType(for: $0) }
            let delegateType = driver.inferExpr(delegateExpr, ctx: ctx, locals: &locals, expectedType: expectedType)
            if let expectedType {
                driver.emitSubtypeConstraint(
                    left: delegateType,
                    right: expectedType,
                    range: ast.arena.exprRange(delegateExpr),
                    solver: driver.solver,
                    sema: sema,
                    diagnostics: ctx.sema.diagnostics
                )
            }
        }

        // KSP-CAP-018: the superclass constructor call's arguments
        // (`object : Base(x) { ... }`) are evaluated in the *enclosing*
        // scope — same as a class header's `: Base(x)` — so they are
        // type-checked against the outer `ctx`/`locals`, not `objectScope`
        // below. Without this, `arg.expr` reaches KIR lowering with no type
        // binding or resolved symbol reference and lowers to a stray value.
        driver.declChecker.bindObjectSuperConstructorCall(
            objectDecl, symbol: objectSymbol, ctx: ctx, locals: &locals
        )

        let propertySymbolsByDecl = registerLocalNominalMemberProperties(
            objectDecl.memberProperties,
            ownerFQName: fqNamePrefix + [objectDecl.name],
            ownerSymbol: objectSymbol,
            ctx: ctx
        )

        let objectSymbolFQName = fqNamePrefix + [objectDecl.name]
        let objectType = objectLiteralType(for: objectSymbol, sema: sema)
        let objectScope = ClassMemberScope(
            parent: ctx.scope,
            symbols: sema.symbols,
            ownerSymbol: objectSymbol,
            thisType: objectType
        )
        if let compilationContext = driver.compilationContext {
            var nestedEnclosingTypeParameters: [InternedString: SymbolID] = [:]
            for typeParameterSymbol in driver.helpers.lexicalTypeParameterSymbols(in: ctx) {
                guard let name = sema.symbols.symbol(typeParameterSymbol)?.name,
                      nestedEnclosingTypeParameters[name] == nil,
                      let visibleSymbol = driver.helpers.resolveTypeParameterSymbol(
                          name, scope: objectScope, sema: sema
                      )
                else {
                    continue
                }
                nestedEnclosingTypeParameters[name] = visibleSymbol
            }
            let nestedClassTypeParameterSymbols = sema.types.nominalTypeParameterSymbols(for: objectSymbol)
            let uncollectedNestedClasses = objectDecl.nestedClasses.filter { sema.bindings.declSymbols[$0] == nil }
            let uncollectedNestedObjects = objectDecl.nestedObjects.filter { sema.bindings.declSymbols[$0] == nil }
            for nestedDeclID in objectDecl.nestedClasses + objectDecl.nestedObjects {
                if let existingNested = sema.bindings.declSymbols[nestedDeclID] {
                    objectScope.insert(existingNested)
                }
            }
            if !uncollectedNestedClasses.isEmpty || !uncollectedNestedObjects.isEmpty {
                DataFlowSemaPhase().collectMemberHeaders(
                    members: MemberDeclarations(
                        functions: [],
                        properties: [],
                        nestedClasses: uncollectedNestedClasses,
                        nestedObjects: uncollectedNestedObjects
                    ),
                    owner: OwnerContext(
                        fqName: objectSymbolFQName,
                        symbol: objectSymbol,
                        type: objectType
                    ),
                    sourceFileID: ctx.currentFileID,
                    ctx: compilationContext,
                    ast: ast,
                    symbols: sema.symbols,
                    types: sema.types,
                    bindings: sema.bindings,
                    scope: objectScope,
                    diagnostics: sema.diagnostics,
                    interner: interner,
                    classTypeParameterSymbols: nestedClassTypeParameterSymbols,
                    classLocalTypeParameters: nestedEnclosingTypeParameters
                )

                var nestedEnclosingClassScopes = enclosingClassScopes
                nestedEnclosingClassScopes.append(objectSymbolFQName)
                if let sourceFile = ast.file(for: ctx.currentFileID) {
                    for nestedDeclID in uncollectedNestedClasses + uncollectedNestedObjects {
                        DataFlowSemaPhase().bindInheritanceEdges(
                            declID: nestedDeclID,
                            currentPackage: sourceFile.packageFQName,
                            imports: sourceFile.imports,
                            enclosingTypeParameters: nestedEnclosingTypeParameters,
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
            }
        }
        for propertySymbol in propertySymbolsByDecl.values {
            objectScope.insert(propertySymbol)
        }
        let memberFunctionSymbolsByDecl = collectObjectLiteralMemberFunctions(
            objectDecl.memberFunctions,
            memberFQNamePrefix: objectSymbolFQName,
            objectSymbol: objectSymbol,
            objectType: objectType,
            classTypeParameterSymbols: sema.types.nominalTypeParameterSymbols(for: objectSymbol),
            limitsClassTypeParameterPrefixToMemberSurface: true,
            objectScope: objectScope,
            ctx: ctx
        )
        if !pendingRecheck {
            inheritance.synthesizeDelegationForwardingForClass(
                range: objectDecl.range,
                memberFunctions: objectDecl.memberFunctions,
                memberProperties: objectDecl.memberProperties,
                classSymbol: objectSymbol,
                classFQName: objectSymbolFQName,
                symbols: sema.symbols,
                bindings: sema.bindings,
                types: sema.types,
                interner: interner
            )
        }
        for symbol in sema.symbols.classDelegationForwardingMethodSymbols(forClass: objectSymbol)
            + sema.symbols.classDelegationForwardingPropertySymbols(forClass: objectSymbol)
        {
            objectScope.insert(symbol)
        }
        var objectOuterReceiverTypes = ctx.outerReceiverTypes
        let thisBinding = outerLocalsSnapshot[ctx.interner.intern("this")]
        if let enclosingClassSymbol = ctx.enclosingClassSymbol {
            let memberExtensionDispatchSymbol = ctx.enclosingFunctionSymbol.flatMap { functionSymbol -> SymbolID? in
                guard sema.symbols.memberExtensionOwnerSymbol(for: functionSymbol) == enclosingClassSymbol else {
                    return nil
                }
                return SyntheticSymbolScheme.receiverParameterSymbol(for: enclosingClassSymbol)
            }
            let enclosingMemberReceiverSymbol = ctx.enclosingFunctionSymbol.flatMap { functionSymbol -> SymbolID? in
                guard sema.symbols.memberExtensionOwnerSymbol(for: functionSymbol) == nil,
                      sema.symbols.parentSymbol(for: functionSymbol) == enclosingClassSymbol
                else {
                    return nil
                }
                return SyntheticSymbolScheme.receiverParameterSymbol(for: functionSymbol)
            }
            for index in objectOuterReceiverTypes.indices {
                let entry = objectOuterReceiverTypes[index]
                guard entry.symbol == enclosingClassSymbol,
                      case let .classType(entryClassType) = sema.types.kind(of: entry.type),
                      entryClassType.classSymbol == enclosingClassSymbol
                else {
                    continue
                }
                let receiverValueSymbol: SymbolID
                if let memberExtensionDispatchSymbol {
                    receiverValueSymbol = memberExtensionDispatchSymbol
                } else if let thisBinding,
                          entry.type == thisBinding.type,
                          SyntheticSymbolScheme.receiverParameterOwner(for: thisBinding.symbol) != nil
                {
                    receiverValueSymbol = thisBinding.symbol
                } else if let enclosingMemberReceiverSymbol {
                    receiverValueSymbol = enclosingMemberReceiverSymbol
                } else {
                    continue
                }
                objectOuterReceiverTypes[index].symbol = receiverValueSymbol
                captureOuterSymbols.insert(receiverValueSymbol)
            }
        }
        if let thisBinding {
            for index in objectOuterReceiverTypes.indices
                where objectOuterReceiverTypes[index].type == thisBinding.type
                && objectOuterReceiverTypes[index].symbol == nil
            {
                objectOuterReceiverTypes[index].symbol = thisBinding.symbol
            }
        }
        for index in objectOuterReceiverTypes.indices where objectOuterReceiverTypes[index].symbol == nil {
            guard let (_, classSymbol) = resolveClassTypeSymbol(objectOuterReceiverTypes[index].type, sema: sema),
                  outerClassChain.contains(classSymbol.id)
            else {
                continue
            }
            objectOuterReceiverTypes[index].symbol = classSymbol.id
        }
        objectOuterReceiverTypes.append((label: objectDecl.name, type: objectType, symbol: objectSymbol))
        let objectCtx = ctx.withoutSuspensionContext().copying(
            scope: objectScope,
            implicitReceiverType: objectType,
            enclosingClassSymbol: objectSymbol,
            outerReceiverTypes: objectOuterReceiverTypes
        )

        // KUU-4595: an expression-bodied member function keeps the `Any`
        // return placeholder collected in `collectObjectLiteralMemberFunctions`
        // until its body is checked at the end of this pass, but member
        // property initializers and `by lazy` lambdas below can already call
        // it. Register each for the same on-demand return inference named
        // members get, seeded with the outer locals the authoritative pass
        // uses so a speculative check binds identical symbols — an unseeded
        // check could resolve an outer local through the member scope and
        // cache that binding permanently. Inferred member properties likewise
        // stay `pending` until the source-order pass (or an on-demand read
        // from an early-inferred function) resolves them.
        let localMemberFunctionCtx = driver.helpers.localFunctionOptInContext(objectCtx)
        for functionDeclID in objectDecl.memberFunctions {
            driver.registerInferredReturnFunction(
                for: functionDeclID,
                context: localMemberFunctionCtx,
                baseLocals: outerLocalsSnapshot
            )
        }
        for propertyDeclID in objectDecl.memberProperties {
            guard case let .propertyDecl(property)? = ast.arena.decl(propertyDeclID),
                  property.type == nil,
                  let symbol = propertySymbolsByDecl[propertyDeclID]
            else { continue }
            driver.pendingPropertyTypes.insert(symbol)
        }
        driver.registerInferredMemberProperties(
            objectDecl.memberProperties,
            context: objectCtx,
            initialLocals: outerLocalsSnapshot
        )

        driver.declChecker.precheckIndependentObjectLiteralMemberProperties(
            objectDecl.memberProperties,
            ctx: objectCtx,
            initialLocals: outerLocalsSnapshot,
            solver: driver.solver,
            diagnostics: sema.diagnostics
        )

        for nestedClassDeclID in objectDecl.nestedClasses {
            driver.declChecker.typeCheckNestedClassDecl(
                declID: nestedClassDeclID,
                ctx: objectCtx,
                solver: driver.solver,
                diagnostics: sema.diagnostics
            )
        }
        for nestedObjectDeclID in objectDecl.nestedObjects {
            driver.declChecker.typeCheckNestedObjectDecl(
                nestedObjectDeclID,
                ctx: objectCtx,
                solver: driver.solver,
                diagnostics: sema.diagnostics
            )
        }

        var pendingNestedNominalDecls = objectDecl.nestedClasses + objectDecl.nestedObjects
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
        DataFlowSemaPhase().synthesizeNominalLayouts(
            for: nestedNominalSymbols,
            symbols: sema.symbols,
            types: sema.types,
            interner: interner,
            diagnostics: sema.diagnostics
        )

        typeCheckLocalNominalMemberProperties(
            objectDecl.memberProperties,
            propertySymbolsByDecl: propertySymbolsByDecl,
            memberCtx: objectCtx,
            initializerLocals: locals,
            accessorBaseLocals: outerLocalsSnapshot,
            ctx: ctx
        )
        driver.declChecker.typeCheckInitBlocks(
            objectDecl.initBlocks,
            ctx: objectCtx,
            baseLocals: locals
        )

        // KSP-CAP-001: member function bodies resolve outer locals the same
        // way lambda bodies do — seeded via `locals`, which `inferNameRefExpr`
        // always checks before the class member scope chain. Verified against
        // kotlinc: an outer local shadows an object literal's own member of
        // the same name (not the other way around) — a bare reference inside
        // the member function binds to the captured outer local, and the
        // object's own member is only reachable via explicit `this.member`.
        var capturedSymbols: Set<SymbolID> = []
        for functionDeclID in objectDecl.memberFunctions {
            guard let functionSymbol = memberFunctionSymbolsByDecl[functionDeclID],
                  let decl = ast.arena.decl(functionDeclID),
                  case let .funDecl(functionDecl) = decl
            else {
                continue
            }
            driver.declChecker.typeCheckFunctionDecl(
                functionDecl,
                symbol: functionSymbol,
                ctx: driver.helpers.localFunctionOptInContext(objectCtx)
                    .with(currentDeclSymbol: functionSymbol),
                solver: driver.solver,
                diagnostics: ctx.sema.diagnostics,
                baseLocals: outerLocalsSnapshot
            )
            capturedSymbols.formUnion(driver.captureAnalyzer.collectCapturedOuterSymbols(
                inBody: functionDecl.body,
                ast: ast,
                sema: sema,
                outerSymbols: captureOuterSymbols,
                skipNestedClosures: false
            ))
        }

        for nestedDeclID in objectDecl.nestedClasses + objectDecl.nestedObjects {
            let nestedCaptures = driver.captureAnalyzer.collectCapturedOuterSymbols(
                inDecl: nestedDeclID,
                ast: ast,
                sema: sema,
                outerSymbols: captureOuterSymbols,
                skipNestedClosures: false
            )
            capturedSymbols.formUnion(nestedCaptures)

            for capturedProperty in nestedCaptures
                where outerReceiverPropertySymbols.contains(capturedProperty)
            {
                guard let propertyOwner = sema.symbols.parentSymbol(for: capturedProperty),
                      sema.symbols.symbol(propertyOwner)?.kind == .class
                else {
                    continue
                }
                capturedSymbols.insert(propertyOwner)
            }
        }

        // KSP-CAP-018: a custom accessor body is lowered as its own KIR
        // function, exactly like a member function, so an outer local it
        // references needs a capture field too. Property *initializers* are
        // excluded on purpose: those are lowered inline in the enclosing
        // function (see `lowerStoredObjectLiteralExpr`), where the local is
        // still directly in scope. BUG-267: a delegate body (`lazy { ... }`)
        // is also lowered as a standalone KIR function via
        // `lowerDelegateLambdaBody`, so it needs the same capture treatment.
        capturedSymbols.formUnion(collectLocalNominalCaptureSymbols(
            memberProperties: objectDecl.memberProperties,
            includePropertyInitializers: false,
            extraBodies: [],
            extraExprRoots: [],
            captureOuterSymbols: captureOuterSymbols,
            ast: ast,
            sema: sema
        ))
        // An inherited property belongs to the anonymous instance itself.
        // Capturing the same symbol would overwrite its inherited field slot.
        // Explicit outer accesses retain their receiver capture instead.
        capturedSymbols = Set(capturedSymbols.filter { symbol in
            guard outerReceiverPropertySymbols.contains(symbol),
                  let owner = sema.symbols.parentSymbol(for: symbol)
            else { return true }
            return !sema.types.isNominalSubtypeSymbol(objectSymbol, of: owner)
        })

        // Mutable outer receiver properties must keep addressing the enclosing
        // instance. Capturing their current values would turn writes into writes
        // to the anonymous object's copy, so capture the receiver once instead.
        let capturesMutableOuterProperty = capturedSymbols.contains {
            mutableOuterReceiverPropertySymbols.contains($0)
        }
        capturedSymbols.subtract(mutableOuterReceiverPropertySymbols)
        if capturesMutableOuterProperty,
           let currentDeclSymbol = ctx.currentDeclSymbol,
           let implicitReceiverType = ctx.implicitReceiverType,
           let receiverOwnerSymbol = ctx.enclosingClassSymbol ?? driver.helpers.nominalSymbol(
               of: sema.types.makeNonNullable(implicitReceiverType),
               types: sema.types
           )
        {
            let receiverCaptureSymbol = SyntheticSymbolScheme.receiverParameterSymbol(for: currentDeclSymbol)
            capturedSymbols.insert(receiverCaptureSymbol)
            sema.bindings.bindCapturedLocalType(receiverCaptureSymbol, type: implicitReceiverType)
            sema.bindings.bindObjectLiteralCapturedReceiver(
                objectSymbol,
                receiverSymbol: receiverCaptureSymbol,
                ownerSymbol: receiverOwnerSymbol
            )
        }
        for superSymbol in directSuperSymbols where sema.symbols.symbol(superSymbol)?.kind == .class {
            capturedSymbols.formUnion(sema.bindings.objectLiteralCaptureSymbols(for: superSymbol))
        }
        bindLocalNominalCaptures(
            capturedSymbols,
            ownerSymbol: objectSymbol,
            outerLocalsSnapshot: outerLocalsSnapshot,
            outerReceiverTypes: objectOuterReceiverTypes,
            receiverStack: ctx.implicitReceiverStack,
            sema: sema
        )

        synthesizeLocalNominalLayout(
            ownerSymbol: objectSymbol,
            memberFunctionDecls: objectDecl.memberFunctions,
            memberFunctionSymbolsByDecl: memberFunctionSymbolsByDecl,
            memberPropertyDecls: objectDecl.memberProperties,
            propertySymbolsByDecl: propertySymbolsByDecl,
            capturedSymbols: capturedSymbols,
            directSuperSymbols: directSuperSymbols,
            declRange: objectDecl.range,
            subjectDescription: sema.symbols.symbol(objectSymbol)?.kind == .object
                ? "Object '\(interner.resolve(objectDecl.name))'"
                : "Object expression",
            ctx: ctx
        )
        return objectSymbol
    }



    func registerLocalNominalMemberProperties(
        _ memberProperties: [DeclID],
        ownerFQName: [InternedString],
        ownerSymbol: SymbolID,
        markAsSynthetic: Bool = true,
        primaryConstructorParameters: [DeclID: ValueParamDecl] = [:],
        ctx: TypeInferenceContext
    ) -> [DeclID: SymbolID] {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        var propertySymbolsByDecl: [DeclID: SymbolID] = [:]
        var declBySymbolCache: [SymbolID: DeclID]?
        for propertyDeclID in memberProperties {
            guard let decl = ast.arena.decl(propertyDeclID),
                  case let .propertyDecl(propertyDecl) = decl
            else {
                continue
            }
            var propertyFlags: SymbolFlags = markAsSynthetic ? [.synthetic] : []
            if propertyDecl.modifiers.contains(.override) { propertyFlags.insert(.overrideMember) }
            if propertyDecl.modifiers.contains(.open) { propertyFlags.insert(.openType) }
            if propertyDecl.modifiers.contains(.abstract) { propertyFlags.insert(.abstractType) }
            if propertyDecl.modifiers.contains(.final) { propertyFlags.insert(.finalMember) }
            if propertyDecl.isVar {
                propertyFlags.insert(.mutable)
            }
            if propertyDecl.modifiers.contains(.lateinit) {
                propertyFlags.insert(.lateinitProperty)
            }
            let propertySymbol: SymbolID
            if let existing = sema.bindings.declSymbols[propertyDeclID] {
                propertySymbol = existing
            } else {
                propertySymbol = sema.symbols.define(
                    kind: .property,
                    name: propertyDecl.name,
                    fqName: ownerFQName + [propertyDecl.name],
                    declSite: propertyDecl.range,
                    visibility: Visibility(modifiers: propertyDecl.modifiers),
                    flags: propertyFlags
                )
                sema.bindings.bindDecl(propertyDeclID, symbol: propertySymbol)
            }
            sema.bindings.markObjectLiteralPropertySymbol(propertySymbol)
            sema.symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
            sema.symbols.setSourceFileID(ctx.currentFileID, for: propertySymbol)

            let ownerScope = FunctionScope(parent: ctx.scope, symbols: sema.symbols)
            let ownerParameters = sema.types.nominalTypeParameterSymbols(for: ownerSymbol)
            for parameter in ownerParameters { ownerScope.insert(parameter) }
            let propertyScope = FunctionScope(parent: ownerScope, symbols: sema.symbols)
            var parameters: [SymbolID] = []
            for parameter in propertyDecl.typeParams {
                let symbol = sema.symbols.define(
                    kind: .typeParameter, name: parameter.name,
                    fqName: ownerFQName + [propertyDecl.name, interner.intern("$\(propertySymbol.rawValue)"), parameter.name],
                    declSite: propertyDecl.range, visibility: .private,
                    flags: parameter.isReified ? [.reifiedTypeParameter] : []
                )
                parameters.append(symbol)
                propertyScope.insert(symbol)
            }
            let propertyHeaderCtx: TypeInferenceContext
            if let parameter = primaryConstructorParameters[propertyDeclID] {
                propertyHeaderCtx = driver.helpers.primaryConstructorParameterOptInContext(
                    parameter, ctx: driver.helpers.localFunctionOptInContext(ctx).with(currentDeclSymbol: propertySymbol)
                )
            } else {
                propertyHeaderCtx = ctx
            }
            func resolvePropertyType(_ reference: TypeRefID) -> TypeID {
                driver.helpers.resolveTypeRef(reference, ast: ast, sema: sema, interner: interner,
                                              scope: propertyScope, diagnostics: ctx.sema.diagnostics,
                                              inferenceContext: propertyHeaderCtx, usageRange: propertyDecl.range)
            }
            for (parameter, symbol) in zip(propertyDecl.typeParams, parameters) {
                let bounds = parameter.upperBounds.map(resolvePropertyType)
                if !bounds.isEmpty { sema.symbols.setTypeParameterUpperBounds(bounds, for: symbol) }
                DataFlowSemaPhase.checkConflictingClassUpperBounds(
                    typeParamName: parameter.name, bounds: bounds, declSite: propertyDecl.range,
                    symbols: sema.symbols, types: sema.types, interner: interner,
                    diagnostics: ctx.sema.diagnostics
                )
            }
            var declaredType = propertyDecl.type.map(resolvePropertyType) ?? sema.types.anyType
            if propertyDecl.isSynthesizedPrimaryConstructorProperty,
               let constructor = sema.symbols.lookupAll(fqName: ownerFQName + [interner.intern("<init>")])
                   .compactMap({ sema.symbols.functionSignature(for: $0) }).first,
               let index = constructor.valueParameterSymbols.firstIndex(where: {
                   sema.symbols.symbol($0)?.name == propertyDecl.name
               }), constructor.valueParameterIsVararg.indices.contains(index),
               constructor.valueParameterIsVararg[index], constructor.parameterTypes.indices.contains(index),
               let array = primitiveVarargArrayType(elementType: constructor.parameterTypes[index],
                                                   sema: sema, interner: interner) {
                declaredType = array
            }
            // Re-entry after inference must not replace a concrete inferred type
            // with the Any placeholder used before the initializer is checked.
            if propertyDecl.type == nil,
               let existingPropertyType = sema.symbols.propertyType(for: propertySymbol),
               existingPropertyType != sema.types.anyType {
                declaredType = existingPropertyType
            }
            sema.symbols.setPropertyType(declaredType, for: propertySymbol)
            if let setterVisibility = propertyDecl.setter?.visibility {
                sema.symbols.setPropertySetterVisibility(setterVisibility, for: propertySymbol)
            } else if propertyDecl.isVar, propertyDecl.modifiers.contains(.override) {
                if declBySymbolCache == nil {
                    declBySymbolCache = Dictionary(
                        sema.bindings.declSymbols.map { ($0.value, $0.key) },
                        uniquingKeysWith: { first, _ in first }
                    )
                }
                if let effective = DataFlowSemaPhase().implicitOverrideSetterVisibility(
                    propertyDecl: propertyDecl,
                    ownerSymbol: ownerSymbol,
                    declBySymbol: declBySymbolCache ?? [:],
                    ast: ast,
                    symbols: sema.symbols
                ) {
                    sema.symbols.setPropertySetterVisibility(effective, for: propertySymbol)
                }
            }
            if propertyDecl.modifiers.contains(.override),
               propertyDecl.modifiers.isDisjoint(
                   with: [.private, .protected, .internal, .public]
               )
            {
                if declBySymbolCache == nil {
                    declBySymbolCache = Dictionary(
                        sema.bindings.declSymbols.map { ($0.value, $0.key) },
                        uniquingKeysWith: { first, _ in first }
                    )
                }
                if let effective = DataFlowSemaPhase().implicitOverrideMemberVisibility(
                    kind: .property,
                    name: propertyDecl.name,
                    ownerSymbol: ownerSymbol,
                    parameterTypes: nil,
                    declBySymbol: declBySymbolCache ?? [:],
                    ast: ast,
                    symbols: sema.symbols,
                    childMember: propertySymbol,
                    types: sema.types
                ) {
                    sema.symbols.setVisibility(effective, for: propertySymbol)
                }
            }
            if let receiver = propertyDecl.receiverType.map(resolvePropertyType) {
                sema.symbols.insertFlags(.memberExtension, for: propertySymbol)
                sema.symbols.setExtensionPropertyReceiverType(receiver, for: propertySymbol)
                let allParameters = ownerParameters + parameters
                let bounds = allParameters.map { sema.symbols.typeParameterUpperBounds(for: $0) }
                func accessor(_ name: String, parameterTypes: [TypeID], returnType: TypeID) -> SymbolID {
                    let symbol = sema.symbols.define(
                        kind: .function, name: interner.intern(name),
                        fqName: ownerFQName + [propertyDecl.name, interner.intern("$" + name)],
                        declSite: propertyDecl.range, visibility: .public, flags: [.synthetic]
                    )
                    sema.symbols.setParentSymbol(propertySymbol, for: symbol)
                    sema.symbols.setFunctionSignature(FunctionSignature(
                        receiverType: receiver, parameterTypes: parameterTypes, returnType: returnType,
                        typeParameterSymbols: allParameters,
                        reifiedTypeParameterIndices: Set(propertyDecl.typeParams.indices.filter { propertyDecl.typeParams[$0].isReified }.map { $0 + ownerParameters.count }),
                        typeParameterUpperBoundsList: bounds,
                        classTypeParameterCount: ownerParameters.count
                    ), for: symbol)
                    return symbol
                }
                sema.symbols.setExtensionPropertyGetterAccessor(accessor("get", parameterTypes: [], returnType: declaredType), for: propertySymbol)
                if propertyDecl.isVar {
                    sema.symbols.setExtensionPropertySetterAccessor(accessor("set", parameterTypes: [declaredType], returnType: sema.types.unitType), for: propertySymbol)
                }
            }
            if propertyDecl.getter?.body != nil { sema.symbols.setPropertyHasCustomGetter(true, for: propertySymbol) }

            // KSP-CAP-018: mirror `MemberHeaderCollection`'s backing-field rule.
            // A property carrying accessors *and* real storage (a setter, or an
            // initializer) needs a field symbol distinct from the property
            // symbol, so that `field` inside its own accessor body resolves to
            // the slot instead of back to the property — which lowers to `call
            // get`/`call set` and makes the accessor recurse into itself. A
            // getter-only computed property has no storage and needs none.
            let isGetterOnlyComputed = propertyDecl.getter != nil
                && propertyDecl.setter == nil
                && propertyDecl.initializer == nil
            let needsBackingField = !isGetterOnlyComputed
                && (propertyDecl.getter != nil || propertyDecl.setter != nil)
            if needsBackingField, propertyDecl.delegateExpression == nil, propertyDecl.receiverType == nil {
                let fieldName = interner.intern("$backing_\(interner.resolve(propertyDecl.name))")
                let backingFieldSymbol = sema.symbols.define(
                    kind: .backingField,
                    name: fieldName,
                    fqName: ownerFQName + [fieldName],
                    declSite: propertyDecl.range,
                    visibility: .private,
                    flags: propertyDecl.isVar ? [.mutable] : []
                )
                sema.symbols.setParentSymbol(ownerSymbol, for: backingFieldSymbol)
                sema.symbols.setPropertyType(declaredType, for: backingFieldSymbol)
                sema.symbols.setSourceFileID(ctx.currentFileID, for: backingFieldSymbol)
                sema.symbols.setBackingFieldSymbol(backingFieldSymbol, for: propertySymbol)
            }

            if propertyDecl.delegateExpression != nil {
                let extensionSuffix = propertyDecl.receiverType == nil ? "" : "_extension_\(propertySymbol.rawValue)"
                let delegateStorageName = interner.intern(
                    "$delegate_\(interner.resolve(propertyDecl.name))\(extensionSuffix)"
                )
                let delegateStorageSymbol = sema.symbols.define(
                    kind: .field,
                    name: delegateStorageName,
                    fqName: ownerFQName + [delegateStorageName],
                    declSite: propertyDecl.range,
                    visibility: .private,
                    flags: []
                )
                sema.symbols.setParentSymbol(ownerSymbol, for: delegateStorageSymbol)
                sema.symbols.setSourceFileID(ctx.currentFileID, for: delegateStorageSymbol)
                sema.symbols.setDelegateStorageSymbol(delegateStorageSymbol, for: propertySymbol)
            }
            propertySymbolsByDecl[propertyDeclID] = propertySymbol
        }
        return propertySymbolsByDecl
    }

    func typeCheckLocalNominalMemberProperties(
        _ memberProperties: [DeclID],
        propertySymbolsByDecl: [DeclID: SymbolID],
        memberCtx: TypeInferenceContext,
        initializerLocals: LocalBindings,
        accessorBaseLocals: LocalBindings,
        ctx: TypeInferenceContext
    ) {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        var initializerLocals = initializerLocals
        for propertyDeclID in memberProperties {
            guard !driver.precheckedPropertyDecls.contains(propertyDeclID),
                  let propertySymbol = propertySymbolsByDecl[propertyDeclID],
                  let decl = ast.arena.decl(propertyDeclID),
                  case let .propertyDecl(propertyDecl) = decl
            else {
                continue
            }

            if propertyDecl.isSynthesizedPrimaryConstructorProperty {
                driver.declChecker.validatePropertyHeaderOptInTypes(
                    propertySymbol,
                    ctx: driver.helpers.localFunctionOptInContext(memberCtx).with(currentDeclSymbol: propertySymbol)
                )
            }
            driver.declChecker.typeCheckAnnotationFactories(
                propertyDecl.annotations + (sema.bindings.primaryConstructorPropertyAnnotations[propertySymbol] ?? []),
                symbol: propertySymbol, ctx: memberCtx
            )
            let declaredType = propertyDecl.type == nil ? nil : sema.symbols.propertyType(for: propertySymbol)

            var inferredType: TypeID?
            if let initializer = propertyDecl.initializer {
                let type = driver.inferExpr(
                    initializer,
                    ctx: memberCtx,
                    locals: &initializerLocals,
                    expectedType: declaredType
                )
                if let declaredType {
                    driver.emitSubtypeConstraint(
                        left: type,
                        right: declaredType,
                        range: propertyDecl.range,
                        solver: ConstraintSolver(),
                        sema: sema,
                        diagnostics: ctx.sema.diagnostics,
                        diagnosticCode: "KSWIFTK-SEMA-0468",
                        failureMessage: "Initializer type mismatch."
                    )
                }
                inferredType = type
            }

            var accessorCtx = driver.declChecker.propertyTypeParameterContext(
                propertyDecl, symbol: propertySymbol, ctx: memberCtx, diagnostics: ctx.sema.diagnostics
            )
            if let receiver = sema.symbols.extensionPropertyReceiverType(for: propertySymbol) {
                accessorCtx = accessorCtx.copying(implicitReceiverType: receiver).withOuterReceiver(
                    label: propertyDecl.name, type: receiver,
                    symbol: SyntheticSymbolScheme.receiverParameterSymbol(for: propertySymbol)
                )
            }
            if let getter = propertyDecl.getter, getter.body != .unit {
                inferredType = driver.declChecker.typeCheckGetter(
                    getter,
                    property: propertyDecl,
                    symbol: propertySymbol,
                    inferredPropertyType: declaredType ?? inferredType,
                    accessorCtx: accessorCtx,
                    solver: driver.solver,
                    diagnostics: ctx.sema.diagnostics,
                    baseLocals: accessorBaseLocals
                )
            }

            if let delegateExpr = propertyDecl.delegateExpression {
                inferredType = driver.declChecker.typeCheckDelegate(
                    delegateExpr,
                    isVar: propertyDecl.isVar,
                    fallbackRange: propertyDecl.range,
                    symbol: propertySymbol,
                    inferredPropertyType: declaredType ?? inferredType,
                    ctx: memberCtx,
                    locals: &initializerLocals,
                    diagnostics: ctx.sema.diagnostics,
                    delegateBody: propertyDecl.delegateBody,
                    delegateBodyParams: propertyDecl.delegateBodyParams
                )
            }

            let finalType: TypeID
            if let declaredType {
                finalType = declaredType
            } else if let inferredType {
                finalType = inferredType
            } else {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0101",
                    "Property '\(interner.resolve(propertyDecl.name))' in object literal must have a type annotation or initializer.",
                    range: propertyDecl.range
                )
                finalType = sema.types.errorType
            }
            sema.symbols.setPropertyType(finalType, for: propertySymbol)

            if propertyDecl.modifiers.contains(.lateinit) {
                driver.declChecker.validateLateinitProperty(
                    propertyDecl,
                    finalPropertyType: finalType,
                    diagnostics: ctx.sema.diagnostics,
                    sema: sema
                )
            }

            if let setter = propertyDecl.setter, setter.body != .unit {
                driver.declChecker.typeCheckSetter(
                    setter,
                    property: propertyDecl,
                    symbol: propertySymbol,
                    finalPropertyType: finalType,
                    accessorCtx: accessorCtx,
                    solver: driver.solver,
                    diagnostics: ctx.sema.diagnostics,
                    baseLocals: accessorBaseLocals
                )
            }

            driver.pendingPropertyTypes.remove(propertySymbol)
            driver.deferredInferredProperties.remove(propertySymbol)
        }
    }

    func collectLocalNominalCaptureSymbols(
        memberProperties: [DeclID],
        includePropertyInitializers: Bool,
        extraBodies: [FunctionBody],
        extraExprRoots: [ExprID],
        captureOuterSymbols: Set<SymbolID>,
        ast: ASTModule,
        sema: SemaModule
    ) -> Set<SymbolID> {
        var capturedSymbols: Set<SymbolID> = []
        for propertyDeclID in memberProperties {
            guard let decl = ast.arena.decl(propertyDeclID),
                  case let .propertyDecl(propertyDecl) = decl
            else {
                continue
            }
            for accessorBody in [propertyDecl.getter?.body, propertyDecl.setter?.body, propertyDecl.delegateBody] {
                guard let accessorBody, accessorBody != .unit else {
                    continue
                }
                capturedSymbols.formUnion(driver.captureAnalyzer.collectCapturedOuterSymbols(
                    inBody: accessorBody,
                    ast: ast,
                    sema: sema,
                    outerSymbols: captureOuterSymbols,
                    skipNestedClosures: false
                ))
            }
            if includePropertyInitializers {
                let initializerRoots = [
                    propertyDecl.initializer,
                    propertyDecl.delegateExpression,
                ].compactMap { $0 }
                for initializer in initializerRoots {
                    capturedSymbols.formUnion(driver.captureAnalyzer.collectCapturedOuterSymbols(
                        in: initializer,
                        ast: ast,
                        sema: sema,
                        outerSymbols: captureOuterSymbols,
                        // These roots lower inside `<init>`, so an outer local
                        // referenced only from a nested lambda/init-block body
                        // still needs a capture field for the lambda to load
                        // (KUU-2944: `{ x + y }` on `val x by Delegate()`).
                        skipNestedClosures: false
                    ))
                }
            }
        }
        for body in extraBodies {
            capturedSymbols.formUnion(driver.captureAnalyzer.collectCapturedOuterSymbols(
                inBody: body,
                ast: ast,
                sema: sema,
                outerSymbols: captureOuterSymbols,
                skipNestedClosures: false
            ))
        }
        for exprID in extraExprRoots {
            capturedSymbols.formUnion(driver.captureAnalyzer.collectCapturedOuterSymbols(
                in: exprID,
                ast: ast,
                sema: sema,
                outerSymbols: captureOuterSymbols,
                skipNestedClosures: false
            ))
        }
        return capturedSymbols
    }

    func bindLocalNominalCaptures(
        _ capturedSymbols: Set<SymbolID>,
        ownerSymbol: SymbolID,
        outerLocalsSnapshot: LocalBindings,
        outerReceiverTypes: [(label: InternedString, type: TypeID, symbol: SymbolID?)],
        receiverStack: [(type: TypeID, symbol: SymbolID)] = [],
        sema: SemaModule
    ) {
        guard !capturedSymbols.isEmpty else {
            return
        }
        var typesBySymbol: [SymbolID: TypeID] = [:]
        for binding in outerLocalsSnapshot.values {
            typesBySymbol[binding.symbol] = binding.type
        }
        for outerReceiver in outerReceiverTypes {
            if let symbol = outerReceiver.symbol {
                typesBySymbol[symbol] = outerReceiver.type
            }
        }
        for receiver in receiverStack {
            typesBySymbol[receiver.symbol] = receiver.type
        }
        for capturedSymbol in capturedSymbols {
            if sema.symbols.symbol(capturedSymbol)?.flags.contains(.reifiedTypeParameter) == true {
                sema.bindings.bindCapturedLocalType(capturedSymbol, type: sema.types.intType)
                continue
            }
            if let type = typesBySymbol[capturedSymbol]
                ?? sema.symbols.propertyType(for: capturedSymbol)
            {
                sema.bindings.bindCapturedLocalType(capturedSymbol, type: type)
            }
        }
        sema.bindings.bindObjectLiteralCaptureSymbols(
            ownerSymbol,
            symbols: capturedSymbols.sorted(by: { $0.rawValue < $1.rawValue })
        )
    }

    func synthesizeLocalNominalLayout(
        ownerSymbol: SymbolID,
        memberFunctionDecls: [DeclID],
        memberFunctionSymbolsByDecl: [DeclID: SymbolID],
        memberPropertyDecls: [DeclID],
        propertySymbolsByDecl: [DeclID: SymbolID],
        capturedSymbols: Set<SymbolID>,
        directSuperSymbols: [SymbolID],
        declRange: SourceRange,
        subjectDescription: String = "Object expression",
        ctx: TypeInferenceContext
    ) {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let superClass = directSuperSymbols.first { superSymbol in
            guard let symbol = sema.symbols.symbol(superSymbol) else {
                return false
            }
            return symbol.kind != .interface
        }
        let layoutSuperClass = superClass.flatMap { superClassID in
            guard let expectSymbol = sema.symbols.symbol(superClassID),
                  expectSymbol.flags.contains(.expectDeclaration),
                  let actualSymbolID = sema.symbols.actualSymbol(for: superClassID),
                  sema.symbols.symbol(actualSymbolID)?.kind == expectSymbol.kind
            else {
                return superClassID
            }
            return actualSymbolID
        }
        // KUU-2955, KUU-2959: a local class nested inside another local
        // nominal's member (`class FooC : AB` inside local `A2.foo`), or an
        // object literal declared inside a local nominal's body, reaches this
        // point while the enclosing nominal is still being processed —
        // before sibling nested nominals like `AB` get their layout
        // synthesized. Materialize the superclass layout on demand so its
        // fields, `$outer` slot and vtable slots are actually inherited.
        if let layoutSuperClass, sema.symbols.nominalLayout(for: layoutSuperClass) == nil {
            DataFlowSemaPhase().synthesizeNominalLayouts(
                for: [layoutSuperClass],
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                diagnostics: sema.diagnostics,
                includeAncestors: true
            )
        }
        let inheritedLayout = layoutSuperClass.flatMap { sema.symbols.nominalLayout(for: $0) }
        var fieldOffsets = inheritedLayout?.fieldOffsets ?? [:]
        let objectHeaderWords = inheritedLayout?.objectHeaderWords ?? 2
        var nextFieldOffset = (fieldOffsets.values.max() ?? (objectHeaderWords - 1)) + 1
        for propertyDeclID in memberPropertyDecls {
            guard let propertySymbol = propertySymbolsByDecl[propertyDeclID] else {
                continue
            }
            let storageSymbol = sema.symbols.delegateStorageSymbol(for: propertySymbol)
                ?? sema.symbols.backingFieldSymbol(for: propertySymbol)
                ?? propertySymbol
            guard fieldOffsets[storageSymbol] == nil else {
                continue
            }
            fieldOffsets[storageSymbol] = nextFieldOffset
            nextFieldOffset += 1
        }
        let delegationFields = sema.symbols.delegatedInterfaces(forClass: ownerSymbol).compactMap {
            sema.symbols.classDelegationField(forClass: ownerSymbol, interface: $0)
        }
        for fieldSymbol in delegationFields where fieldOffsets[fieldSymbol] == nil {
            fieldOffsets[fieldSymbol] = nextFieldOffset
            nextFieldOffset += 1
        }
        for capturedSymbol in capturedSymbols.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard fieldOffsets[capturedSymbol] == nil else {
                continue
            }
            fieldOffsets[capturedSymbol] = nextFieldOffset
            nextFieldOffset += 1
        }

        let inheritedFieldCount = inheritedLayout?.instanceFieldCount ?? 0
        let instanceFieldCount = inheritedFieldCount + propertySymbolsByDecl.count
            + delegationFields.count + capturedSymbols.count
        let inheritedInstanceSizeWords = inheritedLayout?.instanceSizeWords ?? 0
        let instanceSizeWords = max(objectHeaderWords + instanceFieldCount, inheritedInstanceSizeWords)
        let inheritedVtableSlots = inheritedLayout?.vtableSlots ?? [:]
        let inheritedItableSlots = inheritedLayout?.itableSlots ?? [:]
        let inheritedVtableSize = inheritedLayout?.vtableSize
        let inheritedItableSize = inheritedLayout?.itableSize

        // The nominal never went through `synthesizeNominalLayouts`, so its
        // `vtableSlots` start as a bare copy of the superclass's slots — an
        // `override fun` here would leave the inherited slot pointing at the
        // base class's implementation. Re-slot overrides now.
        var vtableSlots = inheritedVtableSlots
        let inheritedCandidatesByKey = vtableInheritedCandidatesByKey(
            inheritedVtableSlots: inheritedVtableSlots, symbols: sema.symbols
        )
        // A local `open`/`abstract` class can itself be a superclass, so its
        // own non-overriding methods need fresh slots (like
        // `synthesizeLayoutForNominal` does for named classes); otherwise a
        // call through a base-typed reference finds no slot and is lowered as
        // a direct call to the base implementation.
        var nextVtableSlot = max(inheritedVtableSize ?? 0, (inheritedVtableSlots.values.max() ?? -1) + 1)
        let memberFunctionSymbols = Array(memberFunctionSymbolsByDecl.values)
            + sema.symbols.classDelegationForwardingMethodSymbols(forClass: ownerSymbol)
        for memberSymbolID in memberFunctionSymbols.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let method = sema.symbols.symbol(memberSymbolID) else { continue }
            if method.flags.contains(.overrideMember),
               let candidates = inheritedCandidatesByKey[vtableMethodDispatchKey(for: method, symbols: sema.symbols)]
            {
                let parameterTypes = sema.symbols.functionSignature(for: method.id)?.parameterTypes ?? []
                if let matchedSlot = resolveOverriddenVtableSlot(method: method, parameterTypes: parameterTypes, candidates: candidates, symbols: sema.symbols, types: sema.types) {
                    vtableSlots[method.id] = matchedSlot
                    continue
                }
            }
            vtableSlots[method.id] = nextVtableSlot
            nextVtableSlot += 1
        }

        if let owner = sema.symbols.symbol(ownerSymbol) {
            DataFlowSemaPhase.assignPropertyAccessorVtableSlots(
                for: owner,
                symbols: sema.symbols,
                inheritedVtable: inheritedVtableSlots,
                vtableSlots: &vtableSlots,
                nextVtableSlot: &nextVtableSlot
            )
        }

        var itableSlots = inheritedItableSlots
        var nextItableSlot = max(inheritedItableSize ?? 0, (itableSlots.values.max() ?? -1) + 1)
        for interfaceID in kirTransitiveInterfaceSupertypes(of: ownerSymbol, sema: sema)
            where itableSlots[interfaceID] == nil
        {
            itableSlots[interfaceID] = nextItableSlot
            nextItableSlot += 1
        }

        var overriddenMembers: Set<MemberRequirementKey> = []
        for functionDeclID in memberFunctionDecls {
            guard let decl = ast.arena.decl(functionDeclID),
                  case let .funDecl(functionDecl) = decl
            else { continue }
            overriddenMembers.insert(MemberRequirementKey(
                name: functionDecl.name,
                isMemberExtension: functionDecl.receiverType != nil,
                kind: .function
            ))
        }
        for propertyDeclID in memberPropertyDecls {
            guard let decl = ast.arena.decl(propertyDeclID),
                  case let .propertyDecl(propertyDecl) = decl
            else { continue }
            overriddenMembers.insert(MemberRequirementKey(
                name: propertyDecl.name,
                isMemberExtension: propertyDecl.receiverType != nil,
                kind: .property
            ))
        }
        for missingMember in unimplementedAbstractMembers(
            for: ownerSymbol,
            overriddenMembers: overriddenMembers,
            delegatedInterfaces: sema.symbols.delegatedInterfaces(forClass: ownerSymbol),
            symbols: sema.symbols,
            types: sema.types,
            interner: interner
        ) {
            guard let missingSymbol = sema.symbols.symbol(missingMember) else {
                continue
            }
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-ABSTRACT",
                "\(subjectDescription) must override abstract member "
                    + "'\(interner.resolve(missingSymbol.name))'.",
                range: declRange
            )
        }

        sema.symbols.setNominalLayout(
            NominalLayout(
                objectHeaderWords: objectHeaderWords,
                instanceFieldCount: instanceFieldCount,
                instanceSizeWords: instanceSizeWords,
                fieldOffsets: fieldOffsets,
                vtableSlots: vtableSlots,
                itableSlots: itableSlots,
                vtableSize: nextVtableSlot,
                itableSize: nextItableSlot,
                superClass: layoutSuperClass
            ),
            for: ownerSymbol
        )
    }

    func collectObjectLiteralMemberFunctions(
        _ memberFunctions: [DeclID],
        memberFQNamePrefix: [InternedString],
        objectSymbol: SymbolID,
        objectType: TypeID,
        classTypeParameterSymbols: [SymbolID] = [],
        limitsClassTypeParameterPrefixToMemberSurface: Bool = false,
        objectScope: ClassMemberScope,
        ctx: TypeInferenceContext
    ) -> [DeclID: SymbolID] {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        var result: [DeclID: SymbolID] = [:]
        var declBySymbolCache: [SymbolID: DeclID]?

        for functionDeclID in memberFunctions {
            guard let decl = ast.arena.decl(functionDeclID),
                  case let .funDecl(functionDecl) = decl
            else {
                continue
            }

            let memberSymbol: SymbolID
            if let existing = sema.bindings.declSymbols[functionDeclID] {
                memberSymbol = existing
            } else {
                memberSymbol = sema.symbols.define(
                    kind: .function,
                    name: functionDecl.name,
                    fqName: memberFQNamePrefix + [functionDecl.name],
                    declSite: functionDecl.range,
                    visibility: Visibility(modifiers: functionDecl.modifiers),
                    flags: objectLiteralFunctionFlags(
                        from: functionDecl,
                        objectSymbol: objectSymbol,
                        sema: sema)
                )
                sema.bindings.bindDecl(functionDeclID, symbol: memberSymbol)
            }
            sema.symbols.setParentSymbol(objectSymbol, for: memberSymbol)
            sema.symbols.setSourceFileID(ctx.currentFileID, for: memberSymbol)
            objectScope.insert(memberSymbol)

            let memberFQName = memberFQNamePrefix + [functionDecl.name]
            let localNamespaceFQName = memberFQName + [interner.intern("$\(memberSymbol.rawValue)")]
            var enclosingTypeParameters: [InternedString: SymbolID] = [:]
            for typeParameterSymbol in driver.helpers.lexicalTypeParameterSymbols(in: ctx) {
                guard let name = sema.symbols.symbol(typeParameterSymbol)?.name,
                      enclosingTypeParameters[name] == nil,
                      let visibleSymbol = driver.helpers.resolveTypeParameterSymbol(
                          name, scope: objectScope, sema: sema
                      )
                else {
                    continue
                }
                enclosingTypeParameters[name] = visibleSymbol
            }
            let sourceFile = ast.file(for: ctx.currentFileID)
            let typeParamResult = DataFlowSemaPhase().collectFunctionTypeParameters(
                functionDecl.typeParams,
                localNamespaceFQName: localNamespaceFQName,
                declSite: functionDecl.range,
                ast: ast,
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                sourceManager: ctx.visibilityChecker.sourceManager,
                isInline: functionDecl.isInline,
                diagnostics: ctx.sema.diagnostics,
                enclosingTypeParameters: enclosingTypeParameters,
                relativeOwnerFQName: memberFQNamePrefix,
                currentPackageFQName: sourceFile?.packageFQName,
                imports: sourceFile?.imports ?? []
            )
            let functionScope = FunctionScope(parent: objectScope, symbols: sema.symbols)
            for typeParameterSymbol in typeParamResult.typeParameterSymbols {
                functionScope.insert(typeParameterSymbol)
            }

            var parameterTypes: [TypeID] = []
            var parameterSymbols: [SymbolID] = []
            for param in functionDecl.valueParams {
                let paramType: TypeID = if let typeRefID = param.type {
                    driver.helpers.resolveTypeRef(
                        typeRefID,
                        ast: ast,
                        sema: sema,
                        interner: interner,
                        scope: functionScope,
                        diagnostics: ctx.sema.diagnostics,
                        inferenceContext: ctx,
                        usageRange: functionDecl.range
                    )
                } else {
                    sema.types.anyType
                }
                parameterTypes.append(paramType)

                let paramSymbol = sema.symbols.define(
                    kind: .valueParameter,
                    name: param.name,
                    fqName: memberFQNamePrefix + [functionDecl.name, param.name],
                    declSite: functionDecl.range,
                    visibility: .private,
                    flags: []
                )
                sema.symbols.setParentSymbol(memberSymbol, for: paramSymbol)
                sema.symbols.setPropertyType(paramType, for: paramSymbol)
                parameterSymbols.append(paramSymbol)
            }

            let contextReceiverTypes = functionDecl.contextReceivers.compactMap { contextReceiver in
                driver.helpers.resolveTypeRef(
                    contextReceiver.type,
                    ast: ast,
                    sema: sema,
                    interner: interner,
                    scope: functionScope,
                    diagnostics: ctx.sema.diagnostics,
                    inferenceContext: ctx,
                    usageRange: functionDecl.range
                )
            }
            var contextParameterTypes: [TypeID] = []
            var contextParameterSymbols: [SymbolID] = []
            for param in DataFlowSemaPhase().contextParameterValueDeclarations(
                functionDecl.contextReceivers,
                interner: interner
            ) {
                let paramType: TypeID = if let typeRefID = param.type {
                    driver.helpers.resolveTypeRef(
                        typeRefID,
                        ast: ast,
                        sema: sema,
                        interner: interner,
                        scope: functionScope,
                        diagnostics: ctx.sema.diagnostics,
                        inferenceContext: ctx,
                        usageRange: functionDecl.range
                    )
                } else {
                    sema.types.anyType
                }
                contextParameterTypes.append(paramType)

                let paramSymbol = sema.symbols.define(
                    kind: .valueParameter,
                    name: param.name,
                    fqName: memberFQNamePrefix + [
                        functionDecl.name, interner.intern("$context"), param.name,
                    ],
                    declSite: functionDecl.range,
                    visibility: .private,
                    flags: []
                )
                sema.symbols.setParentSymbol(memberSymbol, for: paramSymbol)
                sema.symbols.setPropertyType(paramType, for: paramSymbol)
                contextParameterSymbols.append(paramSymbol)
            }

            let returnType: TypeID
            if let returnTypeRef = functionDecl.returnType {
                returnType = driver.helpers.resolveTypeRef(
                    returnTypeRef,
                    ast: ast,
                    sema: sema,
                    interner: interner,
                    scope: functionScope,
                    diagnostics: ctx.sema.diagnostics,
                    inferenceContext: ctx
                )
            } else {
                switch functionDecl.body {
                case .unit, .block:
                    returnType = sema.types.unitType
                case .expr:
                    if let existingSymbol = sema.bindings.declSymbols[functionDeclID],
                       let preservedReturnType = sema.symbols.functionSignatureIfKnown(for: existingSymbol)?.returnType,
                       preservedReturnType != sema.types.anyType
                    {
                        returnType = preservedReturnType
                    } else {
                        returnType = sema.types.anyType
                    }
                }
            }

            let receiverType: TypeID
            if let receiverTypeRef = functionDecl.receiverType {
                receiverType = driver.helpers.resolveTypeRef(
                    receiverTypeRef,
                    ast: ast,
                    sema: sema,
                    interner: interner,
                    scope: objectScope,
                    diagnostics: ctx.sema.diagnostics,
                    inferenceContext: ctx,
                    usageRange: functionDecl.range
                )
            } else {
                receiverType = objectType
            }

            // KUU-3867: an anonymous object keeps every lexical type parameter
            // on its own type so escaped members whose *inferred* types still
            // resolve to them can substitute through the object arguments.
            // The member signature prefix must only carry the parameters the
            // member's declared surface actually spells — an outer generic
            // function's unused parameters would otherwise sit ahead of the
            // member's own type parameters, shifting them (and the reified
            // indices and upper-bound lists derived from them) off index 0
            // and breaking explicit type-argument calls.
            //
            // The prefix is all-or-nothing: receiver-owner constraint paths
            // pair it positionally with the object type's argument list, so a
            // partial prefix would misalign arity and bind the wrong
            // arguments. A member spelling any captured parameter therefore
            // keeps the full prefix — as do members with an inferred
            // signature position (`fun get() = stored`, an untyped parameter),
            // whose refined types may still mention one.
            let memberClassTypeParameterSymbols: [SymbolID]
            if limitsClassTypeParameterPrefixToMemberSurface,
               !objectLiteralMemberHasInferredSignatureType(functionDecl) {
                let spelledTypeParameterNames = objectLiteralMemberSpelledTypeNames(
                    functionDecl, ast: ast
                )
                let spellsCapturedParameter = classTypeParameterSymbols.contains { symbol in
                    guard let name = sema.symbols.symbol(symbol)?.name else { return false }
                    return spelledTypeParameterNames.contains(name)
                }
                memberClassTypeParameterSymbols = spellsCapturedParameter
                    ? classTypeParameterSymbols
                    : []
            } else {
                memberClassTypeParameterSymbols = classTypeParameterSymbols
            }

            sema.symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    contextReceiverTypes: contextReceiverTypes,
                    contextParameterSymbols: contextParameterSymbols,
                    contextParameterTypes: contextParameterTypes,
                    parameterTypes: parameterTypes,
                    returnType: returnType,
                    isSuspend: functionDecl.isSuspend,
                    valueParameterSymbols: parameterSymbols,
                    valueParameterHasDefaultValues: functionDecl.valueParams.map(\.hasDefaultValue),
                    valueParameterIsVararg: functionDecl.valueParams.map(\.isVararg),
                    typeParameterSymbols: memberClassTypeParameterSymbols + typeParamResult.typeParameterSymbols,
                    reifiedTypeParameterIndices: Set(
                        typeParamResult.reifiedIndices.map { $0 + memberClassTypeParameterSymbols.count }
                    ),
                    typeParameterUpperBoundsList: (
                        memberClassTypeParameterSymbols + typeParamResult.typeParameterSymbols
                    ).map {
                        sema.symbols.typeParameterUpperBounds(for: $0)
                    },
                    classTypeParameterCount: memberClassTypeParameterSymbols.count
                ),
                for: memberSymbol
            )
            if DataFlowSemaPhase().nearestOverriddenFunctionCandidates(
                of: memberSymbol, symbols: sema.symbols, types: sema.types
            ).contains(where: { sema.symbols.symbol($0)?.flags.contains(.infixFunction) == true }) {
                sema.symbols.insertFlags(.infixFunction, for: memberSymbol)
            }
            if functionDecl.modifiers.contains(.override),
               functionDecl.modifiers.isDisjoint(
                   with: [.private, .protected, .internal, .public]
               )
            {
                if declBySymbolCache == nil {
                    declBySymbolCache = Dictionary(
                        sema.bindings.declSymbols.map { ($0.value, $0.key) },
                        uniquingKeysWith: { first, _ in first }
                    )
                }
                if let effective = DataFlowSemaPhase().implicitOverrideMemberVisibility(
                    kind: .function,
                    name: functionDecl.name,
                    ownerSymbol: objectSymbol,
                    parameterTypes: parameterTypes,
                    declBySymbol: declBySymbolCache ?? [:],
                    ast: ast,
                    symbols: sema.symbols,
                    childMember: memberSymbol,
                    types: sema.types
                ) {
                    sema.symbols.setVisibility(effective, for: memberSymbol)
                }
            }
            result[functionDeclID] = memberSymbol
        }

        return result
    }

    private func objectLiteralFunctionFlags(
        from functionDecl: FunDecl,
        objectSymbol: SymbolID,
        sema: SemaModule) -> SymbolFlags {
        var flags: SymbolFlags = [.synthetic]
        if functionDecl.receiverType != nil { flags.insert(.memberExtension) }
        if functionDecl.isSuspend { flags.insert(.suspendFunction) }
        if functionDecl.isInline { flags.insert(.inlineFunction) }
        if functionDecl.modifiers.contains(.operator) { flags.insert(.operatorFunction) }
        if functionDecl.modifiers.contains(.infix) { flags.insert(.infixFunction) }
        if functionDecl.modifiers.contains(.override) { flags.insert(.overrideMember) }
        if functionDecl.modifiers.contains(.abstract) { flags.insert(.abstractType) }
        if functionDecl.modifiers.contains(.open) { flags.insert(.openType) }
        if functionDecl.modifiers.contains(.final) { flags.insert(.finalMember) }

        // KSP-441: Object literal overrides of operator functions (e.g. Sequence.iterator,
        // Iterator.hasNext/next) must carry the operator flag so for-in lowering can
        // resolve them without an explicit `operator` keyword on the override.
        if !flags.contains(.operatorFunction),
           flags.contains(.overrideMember),
           functionHasOperatorBase(
               name: functionDecl.name,
               parameterCount: functionDecl.valueParams.count,
               ownerSymbol: objectSymbol,
               sema: sema
           )
        {
            flags.insert(.operatorFunction)
        }
        return flags
    }

    private func functionHasOperatorBase(
        name: InternedString,
        parameterCount: Int,
        ownerSymbol: SymbolID,
        sema: SemaModule
    ) -> Bool {
        var stack = sema.symbols.directSupertypes(for: ownerSymbol)
        var visited: Set<SymbolID> = []
        while let current = stack.popLast() {
            guard visited.insert(current).inserted else { continue }
            guard let currentSymbol = sema.symbols.symbol(current) else { continue }
            let candidateFQName = currentSymbol.fqName + [name]
            for candidate in sema.symbols.lookupAll(fqName: candidateFQName) {
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      symbol.flags.contains(.operatorFunction),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == parameterCount,
                      sema.symbols.parentSymbol(for: candidate) == current
                else { continue }
                return true
            }
            stack.append(contentsOf: sema.symbols.directSupertypes(for: current))
        }
        return false
    }

    private func objectLiteralMemberHasInferredSignatureType(_ functionDecl: FunDecl) -> Bool {
        if functionDecl.returnType == nil, case .expr = functionDecl.body {
            return true
        }
        return functionDecl.valueParams.contains { $0.type == nil }
    }

    private func objectLiteralMemberSpelledTypeNames(
        _ functionDecl: FunDecl,
        ast: ASTModule
    ) -> Set<InternedString> {
        var names: Set<InternedString> = []
        for typeParameter in functionDecl.typeParams {
            for bound in typeParameter.upperBounds {
                collectObjectLiteralTypeRefNames(bound, ast: ast, into: &names)
            }
        }
        if let receiverType = functionDecl.receiverType {
            collectObjectLiteralTypeRefNames(receiverType, ast: ast, into: &names)
        }
        for contextReceiver in functionDecl.contextReceivers {
            collectObjectLiteralTypeRefNames(contextReceiver.type, ast: ast, into: &names)
        }
        for valueParam in functionDecl.valueParams {
            if let typeRef = valueParam.type {
                collectObjectLiteralTypeRefNames(typeRef, ast: ast, into: &names)
            }
        }
        if let returnType = functionDecl.returnType {
            collectObjectLiteralTypeRefNames(returnType, ast: ast, into: &names)
        }
        return names
    }

    private func collectObjectLiteralTypeRefNames(
        _ typeRefID: TypeRefID,
        ast: ASTModule,
        into names: inout Set<InternedString>
    ) {
        guard let typeRef = ast.arena.typeRef(typeRefID) else { return }
        switch typeRef {
        case .named, .qualifiedNamed:
            guard let namedType = typeRef.namedType else { return }
            if let last = namedType.path.last {
                names.insert(last)
            }
            for arg in namedType.args {
                switch arg {
                case let .invariant(typeRef), let .out(typeRef), let .in(typeRef):
                    collectObjectLiteralTypeRefNames(typeRef, ast: ast, into: &names)
                case .star:
                    break
                }
            }
        case let .functionType(contextReceivers, receiver, params, returnType, _, _):
            for typeRef in contextReceivers {
                collectObjectLiteralTypeRefNames(typeRef, ast: ast, into: &names)
            }
            if let receiver {
                collectObjectLiteralTypeRefNames(receiver, ast: ast, into: &names)
            }
            for param in params {
                collectObjectLiteralTypeRefNames(param, ast: ast, into: &names)
            }
            collectObjectLiteralTypeRefNames(returnType, ast: ast, into: &names)
        case let .intersection(parts):
            for part in parts {
                collectObjectLiteralTypeRefNames(part, ast: ast, into: &names)
            }
        case let .annotated(base, _):
            collectObjectLiteralTypeRefNames(base, ast: ast, into: &names)
        }
    }
}
