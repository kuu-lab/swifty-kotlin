extension ExprTypeChecker {
    /// Publish an anonymous object's identity and declared supertypes without
    /// checking constructor arguments, delegates, or member bodies early.
    func predeclareObjectLiteralSymbol(
        declID: DeclID,
        objectDecl: ObjectDecl,
        superTypes: [TypeRefID],
        fqNamePrefix: [InternedString] = [],
        symbolKind: SymbolKind = .class,
        ctx: TypeInferenceContext
    ) -> SymbolID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        if let existing = sema.bindings.declSymbols[declID] {
            return existing
        }

        let objectSymbol = sema.symbols.define(
            kind: symbolKind,
            name: objectDecl.name,
            fqName: fqNamePrefix + [objectDecl.name],
            declSite: objectDecl.range,
            visibility: .private,
            flags: symbolKind == .class ? [.synthetic, .objectLiteralType] : [.synthetic]
        )
        sema.bindings.bindDecl(declID, symbol: objectSymbol)
        let capturedTypeParameters = driver.helpers.lexicalTypeParameterSymbols(in: ctx)
            .sorted { $0.rawValue < $1.rawValue }
        sema.types.setNominalTypeParameterSymbols(capturedTypeParameters, for: objectSymbol)
        var lexicalEnclosingFQNames: [[InternedString]] = []
        var lexicalScope: Scope? = ctx.scope
        while let scope = lexicalScope as? BaseScope {
            if let memberScope = scope as? ClassMemberScope,
               let owner = sema.symbols.symbol(memberScope.owner) {
                lexicalEnclosingFQNames.append(owner.fqName)
            }
            lexicalScope = scope.parent
        }
        sema.bindings.deferAnnotationTargets(declID, lexicalEnclosingFQNames: lexicalEnclosingFQNames)
        // A literal declared inside a class shares its lexical private scope.
        // Keep that nesting in the symbol graph so its members can read the
        // enclosing class's private constructor properties.
        if let enclosingClassSymbol = ctx.enclosingClassSymbol {
            sema.symbols.setParentSymbol(enclosingClassSymbol, for: objectSymbol)
        }
        sema.symbols.setSourceFileID(ctx.currentFileID, for: objectSymbol)

        let declIsBundledStdlib = driver.sourceManager?
            .origin(of: ctx.currentFileID)?.isBundledStdlib == true
        var directSuperSymbols: [SymbolID] = []
        directSuperSymbols.reserveCapacity(superTypes.count)
        var directSuperTypeArgs: [SymbolID: [TypeArg]] = [:]
        for (index, superTypeRef) in superTypes.enumerated() {
            let resolved = driver.helpers.resolveTypeRef(
                superTypeRef,
                ast: ast,
                sema: sema,
                interner: interner,
                scope: ctx.scope,
                diagnostics: ctx.sema.diagnostics
            )
            if case let .classType(classType) = sema.types.kind(of: resolved),
               !directSuperSymbols.contains(classType.classSymbol)
            {
                if index < objectDecl.superTypeEntries.count {
                    let entry = objectDecl.superTypeEntries[index]
                    if !entry.hasConstructorCallSyntax,
                       entry.delegateExpression == nil,
                       sema.symbols.symbol(classType.classSymbol)?.kind == .class,
                       !declIsBundledStdlib
                    {
                        ctx.sema.diagnostics.error(
                            "KSWIFTK-SEMA-0436",
                            "this type has a constructor, so it must be initialized here.",
                            range: entry.range ?? objectDecl.range
                        )
                    }
                }
                directSuperSymbols.append(classType.classSymbol)
                // Keep the qualifier's arguments as well: `Outer<Int>.I`
                // stores `Int` in `enclosingTypeArgs`, and the inner
                // constructor needs it to bind `V` during super-delegation
                // resolution (KUU-3859). `classType(for:)` splits the flat
                // list back into enclosing + own arguments.
                directSuperTypeArgs[classType.classSymbol] = sema.types
                    .allTypeArguments(for: classType)
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
            ctx.sema.diagnostics.error(
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
            diagnostics: ctx.sema.diagnostics,
            interner: interner
        )

        driver.predeclaredObjectLiteralDecls.insert(declID)
        return objectSymbol
    }

    func objectLiteralType(for symbol: SymbolID, sema: SemaModule) -> TypeID {
        let arguments = sema.types.nominalTypeParameterSymbols(for: symbol).map { parameter in
            TypeArg.invariant(sema.types.make(.typeParam(TypeParamType(
                symbol: parameter,
                nullability: .nonNull
            ))))
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: symbol,
            args: arguments,
            nullability: .nonNull
        )))
    }
}
