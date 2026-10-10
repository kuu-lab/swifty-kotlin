
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
                    diagnostics: ctx.semaCtx.diagnostics
                )
                sema.bindings.bindExprType(id, type: resolved)
                return resolved
            }
            // No superTypes and no declID → malformed object literal;
            // upstream parser already emitted an error.
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
        let objectType = sema.types.make(.classType(ClassType(
            classSymbol: objectSymbol,
            args: [],
            nullability: .nonNull
        )))
        sema.bindings.bindExprType(id, type: objectType)
        return objectType
    }

    /// `fqNamePrefix` namespaces a *named local* `object` (`{ object L {} }`,
    /// KUU-555): such a declaration is visible only inside its block but must
    /// still carry an FQ name that cannot collide with a same-named
    /// file-scope symbol — the caller passes a per-expression prefix like
    /// `__localdecl_<exprID>`. Object literals pass `[]` and keep their
    /// synthetic name as the FQ name's only component.
    /// `symbolKind` is `.class` for object literals (matching the anonymous-
    /// class treatment) and `.object` for a named local `object` — like a
    /// file-scope `object` declaration, its name in expression position
    /// denotes the singleton instance, not a class-name receiver.
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

        if let existing = sema.bindings.declSymbols[declID] {
            return existing
        }

        // KSP-CAP-001: snapshot the enclosing scope's local bindings before
        // this object literal (or its member type-checking below) adds
        // anything of its own, so member function bodies can be seeded with
        // exactly what was visible at the point the object literal appears —
        // mirroring how lambda bodies capture outer locals.
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
                      let ownerSymbol = sema.symbols.parentSymbol(for: symbol.id),
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
        // Outer receiver `this` symbols (see `outerReceiverTypes`) are also
        // reachable here: the enclosing object literal captured them, so a
        // nested literal can capture them again through the same chain even
        // though the enclosing member's `this` binding shadows them in
        // `outerLocalsSnapshot`.
        var captureOuterSymbols = outerSymbols
            .union(outerReceiverPropertySymbols)
            .union(ctx.outerReceiverTypes.compactMap(\.symbol))
            .union(ctx.implicitReceiverStack.map(\.symbol))
        // An unqualified call to an enclosing class member still needs that
        // receiver after the object literal's own receiver becomes active.
        // Capture the enclosing receiver symbol as a value just like a local.
        if let enclosingClassSymbol = ctx.enclosingClassSymbol {
            captureOuterSymbols.insert(enclosingClassSymbol)
        }
        // BUG-inner-outer: same reasoning as `outerClassChain` above -- an
        // unqualified call or `this@Label` naming an ancestor class two or
        // more `$outer` hops out needs that ancestor's own symbol in the
        // capture set too, or `CaptureAnalyzer` never records it.
        captureOuterSymbols.formUnion(outerClassChain)

        let objectSymbol = sema.symbols.define(
            kind: symbolKind,
            name: objectDecl.name,
            fqName: fqNamePrefix + [objectDecl.name],
            declSite: objectDecl.range,
            visibility: .private,
            flags: [.synthetic]
        )
        sema.bindings.bindDecl(declID, symbol: objectSymbol)
        var lexicalEnclosingFQNames: [[InternedString]] = []
        var lexicalScope: Scope? = ctx.scope
        while let scope = lexicalScope as? BaseScope {
            if let memberScope = scope as? ClassMemberScope,
               let owner = sema.symbols.symbol(memberScope.owner) {
                lexicalEnclosingFQNames.append(owner.fqName)
            }
            lexicalScope = scope.parent
        }
        sema.bindings.deferLocalAnnotationTargets(declID, lexicalEnclosingFQNames: lexicalEnclosingFQNames)
        // A literal declared inside a class shares its lexical private scope.
        // Keep that nesting in the symbol graph so its members can read the
        // enclosing class's private constructor properties.
        if let enclosingClassSymbol = ctx.enclosingClassSymbol {
            sema.symbols.setParentSymbol(enclosingClassSymbol, for: objectSymbol)
        }
        sema.symbols.setSourceFileID(ctx.currentFileID, for: objectSymbol)

        var directSuperSymbols: [SymbolID] = []
        directSuperSymbols.reserveCapacity(superTypes.count)
        var directSuperTypeArgs: [SymbolID: [TypeArg]] = [:]
        for superTypeRef in superTypes {
            let resolved = driver.helpers.resolveTypeRef(
                superTypeRef,
                ast: ast,
                sema: sema,
                interner: interner,
                scope: ctx.scope,
                diagnostics: ctx.semaCtx.diagnostics
            )
            if case let .classType(classType) = sema.types.kind(of: resolved),
               !directSuperSymbols.contains(classType.classSymbol)
            {
                directSuperSymbols.append(classType.classSymbol)
                directSuperTypeArgs[classType.classSymbol] = classType.args
            }
        }
        let concreteClassSupers = directSuperSymbols.filter { symbolID in
            guard let symbol = sema.symbols.symbol(symbolID) else {
                return false
            }
            switch symbol.kind {
            case .class, .enumClass, .object, .annotationClass:
                return true
            default:
                return false
            }
        }
        if concreteClassSupers.count > 1 {
            let classNames = concreteClassSupers.compactMap { sema.symbols.symbol($0)?.fqName.last }
                .map { interner.resolve($0) }
                .joined(separator: ", ")
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0170",
                "Object literal '\(interner.resolve(objectDecl.name))' cannot inherit from more than one class. Found: \(classNames).",
                range: objectDecl.range
            )
        }
        sema.symbols.setDirectSupertypes(directSuperSymbols, for: objectSymbol)
        sema.types.setNominalDirectSupertypes(directSuperSymbols, for: objectSymbol)
        for (superSymbol, args) in directSuperTypeArgs {
            sema.symbols.setSupertypeTypeArgs(args, for: objectSymbol, supertype: superSymbol)
            sema.types.setNominalSupertypeTypeArgs(args, for: objectSymbol, supertype: superSymbol)
        }

        let inheritance = DataFlowSemaPhase()
        inheritance.validateSupertypesAreOpen(
            directSupertypes: directSuperSymbols,
            declRange: objectDecl.range,
            symbols: sema.symbols,
            diagnostics: ctx.semaCtx.diagnostics,
            interner: interner
        )

        // Delegate expressions run in the enclosing scope, before the anonymous
        // object's receiver and members become available.
        for entry in objectDecl.superTypeEntries {
            guard let delegateExpr = entry.delegateExpression else { continue }
            let interfaceType = driver.helpers.resolveTypeRef(
                entry.typeRef,
                ast: ast,
                sema: sema,
                interner: interner,
                scope: ctx.scope,
                diagnostics: ctx.semaCtx.diagnostics
            )
            let field = inheritance.registerClassDelegation(
                delegateExpression: delegateExpr,
                interfaceType: interfaceType,
                classSymbol: objectSymbol,
                range: objectDecl.range,
                symbols: sema.symbols,
                types: sema.types,
                diagnostics: ctx.semaCtx.diagnostics,
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
                    diagnostics: ctx.semaCtx.diagnostics
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
        let objectType = sema.types.make(.classType(ClassType(
            classSymbol: objectSymbol,
            args: [],
            nullability: .nonNull
        )))
        let objectScope = ClassMemberScope(
            parent: ctx.scope,
            symbols: sema.symbols,
            ownerSymbol: objectSymbol,
            thisType: objectType
        )
        for propertySymbol in propertySymbolsByDecl.values {
            objectScope.insert(propertySymbol)
        }
        let memberFunctionSymbolsByDecl = collectObjectLiteralMemberFunctions(
            objectDecl.memberFunctions,
            memberFQNamePrefix: objectSymbolFQName,
            objectSymbol: objectSymbol,
            objectType: objectType,
            objectScope: objectScope,
            ctx: ctx
        )
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
        for symbol in sema.symbols.classDelegationForwardingMethodSymbols(forClass: objectSymbol)
            + sema.symbols.classDelegationForwardingPropertySymbols(forClass: objectSymbol)
        {
            objectScope.insert(symbol)
        }
        // An unqualified member call (or `this@Outer`) inside the object
        // literal's member bodies can target the enclosing receiver — the
        // innermost `outerReceiverTypes` entry. Its runtime value is the
        // enclosing function's `this`, which the capture machinery stores
        // into the object literal's fields like any other outer local.
        // Attaching that symbol to the entry is what lets call resolution
        // and capture analysis find it; entries without a symbol stay
        // type-only (`this@Label` typing) as before.
        var objectOuterReceiverTypes = ctx.outerReceiverTypes
        if let thisBinding = outerLocalsSnapshot[ctx.interner.intern("this")] {
            // The stack may name the same receiver under several labels (the
            // class itself and each enclosing member function), so fill every
            // entry whose type is the enclosing `this` type.
            for index in objectOuterReceiverTypes.indices
                where objectOuterReceiverTypes[index].type == thisBinding.type
                && objectOuterReceiverTypes[index].symbol == nil
            {
                objectOuterReceiverTypes[index].symbol = thisBinding.symbol
            }
        }
        // BUG-inner-outer: `this@Label` entries for ancestor classes beyond
        // the immediate enclosing one have no plain local to bind to above
        // (there is no flat `this` for them -- only `$outer.$outer...`), so
        // bind them to the ancestor class's own symbol instead: the same key
        // `outerClassChain`/`captureOuterSymbols` use, which
        // `captureValueExpr`'s class-symbol branch knows how to materialize
        // via `resolveOuterChainValue`.
        for index in objectOuterReceiverTypes.indices where objectOuterReceiverTypes[index].symbol == nil {
            guard let (_, classSymbol) = resolveClassTypeSymbol(objectOuterReceiverTypes[index].type, sema: sema),
                  outerClassChain.contains(classSymbol.id)
            else {
                continue
            }
            objectOuterReceiverTypes[index].symbol = classSymbol.id
        }
        let objectCtx = ctx.withoutSuspensionContext().copying(
            scope: objectScope,
            implicitReceiverType: objectType,
            enclosingClassSymbol: objectSymbol,
            outerReceiverTypes: objectOuterReceiverTypes
        )

        typeCheckLocalNominalMemberProperties(
            objectDecl.memberProperties,
            propertySymbolsByDecl: propertySymbolsByDecl,
            memberScope: objectScope,
            memberCtx: objectCtx,
            initializerLocals: locals,
            accessorBaseLocals: outerLocalsSnapshot,
            ctx: ctx
        )
        // `init {}` blocks are lowered inline in the enclosing function,
        // like property initializers, so they see the outer locals directly
        // and need no capture fields.
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
                ctx: objectCtx.with(currentDeclSymbol: functionSymbol),
                solver: driver.solver,
                diagnostics: ctx.semaCtx.diagnostics,
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
        bindLocalNominalCaptures(
            capturedSymbols,
            ownerSymbol: objectSymbol,
            outerLocalsSnapshot: outerLocalsSnapshot,
            outerReceiverTypes: ctx.outerReceiverTypes,
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
            // `.object`-kind symbols here are named local objects (KUU-555);
            // anonymous object literals keep `.class` and read as
            // "Object expression".
            subjectDescription: sema.symbols.symbol(objectSymbol)?.kind == .object
                ? "Object '\(interner.resolve(objectDecl.name))'"
                : "Object expression",
            ctx: ctx
        )
        return objectSymbol
    }



    /// Registers `.property` symbols for an anonymous or local nominal's
    /// member properties (plus `$backing_<name>` / `$delegate_<name>` storage
    /// symbols) — the same rules `MemberHeaderCollection` applies to named
    /// nominals, keyed by `ownerFQName` so local declarations get unique FQ
    /// names. Marks every symbol `markObjectLiteralPropertySymbol` so member
    /// reads lower as direct field offsets.
    func registerLocalNominalMemberProperties(
        _ memberProperties: [DeclID],
        ownerFQName: [InternedString],
        ownerSymbol: SymbolID,
        markAsSynthetic: Bool = true,
        ctx: TypeInferenceContext
    ) -> [DeclID: SymbolID] {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        var propertySymbolsByDecl: [DeclID: SymbolID] = [:]
        for propertyDeclID in memberProperties {
            guard let decl = ast.arena.decl(propertyDeclID),
                  case let .propertyDecl(propertyDecl) = decl
            else {
                continue
            }
            // Data synthesis selects source properties from the constructor header.
            var propertyFlags: SymbolFlags = markAsSynthetic ? [.synthetic] : []
            if propertyDecl.modifiers.contains(.override) { propertyFlags.insert(.overrideMember) }
            if propertyDecl.modifiers.contains(.open) { propertyFlags.insert(.openType) }
            if propertyDecl.modifiers.contains(.abstract) { propertyFlags.insert(.abstractType) }
            if propertyDecl.modifiers.contains(.final) { propertyFlags.insert(.finalMember) }
            if propertyDecl.isVar {
                propertyFlags.insert(.mutable)
            }
            // Read wrapping (`kk_lateinit_get_or_throw`) and `::p.isInitialized`
            // both key off this flag, exactly as for named-class members.
            if propertyDecl.modifiers.contains(.lateinit) {
                propertyFlags.insert(.lateinitProperty)
            }
            let propertySymbol = sema.symbols.define(
                kind: .property,
                name: propertyDecl.name,
                fqName: ownerFQName + [propertyDecl.name],
                declSite: propertyDecl.range,
                visibility: .public,
                flags: propertyFlags
            )
            sema.bindings.bindDecl(propertyDeclID, symbol: propertySymbol)
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
            func resolvePropertyType(_ reference: TypeRefID) -> TypeID {
                driver.helpers.resolveTypeRef(reference, ast: ast, sema: sema, interner: interner,
                                              scope: propertyScope, diagnostics: ctx.semaCtx.diagnostics,
                                              inferenceContext: ctx, usageRange: propertyDecl.range)
            }
            for (parameter, symbol) in zip(propertyDecl.typeParams, parameters) {
                let bounds = parameter.upperBounds.map(resolvePropertyType)
                if !bounds.isEmpty { sema.symbols.setTypeParameterUpperBounds(bounds, for: symbol) }
                DataFlowSemaPhase.checkConflictingClassUpperBounds(
                    typeParamName: parameter.name, bounds: bounds, declSite: propertyDecl.range,
                    symbols: sema.symbols, types: sema.types, interner: interner,
                    diagnostics: ctx.semaCtx.diagnostics
                )
            }
            let declaredType = propertyDecl.type.map(resolvePropertyType) ?? sema.types.anyType
            sema.symbols.setPropertyType(declaredType, for: propertySymbol)
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

            // BUG-267: mirror `MemberHeaderCollection`'s delegate-storage
            // rule — a `by`-delegated property stores the delegate instance
            // in its own `$delegate_<name>` field; the property symbol itself
            // gets no storage slot.
            if propertyDecl.delegateExpression != nil {
                let delegateStorageName = interner.intern("$delegate_\(interner.resolve(propertyDecl.name))")
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

    /// Type-checks member properties of an anonymous or local nominal:
    /// declared type -> initializer -> custom getter -> `by` delegate ->
    /// setter, in the owner nominal's member scope. `initializerLocals` is the
    /// binding set initializer/delegate expressions infer against (the
    /// enclosing scope for object literals, ctor-param + captured locals for
    /// a local class whose initializers run inside `<init>`); accessors,
    /// lowered as standalone KIR functions, get `accessorBaseLocals`.
    func typeCheckLocalNominalMemberProperties(
        _ memberProperties: [DeclID],
        propertySymbolsByDecl: [DeclID: SymbolID],
        memberScope: ClassMemberScope,
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
            guard let propertySymbol = propertySymbolsByDecl[propertyDeclID],
                  let decl = ast.arena.decl(propertyDeclID),
                  case let .propertyDecl(propertyDecl) = decl
            else {
                continue
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
                        diagnostics: ctx.semaCtx.diagnostics
                    )
                }
                inferredType = type
            }

            // KSP-CAP-018: type-check the property's custom accessor bodies in
            // the object literal's own member scope. This loop used to visit
            // only the initializer, so identifiers inside a getter/setter body
            // never got an `identifierSymbols` binding and KIR lowering had
            // nothing to resolve them against — it fell back to emitting
            // `.unit`, exactly the failure mode the `typeCheckDelegate` note in
            // `DeclTypeChecker` describes for delegate bodies. Ordering mirrors
            // the named path in `DeclTypeChecker.typeCheckPropertyDecl`: the
            // getter can supply the property's type, the setter needs it final.
            var accessorCtx = driver.declChecker.propertyTypeParameterContext(
                propertyDecl, symbol: propertySymbol, ctx: memberCtx, diagnostics: ctx.semaCtx.diagnostics
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
                    symbol: propertySymbol,
                    inferredPropertyType: declaredType ?? inferredType,
                    accessorCtx: accessorCtx,
                    solver: driver.solver,
                    diagnostics: ctx.semaCtx.diagnostics,
                    baseLocals: accessorBaseLocals
                )
            }

            // BUG-267: type-check `by` delegate expressions through the same
            // convention path named classes use (`DeclTypeChecker.typeCheck
            // PropertyDecl`). This binds the delegate expression's identifiers,
            // resolves and records the delegate's getValue/setValue (and
            // provideDelegate) operator symbols for KIR lowering, and can
            // infer the property type from getValue's return type.
            if let delegateExpr = propertyDecl.delegateExpression {
                inferredType = driver.declChecker.typeCheckDelegate(
                    delegateExpr,
                    isVar: propertyDecl.isVar,
                    fallbackRange: propertyDecl.range,
                    symbol: propertySymbol,
                    inferredPropertyType: declaredType ?? inferredType,
                    ctx: memberCtx,
                    locals: &initializerLocals,
                    diagnostics: ctx.semaCtx.diagnostics,
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
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0101",
                    "Property '\(interner.resolve(propertyDecl.name))' in object literal must have a type annotation or initializer.",
                    range: propertyDecl.range
                )
                finalType = sema.types.errorType
            }
            sema.symbols.setPropertyType(finalType, for: propertySymbol)

            if let setter = propertyDecl.setter, setter.body != .unit {
                driver.declChecker.typeCheckSetter(
                    setter,
                    property: propertyDecl,
                    symbol: propertySymbol,
                    finalPropertyType: finalType,
                    accessorCtx: accessorCtx,
                    solver: driver.solver,
                    diagnostics: ctx.semaCtx.diagnostics,
                    baseLocals: accessorBaseLocals
                )
            }
        }
    }

    /// Unions the captured-outer-symbol sets of a local nominal's accessor
    /// bodies (always lowered as standalone KIR functions) and any caller-
    /// supplied roots: `extraBodies` covers `init {}` blocks and
    /// `extraExprRoots` covers superclass constructor arguments.
    /// `includePropertyInitializers` also collects ordinary property
    /// initializers and delegated-property expressions; all of these lower
    /// inside `<init>` for a local class, unlike an object literal where they
    /// run inline in the enclosing function.
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
                        outerSymbols: captureOuterSymbols
                    ))
                }
            }
        }
        for body in extraBodies {
            capturedSymbols.formUnion(driver.captureAnalyzer.collectCapturedOuterSymbols(
                inBody: body,
                ast: ast,
                sema: sema,
                outerSymbols: captureOuterSymbols
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

    /// Records the captured-symbol list on the owner nominal (read by
    /// `ObjectLiteralLowerer` at materialization time) and binds each
    /// captured local's type so member functions lowered as independent KIR
    /// functions can read the field back.
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

    /// Assigns the field/vtable/itable layout for a nominal synthesized
    /// during body inference (object literal, named local `class`/`object`).
    /// Such nominals are only known once the enclosing function body is
    /// type-checked, well after `synthesizeNominalLayouts` assigned slots for
    /// every named nominal (see `runValidationPasses` vs. `runBodyAnalysis`
    /// in Phase.swift), so the layout is built here: inherited slots from the
    /// class-kind supertype, then storage for member properties (keyed by
    /// backing/delegate storage symbol), captured locals, override vtable
    /// slots, and transitive-interface itable slots.
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
        let inheritedLayout = superClass.flatMap { sema.symbols.nominalLayout(for: $0) }
        var fieldOffsets = inheritedLayout?.fieldOffsets ?? [:]
        let objectHeaderWords = inheritedLayout?.objectHeaderWords ?? 2
        var nextFieldOffset = (fieldOffsets.values.max() ?? (objectHeaderWords - 1)) + 1
        for propertyDeclID in memberPropertyDecls {
            guard let propertySymbol = propertySymbolsByDecl[propertyDeclID] else {
                continue
            }
            // KSP-CAP-018: key the slot by the backing field when the property
            // has one, mirroring `LayoutSynthesis.synthesizeLayoutForNominal`
            // and every `backingFieldSymbol(for:) ?? propertySymbol` lookup on
            // the lowering side. BUG-267: a delegated property's slot is keyed
            // by its `$delegate_<name>` storage symbol instead — the property
            // symbol itself holds no storage (same as `LayoutSynthesis` does
            // for named-class delegated members).
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
        // KSP-CAP-001: give each captured outer local/parameter its own
        // instance field so member functions (lowered as independent KIR
        // functions, unlike inlined property initializers) can read the
        // captured value back through `this` regardless of which method
        // originally referenced it.
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
                if let matchedSlot = resolveOverriddenVtableSlot(parameterTypes: parameterTypes, candidates: candidates, types: sema.types) {
                    vtableSlots[method.id] = matchedSlot
                    continue
                }
            }
            vtableSlots[method.id] = nextVtableSlot
            nextVtableSlot += 1
        }

        // KUU-1251: inherited methods read properties through the base class's
        // vtable slots. Local/anonymous overrides must replace those getter
        // and setter implementations, just as header-time named layouts do.
        if let owner = sema.symbols.symbol(ownerSymbol) {
            DataFlowSemaPhase.assignPropertyAccessorVtableSlots(
                for: owner,
                symbols: sema.symbols,
                inheritedVtable: inheritedVtableSlots,
                vtableSlots: &vtableSlots,
                nextVtableSlot: &nextVtableSlot
            )
        }

        // BUG-242: mirror the named-class path
        // (`LayoutSynthesis.synthesizeLayoutForNominal`) by walking this
        // nominal's own transitive interface supertypes and assigning each
        // one not already covered by inheritance a fresh itable slot.
        var itableSlots = inheritedItableSlots
        var nextItableSlot = max(inheritedItableSize ?? 0, (itableSlots.values.max() ?? -1) + 1)
        for interfaceID in kirTransitiveInterfaceSupertypes(of: ownerSymbol, sema: sema)
            where itableSlots[interfaceID] == nil
        {
            itableSlots[interfaceID] = nextItableSlot
            nextItableSlot += 1
        }

        // KSP-CAP-018: these nominals are always concrete, so they must
        // implement every inherited abstract member — `object : Animal() {}`
        // over `abstract fun speak()` is an error in Kotlin. The named-nominal
        // check (`Inheritance.validateAbstractOverrides`) ran during header
        // validation, before this symbol existed.
        var overriddenNames: Set<InternedString> = []
        for functionDeclID in memberFunctionDecls {
            guard let decl = ast.arena.decl(functionDeclID),
                  case let .funDecl(functionDecl) = decl
            else { continue }
            overriddenNames.insert(functionDecl.name)
        }
        for propertyDeclID in memberPropertyDecls {
            guard let decl = ast.arena.decl(propertyDeclID),
                  case let .propertyDecl(propertyDecl) = decl
            else { continue }
            overriddenNames.insert(propertyDecl.name)
        }
        for missingMember in unimplementedAbstractMembers(
            for: ownerSymbol,
            overriddenNames: overriddenNames,
            delegatedInterfaces: sema.symbols.delegatedInterfaces(forClass: ownerSymbol),
            symbols: sema.symbols,
            interner: interner
        ) {
            guard let missingSymbol = sema.symbols.symbol(missingMember) else {
                continue
            }
            ctx.semaCtx.diagnostics.error(
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
                superClass: superClass
            ),
            for: ownerSymbol
        )
    }

    /// Defines member-function symbols for an anonymous or local nominal
    /// (object literal, named local `object`, named local `class`).
    /// `memberFQNamePrefix` is the owning nominal's FQ name — members get
    /// `<prefix> + [memberName]`, parameters `<prefix> + [memberName, paramName]`.
    func collectObjectLiteralMemberFunctions(
        _ memberFunctions: [DeclID],
        memberFQNamePrefix: [InternedString],
        objectSymbol: SymbolID,
        objectType: TypeID,
        objectScope: ClassMemberScope,
        ctx: TypeInferenceContext
    ) -> [DeclID: SymbolID] {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        var result: [DeclID: SymbolID] = [:]

        for functionDeclID in memberFunctions {
            guard let decl = ast.arena.decl(functionDeclID),
                  case let .funDecl(functionDecl) = decl
            else {
                continue
            }

            let memberSymbol = sema.symbols.define(
                kind: .function,
                name: functionDecl.name,
                fqName: memberFQNamePrefix + [functionDecl.name],
                declSite: functionDecl.range,
                visibility: Visibility(modifiers: functionDecl.modifiers),
                flags: objectLiteralFunctionFlags(
                    from: functionDecl,
                    objectSymbol: objectSymbol,
                    sema: sema,
                    interner: interner
                )
            )
            sema.bindings.bindDecl(functionDeclID, symbol: memberSymbol)
            sema.symbols.setParentSymbol(objectSymbol, for: memberSymbol)
            sema.symbols.setSourceFileID(ctx.currentFileID, for: memberSymbol)
            objectScope.insert(memberSymbol)

            var parameterTypes: [TypeID] = []
            var parameterSymbols: [SymbolID] = []
            for param in functionDecl.valueParams {
                let paramType: TypeID = if let typeRefID = param.type {
                    driver.helpers.resolveTypeRef(
                        typeRefID,
                        ast: ast,
                        sema: sema,
                        interner: interner,
                        scope: objectScope,
                        diagnostics: ctx.semaCtx.diagnostics,
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

            let returnType: TypeID
            if let returnTypeRef = functionDecl.returnType {
                returnType = driver.helpers.resolveTypeRef(
                    returnTypeRef,
                    ast: ast,
                    sema: sema,
                    interner: interner,
                    scope: objectScope,
                    diagnostics: ctx.semaCtx.diagnostics,
                    inferenceContext: ctx
                )
            } else {
                switch functionDecl.body {
                case .unit, .block:
                    returnType = sema.types.unitType
                case .expr:
                    returnType = sema.types.anyType
                }
            }

            sema.symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: objectType,
                    parameterTypes: parameterTypes,
                    returnType: returnType,
                    isSuspend: functionDecl.isSuspend,
                    valueParameterSymbols: parameterSymbols,
                    valueParameterHasDefaultValues: functionDecl.valueParams.map(\.hasDefaultValue),
                    valueParameterIsVararg: functionDecl.valueParams.map(\.isVararg)
                ),
                for: memberSymbol
            )
            // Resolve the exact overridden signature before inheriting infix;
            // another overload with the same name and arity may lack it.
            if DataFlowSemaPhase().nearestOverriddenFunctionCandidates(
                of: memberSymbol, symbols: sema.symbols, types: sema.types
            ).contains(where: { sema.symbols.symbol($0)?.flags.contains(.infixFunction) == true }) {
                sema.symbols.insertFlags(.infixFunction, for: memberSymbol)
            }
            result[functionDeclID] = memberSymbol
        }

        return result
    }

    private func objectLiteralFunctionFlags(
        from functionDecl: FunDecl,
        objectSymbol: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolFlags {
        var flags: SymbolFlags = [.synthetic]
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
               sema: sema,
               interner: interner
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
        sema: SemaModule,
        interner: StringInterner
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
}
