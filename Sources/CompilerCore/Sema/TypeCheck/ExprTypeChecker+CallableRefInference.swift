
extension ExprTypeChecker {
    /// Visible `<init>` symbols of a concrete class, or `nil` for an abstract
    /// class or one without constructors. Constructors live under the class's
    /// own FQ name with the reserved `<init>` short name (HeaderHelpers.swift).
    private func visibleConstructorCandidates(
        of classSymbol: SemanticSymbol,
        ctx: TypeInferenceContext
    ) -> [SymbolID]? {
        guard !classSymbol.flags.contains(.abstractType) else {
            return nil
        }
        let ctorSymbols = ctx.sema.symbols.lookupAll(
            fqName: classSymbol.fqName + [ctx.interner.intern("<init>")]
        )
        guard !ctorSymbols.isEmpty else {
            return nil
        }
        return ctx.filterByVisibility(ctorSymbols).0
    }

    private func bindCallableReferenceBinding(
        _ expression: ExprID, target: SymbolID, specialization: ContextualCallableReferenceBinding,
        range: SourceRange, ctx: TypeInferenceContext, requiresFunctionConversion: Bool = false,
        dispatchReceiverSymbol: SymbolID? = nil
    ) {
        guard let signature = ctx.sema.symbols.functionSignature(for: target) else { return }
        for index in signature.reifiedTypeParameterIndices.sorted() where index < specialization.typeArguments.count {
            if case let .typeParam(parameter) = ctx.sema.types.kind(of: specialization.typeArguments[index]),
               ctx.sema.symbols.symbol(parameter.symbol)?.flags.contains(.reifiedTypeParameter) != true {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-REIFIED", "Cannot use an unreified type parameter as a reified type argument.", range: range
                )
            }
        }
        ctx.sema.bindings.bindCallableReference(expression, binding: CallBinding(
            chosenCallee: target,
            substitutedTypeArguments: specialization.typeArguments,
            parameterMapping: specialization.parameterMapping,
            defaultArgumentOwner: specialization.defaultArgumentOwner,
            dispatchReceiverSymbol: dispatchReceiverSymbol,
            isCallableReferenceAdapter: specialization.requiresAdapter || requiresFunctionConversion,
            hidesKCallable: specialization.isSignatureAdapted || requiresFunctionConversion,
            boundContextParameterTypes: specialization.boundContextParameterTypes
        ))
    }

    /// Enum `valueOf` is exposed through the enum class name even though its
    /// synthetic declaration is owned by the companion object. Kotlin binds
    /// that singleton receiver implicitly for `EnumType::valueOf`.
    private func enumCompanionValueOfCallableReference(
        named member: InternedString,
        receiverType: TypeID,
        isUnboundTypeReceiver: Bool,
        ctx: TypeInferenceContext
    ) -> (receiverType: TypeID, candidates: [SymbolID])? {
        let sema = ctx.sema
        let interner = ctx.interner
        guard isUnboundTypeReceiver,
              member == interner.intern("valueOf"),
              let (_, enumSymbol) = resolveClassTypeSymbol(receiverType, sema: sema),
              enumSymbol.kind == .enumClass,
              let companionSymbol = sema.symbols.companionObjectSymbol(for: enumSymbol.id)
        else {
            return nil
        }

        let companionType = sema.symbols.propertyType(for: companionSymbol)
            ?? sema.types.make(.classType(ClassType(
                classSymbol: companionSymbol,
                args: [],
                nullability: .nonNull
            )))
        let candidates = driver.helpers.collectMemberFunctionCandidates(
            named: member,
            receiverType: companionType,
            sema: sema,
            interner: interner
        )
        guard !candidates.isEmpty else { return nil }
        return (companionType, candidates)
    }

    /// `Type::member` can fall back to the class's companion scope when no
    /// member is declared on the class itself. The companion is a singleton,
    /// so this reference captures it instead of adding the class as an input.
    private func companionMemberCallableReference(
        named member: InternedString,
        receiverType: TypeID,
        isUnboundTypeReceiver: Bool,
        ctx: TypeInferenceContext
    ) -> (receiverType: TypeID, candidates: [SymbolID])? {
        let sema = ctx.sema
        let interner = ctx.interner
        guard isUnboundTypeReceiver,
              let (_, ownerSymbol) = resolveClassTypeSymbol(receiverType, sema: sema)
        else {
            return nil
        }

        let companionSymbol = sema.symbols.companionBlockObjectSymbol(
            for: ownerSymbol.id,
            interner: interner
        ) ?? sema.symbols.companionObjectSymbol(for: ownerSymbol.id)
            ?? sema.symbols.actualSymbol(for: ownerSymbol.id).flatMap {
                sema.symbols.companionBlockObjectSymbol(for: $0, interner: interner)
                    ?? sema.symbols.companionObjectSymbol(for: $0)
            }
        guard let companionSymbol else { return nil }

        let companionType = sema.symbols.propertyType(for: companionSymbol)
            ?? sema.types.make(.classType(ClassType(
                classSymbol: companionSymbol,
                args: [],
                nullability: .nonNull
            )))
        let candidates = driver.helpers.collectMemberFunctionCandidates(
            named: member,
            receiverType: companionType,
            sema: sema,
            interner: interner
        ).filter { candidate in
            !driver.helpers.declaresExtensionReceiver(
                candidate,
                sema: sema,
                interner: interner
            )
        }
        guard !candidates.isEmpty else { return nil }
        return (companionType, candidates)
    }

    /// In value position a bare class name denotes its companion object, so
    /// `A::member` also carries a bound interpretation on the `A.Companion`
    /// singleton — the same candidate space `A.Companion::member` resolves.
    /// Which members that singleton can actually receive is decided by the
    /// per-candidate receiver checks: members and extensions declared on
    /// `A.Companion` always accept it, while members and extensions declared
    /// on `A` need the companion itself to inherit `A`
    /// (`companion object : A()`, JetBrains
    /// companionObjectReceiverInheritsFromOuter.kt). Returns the companion's
    /// receiver type, or `nil` when the class has no companion at all.
    private func classNameCompanionCallableReferenceReceiverType(
        for unboundClassType: TypeID,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        guard let (_, ownerSymbol) = resolveClassTypeSymbol(unboundClassType, sema: sema)
        else {
            return nil
        }
        let companionSymbol = sema.symbols.companionBlockObjectSymbol(
            for: ownerSymbol.id,
            interner: interner
        ) ?? sema.symbols.companionObjectSymbol(for: ownerSymbol.id)
            ?? sema.symbols.actualSymbol(for: ownerSymbol.id).flatMap {
                sema.symbols.companionBlockObjectSymbol(for: $0, interner: interner)
                    ?? sema.symbols.companionObjectSymbol(for: $0)
            }
        guard let companionSymbol else { return nil }
        return sema.symbols.propertyType(for: companionSymbol)
            ?? sema.types.make(.classType(ClassType(
                classSymbol: companionSymbol,
                args: [],
                nullability: .nonNull
            )))
    }

    func inferCallableRefExpr(
        _ id: ExprID,
        receiver: ExprID?,
        member: InternedString,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let availableContextReceiverTypes = ctx.contextReceiverTypes
            + ctx.implicitReceiverStack.map(\.type)
            + ctx.outerReceiverTypes.map(\.type)
            + (ctx.implicitReceiverType.map { [$0] } ?? [])
        let outerSymbols = Set(locals.values.map(\.symbol))
        sema.bindings.bindCallableReference(id, binding: nil)

        if let expectedType, sema.types.nominalFunctionType(for: expectedType) != nil {
            sema.bindings.bindNominalFunctionExpectedType(id, type: expectedType)
        }

        if member == KnownCompilerNames(interner: interner).className,
           let receiverTypeRef = ast.arena.callableRefReceiverTypeRef(for: id)
        {
            return inferExplicitArrayClassRef(
                id, receiverTypeRef: receiverTypeRef, range: range, ctx: ctx
            )
        }

        if member == KnownCompilerNames(interner: interner).className,
           let receiver,
           case let .nameRef(receiverName, _) = ast.arena.expr(receiver),
           locals[receiverName] == nil
        {
            if let result = inferClassRefExpr(
                id, receiver: receiver, receiverName: receiverName,
                range: range, ctx: ctx, locals: &locals
            ) {
                return result
            }
        }

        if member == KnownCompilerNames(interner: interner).className,
           let receiver
        {
            if let result = inferQualifiedClassRefExpr(
                id, receiver: receiver, range: range, ctx: ctx, locals: locals
            ) {
                return result
            }
            return inferExprReceiverClassRef(
                id, receiver: receiver, range: range, ctx: ctx, locals: &locals
            )
        }

        // `plus`/`times` on a primitive numeric receiver are a table-driven
        // type-inference special case (tryInferRegularMemberCallPrimitiveSpecials),
        // not a real member declaration -- ordinary candidate lookup below
        // (`.function || .constructor` on `member`) always comes up empty for
        // them. Handled first and unconditionally: unlike `Type::member`, a
        // primitive receiver name never introduces real function/constructor
        // candidates that this could shadow.
        if let receiver,
           ast.arena.callableRefReceiverTypeRef(for: id) == nil,
           case let .nameRef(receiverName, _) = ast.arena.expr(receiver),
           locals[receiverName] == nil,
           let result = inferPrimitiveOperatorCallableRefExpr(
               id, receiverName: receiverName, member: member,
               expectedType: expectedType, range: range, ctx: ctx
           )
        {
            return result
        }

        // Keep this callable-reference-only; regular member and
        // unary-expression resolution retain their existing paths.
        if let receiver,
           ast.arena.callableRefReceiverTypeRef(for: id) == nil,
           case let .nameRef(receiverName, _) = ast.arena.expr(receiver),
           locals[receiverName] == nil,
           let result = inferPrimitiveUnaryOperatorCallableRefExpr(
               id, receiverName: receiverName, member: member,
               expectedType: expectedType, range: range, ctx: ctx
           )
        {
            return result
        }

        var unboundClassType: TypeID?
        if let receiverTypeRef = ast.arena.callableRefReceiverTypeRef(for: id) {
            unboundClassType = driver.helpers.resolveTypeRef(
                receiverTypeRef,
                ast: ast,
                sema: sema,
                interner: interner,
                scope: ctx.scope,
                diagnostics: ctx.sema.diagnostics,
                inferenceContext: ctx,
                usageRange: range
            )
            if let unboundClassType {
                let argumentCounts: (expected: Int, actual: Int)?
                if case let .classType(owner) = sema.types.kind(of: unboundClassType) {
                    argumentCounts = (sema.types.nominalTypeParameterSymbols(for: owner.classSymbol).count, owner.args.count)
                } else if case let .named(path, arguments, _) = ast.arena.typeRef(receiverTypeRef),
                          let name = path.last,
                          driver.helpers.resolveBuiltinTypeName(name, types: sema.types, interner: interner) != nil
                {
                    argumentCounts = (0, arguments.count)
                } else {
                    argumentCounts = nil
                }
                if let argumentCounts, argumentCounts.expected != argumentCounts.actual {
                    ctx.sema.diagnostics.error(
                        "KSWIFTK-SEMA-0062",
                        "Type argument count mismatch: expected \(argumentCounts.expected) but got \(argumentCounts.actual).",
                        range: range
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
            }
        } else if let receiver,
           case let .nameRef(receiverName, _) = ast.arena.expr(receiver),
           let local = locals[receiverName],
           let symbol = sema.symbols.symbol(local.symbol),
           (symbol.kind == .class || symbol.kind == .interface || symbol.kind == .enumClass)
        {
            // A local class name also enters LocalBindings so member calls can
            // resolve. Recognize its classifier symbol; local value receivers
            // continue to be treated as bound callable-reference receivers.
            unboundClassType = local.type
        } else if let receiver,
           case let .nameRef(receiverName, _) = ast.arena.expr(receiver),
           locals[receiverName] == nil
        {
            // A local with this name is a bound receiver, so only unresolved
            // names can introduce an unbound type reference.
            let allCandidateIDs = ctx.cachedScopeLookup(receiverName)
            for candidateID in allCandidateIDs {
                guard let sym = ctx.cachedSymbol(candidateID),
                      sym.kind == .class || sym.kind == .interface
                      || sym.kind == .enumClass
                else { continue }
                // Primitive class names are represented by dedicated primitive
                // TypeIDs at expression sites. Keep that representation here so
                // member lookup also probes package-level extensions such as
                // `Char::titlecase` in kotlin.text.
                if let primitive = driver.builtinTypeNamesCache.primitiveType(for: sym.name) {
                    unboundClassType = sema.types.make(.primitive(primitive, .nonNull))
                } else if let builtin = driver.builtinTypeNamesCache.resolveBuiltinType(sym.name, types: sema.types) {
                    unboundClassType = builtin
                } else {
                    unboundClassType = sema.types.make(
                        .classType(ClassType(classSymbol: sym.id, args: [], nullability: .nonNull))
                    )
                }
                break
            }

            if unboundClassType == nil {
                if let primitive = driver.builtinTypeNamesCache.primitiveType(for: receiverName) {
                    // Builtin primitive classes may not be present in the lexical scope,
                    // but their callable references still use the primitive receiver path.
                    unboundClassType = sema.types.make(.primitive(primitive, .nonNull))
                } else if let builtin = driver.builtinTypeNamesCache.resolveBuiltinType(receiverName, types: sema.types) {
                    unboundClassType = builtin
                }
            }
        }

        let receiverType: TypeID?
        if let receiver, let unboundClassType {
            sema.bindings.bindExprType(receiver, type: unboundClassType)
            if let (_, symbol) = resolveClassTypeSymbol(unboundClassType, sema: sema) {
                sema.bindings.bindIdentifier(receiver, symbol: symbol.id)
            }
            receiverType = unboundClassType
        } else if let receiver {
            let inferredReceiverType = driver.inferExpr(receiver, ctx: ctx, locals: &locals, expectedType: nil)
            // A qualified classifier such as `A.B` is parsed as a member
            // expression before `::` is recognized. Its final identifier is
            // nevertheless bound to the nested classifier symbol; preserve
            // that type receiver as unbound instead of capturing it as a value.
            // A labeled `this@Owner` also binds to its owning class symbol, but
            // it is still a value receiver and must be captured for a bound
            // callable reference such as `this@Outer::greet`.
            if case .thisRef = ast.arena.expr(receiver) {
                // Keep the inferred receiver type without classifying `this` as a type reference.
            } else if let symbolID = sema.bindings.identifierSymbols[receiver],
               let symbol = sema.symbols.symbol(symbolID),
               symbol.kind == .class || symbol.kind == .interface || symbol.kind == .enumClass,
               case .classType = sema.types.kind(of: inferredReceiverType)
            {
                unboundClassType = inferredReceiverType
            }
            receiverType = inferredReceiverType
        } else {
            receiverType = nil
        }

        // For unbound type references, use the resolved class type for
        // member lookup instead of the expression-inferred type (which
        // may degrade to Any for classes without companion objects).
        let effectiveReceiverType = unboundClassType ?? receiverType

        // BUG-164: callable references must also support SAM-conversion to a
        // functional interface expected type, the same way lambda literals do.
        // Computed before candidate collection: the extension-vs-companion
        // preference below already needs the expected function shape.
        let expectedFunctionType: TypeID?
        let expectedSamInterfaceType: TypeID?
        if let expectedType {
            if case .functionType = sema.types.kind(of: expectedType) {
                expectedFunctionType = expectedType
                expectedSamInterfaceType = nil
            } else if let functionType = sema.types.nominalFunctionType(for: expectedType) {
                expectedFunctionType = sema.types.make(.functionType(functionType))
                expectedSamInterfaceType = nil
            } else if let samFT = driver.helpers.samCallableReferenceFunctionType(for: expectedType, sema: sema) {
                expectedFunctionType = sema.types.make(.functionType(samFT))
                expectedSamInterfaceType = expectedType
            } else {
                expectedFunctionType = nil
                expectedSamInterfaceType = nil
            }
        } else {
            expectedFunctionType = nil
            expectedSamInterfaceType = nil
        }

        var candidates: [SymbolID] = []
        // Resolve receiver members before the bare-property shortcut below:
        // a package `val flush` must not hide `Writer.flush` for `::flush` in
        // implicit-receiver scope. Local declarations retain lexical priority.
        let hasLocalDeclaration = locals[member] != nil
        var implicitBoundReceiver: (type: TypeID, symbol: SymbolID?)?
        var implicitPropertyCandidate: SymbolID?
        var implicitPropertyType: TypeID?
        let implicitMemberCandidates: [SymbolID] = {
            guard receiver == nil, !hasLocalDeclaration
            else { return [] }
            var receivers = ctx.implicitReceiverMemberLookupEntries()
            if let type = ctx.implicitReceiverType,
               let symbol = locals[interner.intern("this")]?.symbol,
               let index = receivers.firstIndex(where: { $0.type == type })
            {
                receivers[index].symbol = symbol
            }
            for index in receivers.indices where receivers[index].symbol == nil {
                guard let symbol = driver.helpers.nominalSymbol(
                    of: receivers[index].type,
                    types: sema.types
                ),
                let kind = sema.symbols.symbol(symbol)?.kind,
                kind == .class || kind == .enumClass
                else {
                    continue
                }
                // An outer class receiver has no local receiver parameter in
                // this context; its class symbol lets lowering follow the
                // inner-class `$outer` chain to capture the instance.
                receivers[index].symbol = symbol
            }
            var hiddenDslMarkers = Set<String>()
            for implicitReceiver in receivers {
                let markers = ctx.collectDslMarkerAnnotations(for: implicitReceiver.type)
                let isHidden = !hiddenDslMarkers.isDisjoint(with: markers)
                hiddenDslMarkers.formUnion(markers)
                if isHidden { continue }
                let nonNullImplicitReceiver = sema.types.makeNonNullable(implicitReceiver.type)
                let members = driver.helpers.collectMemberFunctionCandidates(
                    named: member,
                    receiverType: nonNullImplicitReceiver,
                    sema: sema,
                    interner: interner
                ).filter { candidate in
                    // Top-level extension aliases are indexed under their
                    // receiver's member scope, so they must remain candidates
                    // for an implicitly-bound `::name`. Member extensions
                    // still require both receivers and are not callable-reference
                    // targets.
                    !driver.helpers.declaresExtensionReceiver(
                        candidate,
                        sema: sema,
                        interner: interner
                    ) || sema.symbols.memberExtensionOwnerSymbol(for: candidate) == nil
                }
                // A bare `::ext` inside a receiver scope is a *bound* reference
                // (`with("s") { ::ext }` means `this::ext`), so package-level
                // extensions whose declared receiver accepts the implicit
                // receiver are bound `() -> R` candidates as well — kotlinc
                // resolves `with("42") { ::toInt }` to `() -> Int`.
                let implicitExtensionCandidates = ctx.cachedScopeLookup(member).filter { symbolID in
                    let owner = sema.symbols.parentSymbol(for: symbolID).flatMap { ctx.cachedSymbol($0) }
                    guard let symbol = ctx.cachedSymbol(symbolID),
                          symbol.kind == .function,
                          owner == nil || owner?.kind == .package
                              || Array(symbol.fqName.dropLast()) != owner?.fqName,
                          let signature = sema.symbols.functionSignature(for: symbolID),
                          let declaredReceiver = signature.receiverType,
                          driver.helpers.declaresExtensionReceiver(
                              symbolID,
                              sema: sema,
                              interner: interner
                          )
                    else { return false }
                    return driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                        callSiteReceiver: nonNullImplicitReceiver,
                        declaredReceiver: declaredReceiver,
                        sema: sema
                    )
                }
                // Members of the implicit receiver outrank same-named package
                // extensions, mirroring member-call resolution in Kotlin.
                let visibleMembers = ctx.filterByVisibility(members).0
                if !visibleMembers.isEmpty {
                    implicitBoundReceiver = implicitReceiver
                    return visibleMembers
                }
                let memberProperty = driver.helpers.lookupMemberProperty(
                    named: member,
                    receiverType: nonNullImplicitReceiver,
                    sema: sema
                ).flatMap { property in
                    sema.symbols.extensionPropertyReceiverType(for: property.symbol) == nil
                        ? property
                        : nil
                }
                let memberProperties = memberProperty.map { [$0.symbol] } ?? []
                let extensionProperties = ctx.cachedScopeLookup(member).filter { symbolID in
                    let ownerKind = sema.symbols.parentSymbol(for: symbolID).flatMap { ctx.cachedSymbol($0)?.kind }
                    guard ctx.cachedSymbol(symbolID)?.kind == .property,
                          let declaredReceiver = sema.symbols.extensionPropertyReceiverType(for: symbolID),
                          ownerKind == nil || ownerKind == .package
                    else { return false }
                    return driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                        callSiteReceiver: nonNullImplicitReceiver,
                        declaredReceiver: declaredReceiver,
                        sema: sema
                    )
                }
                if let property = ctx.filterByVisibility(memberProperties).0.first {
                    implicitBoundReceiver = implicitReceiver
                    implicitPropertyCandidate = property
                    implicitPropertyType = memberProperty?.type
                    return []
                }
                // Enum entry members are owned by the entry's field symbol
                // `X.B`, not by the enum class `X` itself, so receiver-type
                // member lookup above never reaches them — even though they
                // are members of the entry's implicit `this`. Reach them
                // through the lexical entry scope (it only exposes that
                // entry's own members while inside its body) when the enum
                // owner matches the implicit receiver's nominal type.
                if let (_, implicitReceiverSymbol) = resolveClassTypeSymbol(
                    nonNullImplicitReceiver, sema: sema
                ) {
                    let enumEntryMembers = ctx.cachedScopeLookup(member).filter { symbolID in
                        guard let symbol = ctx.cachedSymbol(symbolID),
                              let ownerID = sema.symbols.parentSymbol(for: symbolID),
                              let owner = ctx.cachedSymbol(ownerID),
                              sema.symbols.enumOwnerSymbol(for: owner) == implicitReceiverSymbol.id
                        else {
                            return false
                        }
                        switch symbol.kind {
                        case .function:
                            guard let declaredReceiver = sema.symbols.functionSignature(
                                for: symbolID
                            )?.receiverType else {
                                return false
                            }
                            return driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                                callSiteReceiver: nonNullImplicitReceiver,
                                declaredReceiver: declaredReceiver,
                                sema: sema
                            )
                        case .property:
                            return sema.symbols.extensionPropertyReceiverType(for: symbolID) == nil
                        default:
                            return false
                        }
                    }
                    let (enumEntryFunctions, enumEntryProperties) = enumEntryMembers.reduce(
                        into: ([SymbolID](), [SymbolID]())
                    ) { buckets, symbolID in
                        switch ctx.cachedSymbol(symbolID)?.kind {
                        case .function: buckets.0.append(symbolID)
                        case .property: buckets.1.append(symbolID)
                        default: break
                        }
                    }
                    let visibleEnumEntryMembers = ctx.filterByVisibility(enumEntryFunctions).0
                    if !visibleEnumEntryMembers.isEmpty {
                        implicitBoundReceiver = implicitReceiver
                        return visibleEnumEntryMembers
                    }
                    if let property = ctx.filterByVisibility(enumEntryProperties).0.first {
                        implicitBoundReceiver = implicitReceiver
                        implicitPropertyCandidate = property
                        implicitPropertyType = sema.symbols.propertyType(for: property)
                        return []
                    }
                }
                let visibleExtensions = ctx.filterByVisibility(implicitExtensionCandidates).0
                if !visibleExtensions.isEmpty {
                    implicitBoundReceiver = implicitReceiver
                    return visibleExtensions
                }
                if let property = ctx.filterByVisibility(extensionProperties).0.first {
                    implicitBoundReceiver = implicitReceiver
                    implicitPropertyCandidate = property
                    return []
                }
            }
            return []
        }()
        if let property = implicitPropertyCandidate, let implicitBoundReceiver {
            sema.bindings.markImplicitReceiverMember(
                id,
                name: member,
                receiverType: implicitBoundReceiver.type
            )
            if let symbol = implicitBoundReceiver.symbol {
                sema.bindings.markImplicitReceiverOuterReceiver(id, symbol: symbol)
            }
            return bindPropertyCallableRef(
                id,
                propertySymbol: property,
                ownerType: nil,
                isUnbound: false,
                expectedType: expectedType,
                range: range,
                ctx: ctx,
                sema: sema,
                interner: interner,
                resolvedPropertyType: implicitPropertyType
            )
        }
        // A constructor signature's `receiverType` field carries the class type
        // for the constructor body's own implicit `this`
        // (MemberHeaderCollection.swift), not a real extension-style receiver --
        // `callableFunctionType` must therefore treat it as already "bound" for
        // ordinary constructors (excluded from the resulting function type's
        // parameter list) the same way a bound `obj::method` reference is, or
        // `(Int) -> Foo` would gain a spurious leading `Foo` parameter. An inner
        // constructor is the exception for a type receiver: its enclosing
        // instance is the unbound first parameter. A value receiver binds that
        // enclosing instance.
        var isConstructorReference = false
        var unboundInnerConstructorReceiverType: TypeID?
        var isImplicitlyBoundMember = false
        var hasExplicitMemberCandidates = false
        var companionCallableReferenceReceiverType: TypeID?
        var propertyReferenceCandidate: (symbol: SymbolID, ownerType: TypeID?, isUnbound: Bool, type: TypeID)?
        if let effectiveReceiverType {
            let nonNullReceiver = sema.types.makeNonNullable(effectiveReceiverType)
            // `Any` is represented by a builtin TypeID, while its compiler-provided
            // `toString` member is hosted by a synthetic nominal `kotlin.Any` symbol.
            // Bridge that representation gap so `value::toString` resolves through
            // the same member target as other bound references.
            let memberLookupReceiver: TypeID
            if effectiveReceiverType == sema.types.anyType,
               member == interner.intern("toString"),
               let anyClassSymbol = sema.types.anyClassSymbol
            {
                memberLookupReceiver = sema.types.make(.classType(ClassType(
                    classSymbol: anyClassSymbol,
                    args: [],
                    nullability: .nonNull
                )))
            } else if member == interner.intern("invoke"),
                      case let .functionType(functionType) = sema.types.kind(of: nonNullReceiver),
                      !functionType.isCallableReference,
                      functionType.contextReceivers.isEmpty
            {
                let inputTypes = (functionType.receiver.map { [$0] } ?? []) + functionType.params
                let arity = inputTypes.count
                let interfaceSymbols = functionType.isSuspend
                    ? sema.types.suspendFunctionNInterfaceSymbols
                    : sema.types.functionNInterfaceSymbols
                if let interfaceSymbol = interfaceSymbols[arity] {
                    // Function types are not nominal lookup roots. Map their
                    // callable shape to the compiler-known FunctionN interface
                    // so `value::invoke` resolves the same synthetic member as
                    // an ordinary `value.invoke()` call.
                    memberLookupReceiver = sema.types.make(.classType(ClassType(
                        classSymbol: interfaceSymbol,
                        args: inputTypes.map(TypeArg.in) + [.out(functionType.returnType)],
                        nullability: .nonNull
                    )))
                } else {
                    memberLookupReceiver = nonNullReceiver
                }
            } else {
                memberLookupReceiver = nonNullReceiver
            }
            let memberCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: member,
                receiverType: memberLookupReceiver,
                sema: sema,
                includeUnattachedPackageExtensions: true,
                interner: interner
            ).filter { candidate in
                // Member-extensions are never valid callable-reference
                // targets — `C::ext`, `c::ext`, and `this::ext` are all
                // rejected by kotlinc — while package-level extensions on
                // the receiver stay legal (`String::toInt`, `s::toInt`).
                !driver.helpers.declaresExtensionReceiver(
                    candidate,
                    sema: sema,
                    interner: interner
                )
            }
            let enumCompanionValueOf = memberCandidates.isEmpty
                ? enumCompanionValueOfCallableReference(
                    named: member,
                    receiverType: nonNullReceiver,
                    isUnboundTypeReceiver: unboundClassType != nil,
                    ctx: ctx
                )
                : nil
            let companionCallableReference = memberCandidates.isEmpty
                ? (enumCompanionValueOf ?? companionMemberCallableReference(
                    named: member,
                    receiverType: nonNullReceiver,
                    isUnboundTypeReceiver: unboundClassType != nil,
                    ctx: ctx
                ))
                : nil
            let memberProperty = driver.helpers.lookupMemberProperty(
                named: member,
                receiverType: nonNullReceiver,
                sema: sema
            ) ?? {
                // `this::member` inside an enum entry body: the entry's own
                // members are owned by the entry's field symbol `X.B`, not by
                // the enum class `X`, so `lookupMemberProperty` never reaches
                // them even though `this` statically is the entry instance.
                // Reach them through the lexical entry scope — it only
                // exposes that entry's own members while inside its body.
                // Restricted to a `this` receiver: another enum-typed value
                // is not statically the same entry, so `x::entryMember` stays
                // unresolved the way kotlinc reports it.
                guard let receiver,
                      case .thisRef = ast.arena.expr(receiver),
                      let (_, receiverSymbol) = resolveClassTypeSymbol(
                          nonNullReceiver, sema: sema
                      )
                else {
                    return nil
                }
                return ctx.cachedScopeLookup(member).compactMap { symbolID -> (symbol: SymbolID, type: TypeID)? in
                    guard let symbol = ctx.cachedSymbol(symbolID),
                          symbol.kind == .property,
                          let ownerID = sema.symbols.parentSymbol(for: symbolID),
                          let owner = ctx.cachedSymbol(ownerID),
                          sema.symbols.enumOwnerSymbol(for: owner) == receiverSymbol.id,
                          sema.symbols.extensionPropertyReceiverType(for: symbolID) == nil,
                          let propertyType = sema.symbols.propertyType(for: symbolID)
                    else {
                        return nil
                    }
                    return (symbolID, propertyType)
                }.first
            }()
            let companionMemberProperty: (symbol: SymbolID, type: TypeID)? = {
                guard unboundClassType != nil,
                      let (_, ownerSymbol) = resolveClassTypeSymbol(nonNullReceiver, sema: sema)
                else {
                    return nil
                }
                let companionSymbol = sema.symbols.companionBlockObjectSymbol(
                    for: ownerSymbol.id,
                    interner: interner
                ) ?? sema.symbols.companionObjectSymbol(for: ownerSymbol.id)
                    ?? sema.symbols.actualSymbol(for: ownerSymbol.id).flatMap {
                        sema.symbols.companionBlockObjectSymbol(for: $0, interner: interner)
                            ?? sema.symbols.companionObjectSymbol(for: $0)
                    }
                guard let companionSymbol else { return nil }
                let companionType = sema.symbols.propertyType(for: companionSymbol)
                    ?? sema.types.make(.classType(ClassType(
                        classSymbol: companionSymbol,
                        args: [],
                        nullability: .nonNull
                    )))
                guard let property = driver.helpers.lookupMemberProperty(
                    named: member,
                    receiverType: companionType,
                    sema: sema
                ), sema.symbols.extensionPropertyReceiverType(for: property.symbol) == nil
                else {
                    return nil
                }
                return property
            }()
            // A same-named non-extension function in a nearer scope must
            // not hide a legal receiver extension. Filter for applicable
            // extensions during scope lookup so only matching candidates
            // participate in shadowing. Keep member candidates above as
            // the higher-priority tier.
            func isApplicableExtensionReferenceCandidate(_ symbolID: SymbolID) -> Bool {
                guard let symbol = ctx.cachedSymbol(symbolID),
                      symbol.kind == .function,
                      !(symbol.flags.contains(.expectDeclaration)
                          && sema.symbols.actualSymbol(for: symbolID) != nil),
                      sema.symbols.memberExtensionOwnerSymbol(for: symbolID) == nil,
                      driver.helpers.declaresExtensionReceiver(
                          symbolID,
                          sema: sema,
                          interner: interner
                      ),
                      let signature = sema.symbols.functionSignature(for: symbolID),
                      let declaredReceiver = signature.receiverType
                else {
                    return false
                }
                guard driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                    callSiteReceiver: nonNullReceiver,
                    declaredReceiver: declaredReceiver,
                    sema: sema
                ) else {
                    return false
                }
                return receiverSatisfiesOwnTypeParameterBounds(
                    declaredReceiver: declaredReceiver,
                    signature: signature
                )
            }
            // The receiver fallback admits any bare type-parameter receiver
            // (`fun <R : CharSequence> R.zap()`). Since #11436 an unbound
            // reference with several candidates is ambiguous instead of
            // taking the first one, so drop candidates whose own receiver
            // type parameter cannot be bound to this receiver.
            func receiverSatisfiesOwnTypeParameterBounds(
                declaredReceiver: TypeID,
                signature: FunctionSignature
            ) -> Bool {
                guard case let .typeParam(receiverParam) = sema.types.kind(
                    of: sema.types.makeNonNullable(declaredReceiver)
                ),
                    let index = signature.typeParameterSymbols.firstIndex(of: receiverParam.symbol)
                else {
                    return true
                }
                let declaredBounds = index < signature.typeParameterUpperBoundsList.count
                    ? signature.typeParameterUpperBoundsList[index] : []
                let storedBounds = sema.symbols.typeParameterUpperBounds(for: receiverParam.symbol)
                let ownParameters = signature.typeParameterSymbols
                for bound in declaredBounds + storedBounds.filter({ !declaredBounds.contains($0) }) {
                    let nonNullBound = sema.types.makeNonNullable(bound)
                    let mentionsOwnParameter = ownParameters.contains { parameter in
                        sema.types.typeContainsTypeParam(nonNullBound, symbol: parameter)
                    }
                    if !mentionsOwnParameter {
                        if !sema.types.isSubtype(nonNullReceiver, nonNullBound) { return false }
                        continue
                    }
                    // Bounds like `ClosedRange<T>` still need solving, so
                    // only compare the nominal class of the receiver.
                    if case let .classType(boundClass) = sema.types.kind(of: nonNullBound),
                       case let .classType(receiverClass) = sema.types.kind(of: nonNullReceiver),
                       !sema.types.isNominalSubtypeSymbol(receiverClass.classSymbol, of: boundClass.classSymbol)
                    {
                        return false
                    }
                }
                return true
            }
            // Local functions can be present in value-position locals even
            // when this callable-reference scope lookup cannot see them.
            // Match direct explicit-receiver calls: applicable local
            // extensions form the nearest candidate tier and shadow
            // package extensions with the same name.
            func applicableExtensionReferenceCandidates() -> [SymbolID] {
                let localExtensionCandidates = ctx.scope.lookup(member, matching: { symbolID in
                    ctx.cachedSymbol(symbolID)?.flags.contains(.localFunction) == true
                        && isApplicableExtensionReferenceCandidate(symbolID)
                })
                if !localExtensionCandidates.isEmpty {
                    return localExtensionCandidates
                }
                if let local = locals[member],
                   ctx.cachedSymbol(local.symbol)?.flags.contains(.localFunction) == true,
                   isApplicableExtensionReferenceCandidate(local.symbol)
                {
                    return [local.symbol]
                }
                return ctx.scope.lookup(member, matching: isApplicableExtensionReferenceCandidate)
            }
            if !memberCandidates.isEmpty {
                candidates = memberCandidates
                hasExplicitMemberCandidates = true
                if unboundClassType != nil,
                   let memberProperty,
                   sema.symbols.extensionPropertyReceiverType(for: memberProperty.symbol) == nil
                {
                    propertyReferenceCandidate = (
                        memberProperty.symbol,
                        nonNullReceiver,
                        true,
                        memberProperty.type
                    )
                } else if let companionMemberProperty {
                    propertyReferenceCandidate = (
                        companionMemberProperty.symbol,
                        nil,
                        false,
                        companionMemberProperty.type
                    )
                }
            } else if let companionCallableReference {
                // KUU-3674 (Kotlin 1.4 rule, exercised by JetBrains
                // referenceToCompanionMember.kt): `Type::name` prefers an
                // applicable package-level extension over a companion-object
                // member. Companion members reachable through the class name
                // rank *below* extensions — only a member declared on the
                // class itself would outrank them (handled above). The bound
                // companion shape still wins when an expected function type
                // rules every extension out: `() -> String` selects the bound
                // companion `foo`, while `(B) -> String` selects `fun B.foo()`.
                let extensionCandidates = applicableExtensionReferenceCandidates()
                let fittingExtensions: [SymbolID]
                if let expectedFunctionType {
                    let postponedReturnParameter = driver.helpers
                        .postponedCallableReferenceReturnTypeParameter(
                            expectedFunctionType,
                            inferenceParameters: ctx.callableReferenceInferenceParameters,
                            sema: sema
                        )
                    fittingExtensions = extensionCandidates.filter { candidate in
                        guard let signature = sema.symbols.functionSignature(for: candidate)
                        else {
                            return false
                        }
                        return driver.helpers.contextualCallableReferenceBinding(
                            for: signature,
                            targetSymbol: candidate,
                            bindReceiver: false,
                            unboundReceiverType: unboundClassType,
                            expectedFunctionType: expectedFunctionType,
                            postponedReturnTypeParameter: postponedReturnParameter,
                            interner: interner,
                            availableContextReceiverTypes: availableContextReceiverTypes,
                            sema: sema
                        ) != nil
                    }
                } else {
                    fittingExtensions = extensionCandidates
                }
                if !fittingExtensions.isEmpty {
                    candidates = fittingExtensions
                } else {
                    // A class-name companion reference is bound to the
                    // singleton receiver and therefore has no leading class
                    // input.
                    candidates = companionCallableReference.candidates
                    companionCallableReferenceReceiverType = companionCallableReference.receiverType
                    if let property = companionMemberProperty {
                        propertyReferenceCandidate = (
                            property.symbol,
                            nil,
                            false,
                            property.type
                        )
                    }
                }
            } else {
                // Property references use the same inheritance-aware lookup as
                // ordinary member reads (for example MutableList<Int>::size).
                if let property = memberProperty,
                   sema.symbols.extensionPropertyReceiverType(for: property.symbol) == nil
                {
                    // KUU-3683: `A::prop` where `A`'s companion inherits `A`
                    // also carries a bound `KProperty0` interpretation on the
                    // companion singleton. Prefer it only when the unbound
                    // `KProperty1<A, V>` shape cannot satisfy the expected
                    // type (for example `call(A::instanceProp)` for a
                    // `() -> Boolean` parameter).
                    if let unboundClassType,
                       let expectedType,
                       let companionType = classNameCompanionCallableReferenceReceiverType(
                           for: unboundClassType, ctx: ctx
                       ),
                       sema.types.isSubtype(companionType, unboundClassType)
                    {
                        let isMutable = isPropertySetterAccessible(property.symbol, ctx: ctx)
                        let unboundShape = kPropertyReferenceType(
                            ownerType: nonNullReceiver,
                            valueType: property.type,
                            isMutable: isMutable,
                            sema: sema,
                            interner: interner
                        )
                        let boundShape = kPropertyReferenceType(
                            ownerType: nil,
                            valueType: property.type,
                            isMutable: isMutable,
                            sema: sema,
                            interner: interner
                        )
                        if let boundShape,
                           sema.types.isSubtype(boundShape, expectedType),
                           unboundShape.map({ !sema.types.isSubtype($0, expectedType) }) ?? true
                        {
                            return bindPropertyCallableRef(
                                id,
                                propertySymbol: property.symbol,
                                ownerType: nil,
                                isUnbound: false,
                                expectedType: expectedType,
                                range: range,
                                ctx: ctx,
                                sema: sema,
                                interner: interner,
                                resolvedPropertyType: property.type
                            )
                        }
                    }
                    // `lookupMemberProperty` has already substituted the
                    // receiver's arguments into the property type. Keep that
                    // specialized value type even for a bound reference, whose
                    // `ownerType` remains nil to preserve KProperty0 arity.
                    return bindPropertyCallableRef(
                        id,
                        propertySymbol: property.symbol,
                        ownerType: unboundClassType != nil ? nonNullReceiver : nil,
                        isUnbound: unboundClassType != nil,
                        expectedType: expectedType,
                        range: range,
                        ctx: ctx,
                        sema: sema,
                        interner: interner,
                        resolvedPropertyType: property.type
                    )
                }
                // A property declared on a companion belongs to the singleton,
                // so `Type::property` keeps the zero-receiver KProperty0 shape.
                if let property = companionMemberProperty {
                    return bindPropertyCallableRef(
                        id,
                        propertySymbol: property.symbol,
                        ownerType: nil,
                        isUnbound: false,
                        expectedType: expectedType,
                        range: range,
                        ctx: ctx,
                        sema: sema,
                        interner: interner,
                        resolvedPropertyType: property.type
                    )
                }
                // REFL-EXTPROP: a package-level extension property (e.g. `val
                // String.length: Int` in Stdlib/kotlin/String.kt) is registered
                // under its *declaring package's* FQ name, not under its
                // receiver class's FQ name the way an extension *function*
                // gets an alias for (HeaderCollection.swift's `.propertyDecl`
                // branch never creates the member-FQ alias its `.funDecl`
                // sibling does at KSP-443) -- so the FQ-based lookup above
                // never finds `String::length`. Match it the same way
                // `resolveExtensionPropertyGetter` resolves a plain
                // `receiver.length` read: scan scope-visible `.property`
                // symbols for one whose recorded extension receiver type
                // accepts the actual receiver type, including nullability.
                if candidates.isEmpty, unboundClassType != nil {
                    let companionExtensions = companionExtensionCallableReferenceCandidates(
                        named: member,
                        receiverType: nonNullReceiver,
                        ctx: ctx
                    )
                    if !companionExtensions.isEmpty {
                        candidates = companionExtensions
                        companionCallableReferenceReceiverType = nonNullReceiver
                    }
                }
                if candidates.isEmpty {
                    let extensionPropertyCandidates = ctx.cachedScopeLookup(member).filter { symbolID in
                        guard let symbol = ctx.cachedSymbol(symbolID),
                              symbol.kind == .property,
                              let declaredReceiver = sema.symbols.extensionPropertyReceiverType(for: symbolID),
                              !isCompanionExtension(symbolID, ctx: ctx)
                        else {
                            return false
                        }
                        return driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                            callSiteReceiver: effectiveReceiverType,
                            declaredReceiver: declaredReceiver,
                            sema: sema
                        )
                    }
                    let companionExtensionProperty = unboundClassType == nil ? nil : ctx.cachedScopeLookup(member).first { symbolID in
                        guard let symbol = ctx.cachedSymbol(symbolID),
                              symbol.kind == .property,
                              isCompanionExtension(symbolID, ctx: ctx),
                              let declaredReceiver = sema.symbols.extensionPropertyReceiverType(for: symbolID)
                        else {
                            return false
                        }
                        return driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                            callSiteReceiver: effectiveReceiverType,
                            declaredReceiver: declaredReceiver,
                            sema: sema
                        )
                    }
                    if let companionExtensionProperty,
                       let propertyType = sema.symbols.propertyType(for: companionExtensionProperty),
                       let resolution = resolveExtensionPropertyReferenceType(
                           companionExtensionProperty,
                           receiverType: nonNullReceiver,
                           fallbackPropertyType: propertyType,
                           sema: sema,
                           interner: interner
                       )
                    {
                        let resultType = bindPropertyCallableRef(
                            id,
                            propertySymbol: companionExtensionProperty,
                            ownerType: nil,
                            isUnbound: false,
                            expectedType: expectedType,
                            range: range,
                            ctx: ctx,
                            sema: sema,
                            interner: interner,
                            resolvedPropertyType: resolution.valueType
                        )
                        if let specialization = resolution.specialization,
                           let getter = sema.symbols.extensionPropertyGetterAccessor(for: companionExtensionProperty)
                        {
                            bindCallableReferenceBinding(
                                id, target: getter, specialization: specialization,
                                range: range, ctx: ctx
                            )
                        }
                        return resultType
                    }
                    var extensionPropertyReference: (
                        symbol: SymbolID,
                        valueType: TypeID,
                        specialization: ContextualCallableReferenceBinding?
                    )?
                    for propertySymbol in extensionPropertyCandidates {
                        guard let propertyType = sema.symbols.propertyType(for: propertySymbol) else {
                            continue
                        }
                        if unboundClassType != nil {
                            guard let resolution = resolveExtensionPropertyReferenceType(
                                propertySymbol,
                                receiverType: effectiveReceiverType,
                                fallbackPropertyType: propertyType,
                                sema: sema,
                                interner: interner
                            ) else {
                                continue
                            }
                            extensionPropertyReference = (
                                propertySymbol, resolution.valueType, resolution.specialization
                            )
                        } else {
                            extensionPropertyReference = (propertySymbol, propertyType, nil)
                        }
                        break
                    }
                    if let extensionPropertyReference {
                        if let getter = sema.symbols.extensionPropertyGetterAccessor(
                            for: extensionPropertyReference.symbol
                        ), let signature = sema.symbols.functionSignature(for: getter),
                           !signature.contextParameterTypes.isEmpty || !signature.contextReceiverTypes.isEmpty
                        {
                            ctx.sema.diagnostics.error(
                                "KSWIFTK-SEMA-0105",
                                "Callable references to properties with context parameters are unsupported.",
                                range: range
                            )
                            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                        }
                        // KUU-3683: `A::extProp` where `A`'s companion
                        // inherits `A` also has a bound `KProperty0`
                        // interpretation on that singleton. Prefer it only
                        // when the unbound `KProperty1<A, V>` shape cannot
                        // satisfy the expected type.
                        if let unboundClassType,
                           let expectedType,
                           let companionType = classNameCompanionCallableReferenceReceiverType(
                               for: unboundClassType, ctx: ctx
                           ),
                           sema.types.isSubtype(companionType, unboundClassType),
                           let propertyType = sema.symbols.propertyType(
                               for: extensionPropertyReference.symbol
                           )
                        {
                            let boundResolution = resolveExtensionPropertyReferenceType(
                                extensionPropertyReference.symbol,
                                receiverType: companionType,
                                fallbackPropertyType: propertyType,
                                sema: sema,
                                interner: interner
                            )
                            let boundValueType = boundResolution?.valueType ?? propertyType
                            let isMutable = isPropertySetterAccessible(
                                extensionPropertyReference.symbol, ctx: ctx
                            )
                            let unboundShape = kPropertyReferenceType(
                                ownerType: effectiveReceiverType,
                                valueType: extensionPropertyReference.valueType,
                                isMutable: isMutable,
                                sema: sema,
                                interner: interner
                            )
                            let boundShape = kPropertyReferenceType(
                                ownerType: nil,
                                valueType: boundValueType,
                                isMutable: isMutable,
                                sema: sema,
                                interner: interner
                            )
                            if let boundShape,
                               sema.types.isSubtype(boundShape, expectedType),
                               unboundShape.map({ !sema.types.isSubtype($0, expectedType) }) ?? true
                            {
                                let resultType = bindPropertyCallableRef(
                                    id,
                                    propertySymbol: extensionPropertyReference.symbol,
                                    ownerType: nil,
                                    isUnbound: false,
                                    expectedType: expectedType,
                                    range: range,
                                    ctx: ctx,
                                    sema: sema,
                                    interner: interner,
                                    resolvedPropertyType: boundValueType
                                )
                                if let specialization = boundResolution?.specialization,
                                   let getter = sema.symbols.extensionPropertyGetterAccessor(
                                       for: extensionPropertyReference.symbol
                                   ) {
                                    bindCallableReferenceBinding(
                                        id, target: getter, specialization: specialization,
                                        range: range, ctx: ctx
                                    )
                                }
                                return resultType
                            }
                        }
                        let resultType = bindPropertyCallableRef(
                            id,
                            propertySymbol: extensionPropertyReference.symbol,
                            ownerType: unboundClassType != nil ? effectiveReceiverType : nil,
                            isUnbound: unboundClassType != nil,
                            expectedType: expectedType,
                            range: range,
                            ctx: ctx,
                            sema: sema,
                            interner: interner,
                            resolvedPropertyType: extensionPropertyReference.valueType
                        )
                        if let specialization = extensionPropertyReference.specialization,
                           let getter = sema.symbols.extensionPropertyGetterAccessor(
                               for: extensionPropertyReference.symbol
                           ) {
                            bindCallableReferenceBinding(
                                id, target: getter, specialization: specialization,
                                range: range, ctx: ctx
                            )
                        }
                        return resultType
                    }
                    // KUU-3683: an extension property declared on
                    // `A.Companion` (for example
                    // `val A.Companion.companionExtProp`) is only reachable
                    // through the bound interpretation of `A::prop` — its
                    // declared receiver never accepts `A` itself, so the
                    // unbound lookup above cannot see it. Collect it against
                    // the companion type instead; the reference is bound
                    // `KProperty0` unconditionally (there is no unbound
                    // shape for it to compete with).
                    if let unboundClassType,
                       let companionType = classNameCompanionCallableReferenceReceiverType(
                           for: unboundClassType, ctx: ctx
                       )
                    {
                        let boundExtensionProperties = ctx.cachedScopeLookup(member).filter { symbolID in
                            guard let symbol = ctx.cachedSymbol(symbolID),
                                  symbol.kind == .property,
                                  let declaredReceiver = sema.symbols.extensionPropertyReceiverType(
                                      for: symbolID
                                  ),
                                  !isCompanionExtension(symbolID, ctx: ctx)
                            else {
                                return false
                            }
                            return driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                                callSiteReceiver: companionType,
                                declaredReceiver: declaredReceiver,
                                sema: sema
                            )
                        }
                        for boundProperty in boundExtensionProperties {
                            guard let propertyType = sema.symbols.propertyType(for: boundProperty)
                            else {
                                continue
                            }
                            let boundResolution = resolveExtensionPropertyReferenceType(
                                boundProperty,
                                receiverType: companionType,
                                fallbackPropertyType: propertyType,
                                sema: sema,
                                interner: interner
                            )
                            let boundValueType = boundResolution?.valueType ?? propertyType
                            let boundShape = kPropertyReferenceType(
                                ownerType: nil,
                                valueType: boundValueType,
                                isMutable: isPropertySetterAccessible(boundProperty, ctx: ctx),
                                sema: sema,
                                interner: interner
                            ) ?? boundValueType
                            // Bound is the only interpretation this
                            // candidate has, so it resolves unconditionally;
                            // an expected type still has to accept it.
                            if let expectedType,
                               !sema.types.isSubtype(boundShape, expectedType)
                            {
                                continue
                            }
                            let resultType = bindPropertyCallableRef(
                                id,
                                propertySymbol: boundProperty,
                                ownerType: nil,
                                isUnbound: false,
                                expectedType: expectedType,
                                range: range,
                                ctx: ctx,
                                sema: sema,
                                interner: interner,
                                resolvedPropertyType: boundValueType
                            )
                            if let specialization = boundResolution?.specialization,
                               let getter = sema.symbols.extensionPropertyGetterAccessor(
                                   for: boundProperty
                               ) {
                                bindCallableReferenceBinding(
                                    id, target: getter, specialization: specialization,
                                    range: range, ctx: ctx
                                )
                            }
                            return resultType
                        }
                    }

                }
                // Members and companion members above keep their higher
                // priority tiers; this receiver-extension lookup is the
                // last fallback before constructor references.
                candidates = applicableExtensionReferenceCandidates()
                // `Outer::Nested` where `Nested` is a nested (non-inner) class
                // is a constructor reference `(Args...) -> Outer.Nested`. It
                // has no receiver parameter, so it is folded into the bound
                // side like the bare `::Foo` form. `inner` classes are left
                // out: their reference takes the outer instance as a
                // leading parameter, which this path does not model.
                if candidates.isEmpty,
                   unboundClassType != nil,
                   let (_, owner) = resolveClassTypeSymbol(nonNullReceiver, sema: sema)
                {
                    let nestedClasses = sema.symbols.lookupAll(fqName: owner.fqName + [member])
                    let nestedClass = nestedClasses
                        .compactMap { ctx.cachedSymbol($0) }
                        .first { ($0.kind == .class || $0.kind == .enumClass) && !$0.flags.contains(.innerClass) }
                    if let nestedClass,
                       let ctorCandidates = visibleConstructorCandidates(of: nestedClass, ctx: ctx)
                    {
                        candidates = ctorCandidates
                        isConstructorReference = true
                    }
                    if candidates.isEmpty,
                       let innerClass = nestedClasses
                           .compactMap({ ctx.cachedSymbol($0) })
                           .first(where: { $0.kind == .class && $0.flags.contains(.innerClass) }),
                       !ctx.filterByVisibility([innerClass.id]).0.isEmpty,
                       let ctorCandidates = visibleConstructorCandidates(of: innerClass, ctx: ctx)
                    {
                        candidates = ctorCandidates
                        isConstructorReference = true
                        unboundInnerConstructorReceiverType = nonNullReceiver
                    }
                }
                if candidates.isEmpty, unboundClassType == nil {
                    let innerConstructors = driver.helpers.collectInnerClassConstructorCandidates(
                        named: member,
                        receiverType: nonNullReceiver,
                        sema: sema,
                        interner: interner
                    )
                    let visibleInnerConstructors = ctx.filterByVisibility(innerConstructors).0.filter { constructor in
                        guard let innerClassID = sema.symbols.parentSymbol(for: constructor),
                              let innerClass = ctx.cachedSymbol(innerClassID),
                              innerClass.kind == .class,
                              innerClass.flags.contains(.innerClass),
                              !innerClass.flags.contains(.abstractType)
                        else {
                            return false
                        }
                        return !ctx.filterByVisibility([innerClassID]).0.isEmpty
                    }
                    if !visibleInnerConstructors.isEmpty {
                        candidates = visibleInnerConstructors
                        isConstructorReference = true
                    }
                }
            }
        } else {
            let propertyCandidates = ctx.cachedScopeLookup(member).filter { symbolID in
                guard let symbol = ctx.cachedSymbol(symbolID) else {
                    return false
                }
                // A bare `::name` cannot reference an extension property —
                // kotlinc reports `unresolved reference`; only `Type::prop`
                // and `obj::prop` reach extension properties.
                return symbol.kind == .property
                    && sema.symbols.extensionPropertyReceiverType(for: symbolID) == nil
            }
            let packagePropertyShadowedByMember = propertyCandidates.first.map { propertySymbol in
                let ownerKind = sema.symbols.parentSymbol(for: propertySymbol)
                    .flatMap { sema.symbols.symbol($0)?.kind }
                return !implicitMemberCandidates.isEmpty && (ownerKind == .package || ownerKind == nil)
            } ?? false
            if let propertySymbol = propertyCandidates.first, !packagePropertyShadowedByMember {
                let propertyType = sema.symbols.propertyType(for: propertySymbol) ?? sema.types.errorType
                let isMutable = isPropertySetterAccessible(propertySymbol, ctx: ctx)
                // KSP-496/KSP-505: a bare `::member` reference to a member
                // property of the enclosing class or singleton is implicitly
                // bound to `this`. For `.class` owners the receiver is a
                // genuine instance captured by KIR lowering
                // (LambdaLowerer.isCaptureEligibleInstanceContainerSymbol).
                // For `.object` owners (companion objects, plain `object`s)
                // there is exactly one instance ever, stored in a
                // module-level global slot rather than a captured
                // per-instance field — so KIR lowering (see
                // LambdaLowerer+PropertyReferenceLowering.swift's
                // `ensurePropertyReferenceAccessor`) reads/writes that slot
                // directly and never needs a captured receiver at all.
                //
                // `.enumClass` stays excluded (kept on the pre-existing, safe
                // fallback), even though an *enum entry* is also a singleton:
                // a property declared directly in the enum class's own body
                // (e.g. a constructor-promoted `val`) is a genuine per-entry
                // *instance* field — each entry has its own value — not
                // shared global storage the way `.object` is. Confirmed by
                // testing: treating `.enumClass` the same as `.object` here
                // made `enum class E(val v: Int) { A(1), B(2) }`'s `::v`
                // read back `0` for every entry instead of each entry's own
                // value. A property declared inside one specific *entry's*
                // own body (`A { val x = 5 }`) might be a distinct, safely
                // includable case — its owner could plausibly be that
                // entry's own synthesized subclass rather than `.enumClass`
                // itself — but this could not be verified: referencing an
                // entry with a body at all (`EnumClass.ENTRY`) hits a
                // separate, pre-existing, unrelated bug (see
                // the `enum_edge_cases.kt` entry).
                // `.interface` stays excluded here too: interface-owned
                // properties have no storage of their own (always dispatched
                // through whichever class implements them), which this
                // bare-reference path does not handle yet.
                let ownerKind = sema.symbols.parentSymbol(for: propertySymbol)
                    .flatMap { sema.symbols.symbol($0)?.kind }
                let resultType: TypeID
                if let ownerKind, ownerKind != .class, ownerKind != .object {
                    resultType = propertyType
                } else {
                    let inferredType = kPropertyReferenceType(
                        ownerType: nil,
                        valueType: propertyType,
                        isMutable: isMutable,
                        sema: sema,
                        interner: interner
                    ) ?? propertyType
                    resultType = resolvedPropertyReferenceResultType(
                        expectedType: expectedType,
                        inferredType: inferredType,
                        sema: sema,
                        interner: interner
                    )
                }
                sema.bindings.bindIdentifier(id, symbol: propertySymbol)
                sema.bindings.bindCallableRefKind(id, kind: .propertyRef)
                markPropertyReferenceSamConversionIfNeeded(
                    id,
                    expectedType: expectedType,
                    resultType: resultType,
                    sema: sema
                )
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            }
            let localFunctionCandidates = ctx.scope.lookup(member, matching: { symbolID in
                guard let symbol = ctx.cachedSymbol(symbolID),
                      symbol.flags.contains(.localFunction),
                      symbol.kind == .function,
                      let signature = sema.symbols.functionSignature(for: symbolID)
                else {
                    return false
                }
                let isAnonymous = sema.symbols.isAnonymousFunction(symbolID, interner: interner)
                return signature.receiverType == nil || isAnonymous
            })
            candidates = localFunctionCandidates.isEmpty
                ? ctx.cachedScopeLookup(member).filter { symbolID in
                    guard let symbol = ctx.cachedSymbol(symbolID) else {
                        return false
                    }
                    // A bare `::name` cannot reference an extension function —
                    // kotlinc reports `unresolved reference`; only `Type::ext`,
                    // `obj::ext`, and the implicit-receiver bound form (handled
                    // via `implicitMemberCandidates`) reach extensions.
                    return symbol.kind == .constructor
                        || (symbol.kind == .function
                            && !driver.helpers.declaresExtensionReceiver(
                                symbolID,
                                sema: sema,
                                interner: interner
                            ))
                }
                : localFunctionCandidates
            if candidates.isEmpty,
               let local = locals[member],
               let localSymbol = ctx.cachedSymbol(local.symbol),
               localSymbol.kind == .function,
               (sema.symbols.functionSignature(for: local.symbol)?.receiverType == nil
                   || sema.symbols.isAnonymousFunction(local.symbol, interner: interner))
            {
                candidates = [local.symbol]
            }
            // A bare inner-class constructor reference inside an enclosing
            // instance captures that receiver, just like `outer::Inner`.
            if candidates.isEmpty {
                var implicitReceivers = ctx.implicitReceiverMemberLookupEntries()
                if let type = ctx.implicitReceiverType,
                   let symbol = locals[interner.intern("this")]?.symbol,
                   let index = implicitReceivers.firstIndex(where: { $0.type == type })
                {
                    implicitReceivers[index].symbol = symbol
                }
                for implicitReceiver in implicitReceivers.reversed() {
                    let innerConstructors = driver.helpers.collectInnerClassConstructorCandidates(
                        named: member,
                        receiverType: implicitReceiver.type,
                        sema: sema,
                        interner: interner
                    )
                    let visibleConstructors = ctx.filterByVisibility(innerConstructors).0.filter { constructor in
                        guard let innerClassID = sema.symbols.parentSymbol(for: constructor),
                              let innerClass = ctx.cachedSymbol(innerClassID),
                              innerClass.kind == .class,
                              innerClass.flags.contains(.innerClass),
                              !innerClass.flags.contains(.abstractType)
                        else {
                            return false
                        }
                        return !ctx.filterByVisibility([innerClassID]).0.isEmpty
                    }
                    guard !visibleConstructors.isEmpty else { continue }
                    candidates = visibleConstructors
                    isConstructorReference = true
                    isImplicitlyBoundMember = true
                    implicitBoundReceiver = implicitReceiver
                    break
                }
            }
            // REFL-CTOR: a bare `::Foo` where `Foo` names a class/enum class
            // is a constructor reference `(Args...) -> Foo`. Constructors are
            // stored under the class's own FQ name with the reserved `<init>`
            // short name (HeaderHelpers.swift), not under `Foo` itself, so the
            // `.function || .constructor` scope lookup above never finds them
            // -- mirrors the KSP-CAP-006 class+ctor lookup CallTypeChecker.swift
            // uses for a direct call `Foo(...)`.
            // Fun interfaces take a separate synthetic SAM-factory path because
            // they have no declared constructor symbol.
            if candidates.isEmpty {
                let classCandidates = ctx.cachedScopeLookup(member).filter { symbolID in
                    guard let symbol = ctx.cachedSymbol(symbolID) else { return false }
                    return symbol.kind == .class || symbol.kind == .enumClass || symbol.kind == .interface
                }
                if let classSym = classCandidates.first,
                   let classSymbol = ctx.cachedSymbol(classSym)
                {
                    if classSymbol.kind == .interface, classSymbol.flags.contains(.funInterface) {
                        if let type = inferFunInterfaceConstructorCallableReference(
                            id, interfaceSymbol: classSym, expectedType: expectedType, range: range, ctx: ctx
                        ) {
                            return type
                        }
                    } else if let ctorCandidates = visibleConstructorCandidates(of: classSymbol, ctx: ctx) {
                        candidates = ctorCandidates
                        isConstructorReference = true
                    }
                }
            }
            // A bare `::Alias` resolves to the expanded classifier's
            // constructors — the same constructor reference `::Class`
            // produces (KUU-3840). Inner-class expansions keep their
            // implicit-receiver paths below.
            if candidates.isEmpty {
                for aliasID in ctx.cachedScopeLookup(member) {
                    guard let aliasSymbol = ctx.cachedSymbol(aliasID),
                          aliasSymbol.kind == .typeAlias
                    else { continue }
                    let aliasTypeArgs: [TypeArg] = sema.symbols
                        .typeAliasTypeParameters(for: aliasID)
                        .map {
                            .invariant(sema.types.make(.typeParam(TypeParamType(
                                symbol: $0, nullability: .nonNull
                            ))))
                        }
                    guard let expanded = driver.helpers.expandTypeAlias(
                        aliasID,
                        typeArgs: aliasTypeArgs,
                        sema: sema,
                        visited: [],
                        depth: 0,
                        diagnostics: sema.diagnostics
                    ), case let .classType(classType) = sema.types.kind(of: expanded)
                    else { continue }
                    let ownerID = sema.symbols.actualSymbol(for: classType.classSymbol)
                        ?? classType.classSymbol
                    guard let ownerSymbol = ctx.cachedSymbol(ownerID),
                          !ownerSymbol.flags.contains(.innerClass)
                    else { continue }
                    if ownerSymbol.kind == .interface, ownerSymbol.flags.contains(.funInterface) {
                        if let type = inferFunInterfaceConstructorCallableReference(
                            id, interfaceSymbol: ownerID, expectedType: expectedType, range: range, ctx: ctx
                        ) {
                            return type
                        }
                    } else if let ctorCandidates = visibleConstructorCandidates(of: ownerSymbol, ctx: ctx) {
                        candidates = ctorCandidates
                        isConstructorReference = true
                        break
                    }
                }
            }
        }

        // A bare `::Alias` inside an enclosing class is bound to that class's
        // instance when the alias names one of its inner classes.
        if candidates.isEmpty, receiver == nil {
            var implicitReceivers = ctx.implicitReceiverStack
            if let type = ctx.implicitReceiverType,
               let symbol = locals[interner.intern("this")]?.symbol,
               implicitReceivers.last?.symbol != symbol
            {
                implicitReceivers.append((type, symbol))
            }
            for implicitReceiver in implicitReceivers.reversed() {
                guard let aliasedInner = driver.helpers.collectInnerClassTypeAliasConstructorCandidates(
                    named: member,
                    receiverType: implicitReceiver.type,
                    explicitTypeArgs: [],
                    ctx: ctx,
                    interner: interner
                ) else {
                    continue
                }
                candidates = ctx.filterByVisibility(aliasedInner.candidates).visible
                if !candidates.isEmpty {
                    isConstructorReference = true
                    isImplicitlyBoundMember = true
                    implicitBoundReceiver = implicitReceiver
                    break
                }
            }
        }

        // Within a class or extension body, `::member` uses the active
        // implicit receiver before a same-named package function. Lexical
        // scope lookup does not walk inherited member scopes. A local
        // function still shadows the receiver's member.
        if !implicitMemberCandidates.isEmpty {
            candidates = implicitMemberCandidates
            isImplicitlyBoundMember = true
            isConstructorReference = candidates.allSatisfy { candidate in
                guard sema.symbols.symbol(candidate)?.kind == .constructor,
                      let owner = sema.symbols.parentSymbol(for: candidate)
                else {
                    return false
                }
                return sema.symbols.symbol(owner)?.flags.contains(.innerClass) == true
            }
        }

        // A nested class constructor (`Outer::Nested`) is stored under
        // `Outer.Nested.<init>`, just as bare `::Nested` is under
        // `Nested.<init>`. Ordinary member lookup by the short name misses it.
        // Only a type receiver may introduce this fallback.
        if candidates.isEmpty,
           let unboundClassType,
           let (_, owner) = resolveClassTypeSymbol(unboundClassType, sema: sema)
        {
            let nestedClasses = sema.symbols.lookupAll(fqName: owner.fqName + [member])
            for nestedID in nestedClasses {
                let (visibleNested, _) = ctx.filterByVisibility([nestedID])
                guard let nested = ctx.cachedSymbol(nestedID),
                      (nested.kind == .class || nested.kind == .enumClass),
                      !nested.flags.contains(.abstractType),
                      !nested.flags.contains(.innerClass),
                      !visibleNested.isEmpty
                else { continue }
                let constructors = sema.symbols.lookupAll(
                    fqName: nested.fqName + [interner.intern("<init>")]
                )
                let (visible, _) = ctx.filterByVisibility(constructors)
                if !visible.isEmpty {
                    candidates = visible
                    isConstructorReference = true
                    break
                }
            }
            if candidates.isEmpty {
                for nestedID in nestedClasses {
                    let (visibleNested, _) = ctx.filterByVisibility([nestedID])
                    guard let nested = ctx.cachedSymbol(nestedID),
                          nested.kind == .class,
                          nested.flags.contains(.innerClass),
                          !nested.flags.contains(.abstractType),
                          !visibleNested.isEmpty
                    else { continue }
                    let constructors = sema.symbols.lookupAll(
                        fqName: nested.fqName + [interner.intern("<init>")]
                    )
                    let (visible, _) = ctx.filterByVisibility(constructors)
                    if !visible.isEmpty {
                        candidates = visible
                        isConstructorReference = true
                        unboundInnerConstructorReceiverType = unboundClassType
                        break
                    }
                }
            }
            if candidates.isEmpty,
               let aliasedInner = driver.helpers.collectInnerClassTypeAliasConstructorCandidates(
                   named: member,
                   receiverType: unboundClassType,
                   explicitTypeArgs: [],
                   ctx: ctx,
                   interner: interner
               )
            {
                candidates = ctx.filterByVisibility(aliasedInner.candidates).visible
                if !candidates.isEmpty {
                    isConstructorReference = true
                    unboundInnerConstructorReceiverType = unboundClassType
                }
            }
        }

        // A function imported through an object is implicitly bound to that
        // singleton, just like an unqualified call to the imported member.
        // Keep this candidate-specific import behavior out of implicit-receiver
        // lookup, which already selected its own receiver above.
        var importedObjectCallableReferenceReceiver: (symbol: SymbolID, type: TypeID)?
        if receiver == nil, !isImplicitlyBoundMember, !candidates.isEmpty {
            let importedObjectReceivers = driver.callChecker.importedObjectDispatchReceiverOwners(
                named: member,
                candidates: candidates,
                ctx: ctx
            )
            let receiverSymbols = Set(candidates.compactMap { importedObjectReceivers[$0] })
            if importedObjectReceivers.count == candidates.count,
               receiverSymbols.count == 1,
               let objectSymbol = receiverSymbols.first
            {
                importedObjectCallableReferenceReceiver = (
                    objectSymbol,
                    sema.types.make(.classType(ClassType(
                        classSymbol: objectSymbol,
                        args: [],
                        nullability: .nonNull
                    )))
                )
            }
        }

        // For unbound type references (Type::member), the receiver is not
        // bound — it becomes a parameter of the function type. For bound
        // references (obj::member), the receiver is captured. Ordinary
        // constructor references have no receiver parameter; inner
        // constructors use their enclosing instance as that parameter.
        // `var`: the companion-inherits-owner retry below can still turn an
        // unresolved unbound reference into a bound `A.Companion` one.
        var isBoundReceiver = (receiver != nil
            && (unboundClassType == nil || companionCallableReferenceReceiverType != nil))
            || (isConstructorReference && unboundInnerConstructorReceiverType == nil)
            || importedObjectCallableReferenceReceiver != nil
            || isImplicitlyBoundMember
        var unboundCallableReceiverType: TypeID?
        if let unboundInnerConstructorReceiverType {
            unboundCallableReceiverType = unboundInnerConstructorReceiverType
        } else if !isBoundReceiver, !isConstructorReference {
            // Keep the explicit type arguments from `Owner<Args>::member`.
            // The owner type is the function value's first parameter, and its
            // type arguments also specialize the member's remaining parameters
            // and return type.
            unboundCallableReceiverType = unboundClassType
        } else {
            unboundCallableReceiverType = nil
        }

        let expectedCallableReferenceReturnType = expectedType.flatMap {
            driver.helpers.reflectiveCallableReferenceReturnType(from: $0, sema: sema)
        }

        let propertyReferenceCandidateType: TypeID? = if let candidate = propertyReferenceCandidate {
            kPropertyReferenceType(
                ownerType: candidate.ownerType,
                valueType: candidate.type,
                isMutable: isPropertySetterAccessible(candidate.symbol, ctx: ctx),
                sema: sema,
                interner: interner
            )
        } else {
            nil
        }
        if let candidate = propertyReferenceCandidate,
           let expectedType,
           isConcreteKPropertyReferenceShape(expectedType, sema: sema, interner: interner),
           let propertyReferenceType = propertyReferenceCandidateType,
           sema.types.isSubtype(propertyReferenceType, expectedType)
        {
            return bindPropertyCallableRef(
                id,
                propertySymbol: candidate.symbol,
                ownerType: candidate.ownerType,
                isUnbound: candidate.isUnbound,
                expectedType: expectedType,
                range: range,
                ctx: ctx,
                sema: sema,
                interner: interner,
                resolvedPropertyType: candidate.type
            )
        }
        if let candidate = propertyReferenceCandidate,
           let expectedFunctionType,
           !sema.types.typeContainsAnyTypeParam(expectedFunctionType),
           let propertyReferenceType = propertyReferenceCandidateType,
           sema.types.isSubtype(propertyReferenceType, expectedFunctionType),
           !candidates.contains(where: { driver.inferredReturnFunctions[$0] != nil })
        {
            let functionCandidateMatches = candidates.contains { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate) else { return false }
                return driver.helpers.contextualCallableReferenceBinding(
                    for: signature,
                    bindReceiver: false,
                    expectedFunctionType: expectedFunctionType,
                    interner: interner,
                    availableContextReceiverTypes: availableContextReceiverTypes,
                    sema: sema
                ) != nil
            }
            if !functionCandidateMatches {
                return bindPropertyCallableRef(
                    id,
                    propertySymbol: candidate.symbol,
                    ownerType: candidate.ownerType,
                    isUnbound: candidate.isUnbound,
                    expectedType: expectedType,
                    range: range,
                    ctx: ctx,
                    sema: sema,
                    interner: interner,
                    resolvedPropertyType: candidate.type
                )
            }
        }

        // `Type::toString` as a `(Type) -> String` value: the zero-argument
        // `toString()` has no member symbol (only the `toString(radix)`
        // overload is declared), so every candidate is an arity mismatch.
        // kotlinc picks the overload matching the expected function type;
        // synthesize the missing one.
        if let unboundClassType,
           interner.resolve(member) == "toString",
           let expectedFunctionType,
           case let .functionType(expectedFT) = sema.types.kind(of: expectedFunctionType),
           expectedFT.params.count == 1,
           !candidates.contains(where: { candidate in
               guard let signature = sema.symbols.functionSignature(for: candidate) else { return false }
               return signature.parameterTypes.count == 0 && signature.receiverType != nil
           })
        {
            let receiverParam = sema.types.makeNonNullable(unboundClassType)
            let inferredType = sema.types.make(.functionType(FunctionType(
                params: [receiverParam],
                returnType: sema.types.stringType,
                isSuspend: false,
                isCallableReference: true,
                nullability: .nonNull
            )))
            let resultType: TypeID
            if sema.types.typeContainsAnyTypeParam(expectedType ?? expectedFunctionType) {
                resultType = inferredType
            } else {
                driver.emitSubtypeConstraint(
                    left: inferredType,
                    right: expectedFunctionType,
                    range: range,
                    solver: ConstraintSolver(),
                    sema: sema,
                    diagnostics: ctx.sema.diagnostics
                )
                resultType = expectedSamInterfaceType ?? expectedFunctionType
            }
            sema.bindings.bindAnyToStringCallableRef(id)
            sema.bindings.bindCallableRefKind(id, kind: .functionRef)
            sema.bindings.markUnboundCallableRef(id)
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }

        // Concrete value and type receivers specialize the owner's type parameters.
        var boundReceiverType: TypeID? = if isImplicitlyBoundMember {
            implicitBoundReceiver?.type
        } else if let importedObjectCallableReferenceReceiver {
            importedObjectCallableReferenceReceiver.type
        } else if let companionCallableReferenceReceiverType {
            companionCallableReferenceReceiverType
        } else if receiver != nil && !isConstructorReference {
            effectiveReceiverType
        } else {
            nil
        }
        if isBoundReceiver,
           let candidateReceiverType = boundReceiverType,
           let expectedFunctionType,
           let session = ctx.builderInference,
           !session.isFinalized,
           session.mentionsVariable(candidateReceiverType, types: sema.types),
           !session.mentionsVariable(expectedFunctionType, types: sema.types),
           candidates.count == 1,
           let candidate = candidates.first,
           let signature = sema.symbols.functionSignature(for: candidate),
           signature.typeParameterSymbols.count == signature.classTypeParameterCount,
           let resolvedReceiverType = inferBuilderBoundCallableReferenceReceiverType(
               signature: signature,
               targetSymbol: candidate,
               boundReceiverType: candidateReceiverType,
               expectedFunctionType: expectedFunctionType,
               range: range,
               availableContextReceiverTypes: availableContextReceiverTypes,
               ctx: ctx
           )
        {
            boundReceiverType = resolvedReceiverType
        }
        if candidates.count == 1 {
            driver.inferFunctionReturnTypesIfNeeded(for: candidates)
        } else if let expectedFunctionType,
                  case let .functionType(expectedFunction) = sema.types.kind(of: expectedFunctionType),
                  candidates.contains(where: {
                      driver.inferredReturnFunctions[$0] != nil
                          && !driver.checkedInferredReturnFunctions.contains($0)
                  })
        {
            // The inferred return is unavailable while choosing a dependency.
            // Infer only an unambiguous input shape. A broader unselected
            // overload must not introduce a dependency cycle.
            let inputType = sema.types.make(.functionType(FunctionType(
                contextReceivers: expectedFunction.contextReceivers,
                receiver: expectedFunction.receiver,
                params: expectedFunction.params,
                returnType: sema.types.nullableAnyType,
                isSuspend: expectedFunction.isSuspend,
                isCallableReference: expectedFunction.isCallableReference,
                nullability: expectedFunction.nullability,
                throws: expectedFunction.throws
            )))
            let inputMatches = candidates.filter { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate) else { return false }
                return driver.helpers.contextualCallableFunctionType(
                    for: signature,
                    targetSymbol: candidate,
                    bindReceiver: isBoundReceiver,
                    boundReceiver: boundReceiverType.map { (candidate, $0) },
                    unboundReceiverType: unboundCallableReceiverType,
                    expectedFunctionType: inputType,
                    interner: interner,
                    availableContextReceiverTypes: availableContextReceiverTypes,
                    sema: sema
                ) != nil
            }
            if inputMatches.count == 1 {
                driver.inferFunctionReturnTypesIfNeeded(for: inputMatches)
            }
        }
        let postponedReturnParameter = driver.helpers.postponedCallableReferenceReturnTypeParameter(
            expectedFunctionType, inferenceParameters: ctx.callableReferenceInferenceParameters, sema: sema
        )
        let hasUncontextualPropertyFunctionOverload = propertyReferenceCandidate != nil
            && !candidates.isEmpty
            && expectedFunctionType == nil
            && expectedCallableReferenceReturnType == nil
        var chosen: SymbolID? = if hasUncontextualPropertyFunctionOverload {
            nil
        } else {
            driver.helpers.chooseCallableReferenceTarget(
                from: candidates,
                expectedType: expectedFunctionType ?? expectedType,
                bindReceiver: isBoundReceiver,
                boundReceiverType: boundReceiverType,
                unboundReceiverType: unboundCallableReceiverType,
                expectedCallableReferenceReturnType: expectedCallableReferenceReturnType,
                postponedReturnTypeParameter: postponedReturnParameter,
                interner: interner,
                availableContextReceiverTypes: availableContextReceiverTypes,
                sema: sema
            )
        }
        if chosen == nil,
           let candidate = propertyReferenceCandidate,
           let expectedFunctionType,
           let propertyReferenceType = propertyReferenceCandidateType,
           sema.types.isSubtype(propertyReferenceType, expectedFunctionType)
        {
            return bindPropertyCallableRef(
                id,
                propertySymbol: candidate.symbol,
                ownerType: candidate.ownerType,
                isUnbound: candidate.isUnbound,
                expectedType: expectedType,
                range: range,
                ctx: ctx,
                sema: sema,
                interner: interner,
                resolvedPropertyType: candidate.type
            )
        }

        // An inapplicable member must not hide an extension callable reference
        // with a compatible expected function type (for example Int::toString
        // as (Int, Int) -> String). Preserve member priority when one matches.
        if chosen == nil,
           hasExplicitMemberCandidates,
           !isConstructorReference,
           !isImplicitlyBoundMember,
           companionCallableReferenceReceiverType == nil,
           let expectedFunctionType,
           let effectiveReceiverType
        {
            let nonNullReceiver = sema.types.makeNonNullable(effectiveReceiverType)
            func isApplicableExtension(_ symbolID: SymbolID) -> Bool {
                guard let symbol = ctx.cachedSymbol(symbolID),
                      symbol.kind == .function,
                      !(symbol.flags.contains(.expectDeclaration)
                          && sema.symbols.actualSymbol(for: symbolID) != nil),
                      sema.symbols.memberExtensionOwnerSymbol(for: symbolID) == nil,
                      driver.helpers.declaresExtensionReceiver(symbolID, sema: sema, interner: interner),
                      let declaredReceiver = sema.symbols.functionSignature(for: symbolID)?.receiverType
                else { return false }
                return driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                    callSiteReceiver: nonNullReceiver,
                    declaredReceiver: declaredReceiver,
                    sema: sema
                )
            }
            let localExtensions = ctx.scope.lookup(member, matching: { symbolID in
                ctx.cachedSymbol(symbolID)?.flags.contains(.localFunction) == true
                    && isApplicableExtension(symbolID)
            })
            let extensions: [SymbolID]
            if !localExtensions.isEmpty {
                extensions = localExtensions
            } else if let local = locals[member],
                      ctx.cachedSymbol(local.symbol)?.flags.contains(.localFunction) == true,
                      isApplicableExtension(local.symbol)
            {
                extensions = [local.symbol]
            } else {
                extensions = ctx.scope.lookup(member, matching: isApplicableExtension)
            }
            if extensions.count == 1 {
                driver.inferFunctionReturnTypesIfNeeded(for: extensions)
            }
            let matching = extensions.filter { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate) else { return false }
                return driver.helpers.contextualCallableReferenceBinding(
                    for: signature,
                    targetSymbol: candidate,
                    bindReceiver: isBoundReceiver,
                    boundReceiver: boundReceiverType.map { (candidate, $0) },
                    unboundReceiverType: unboundCallableReceiverType,
                    expectedFunctionType: expectedFunctionType,
                    postponedReturnTypeParameter: postponedReturnParameter,
                    interner: interner,
                    availableContextReceiverTypes: availableContextReceiverTypes,
                    sema: sema
                ) != nil
            }
            let mostSpecific = driver.callChecker.preferMostSpecificMemberReceiverCandidates(
                matching, receiverType: nonNullReceiver, sema: sema, interner: interner
            )
            if mostSpecific.count == 1 {
                candidates = mostSpecific
                chosen = mostSpecific[0]
            }
        }

        // KUU-3683: `A::member` also resolves as a bound reference on the
        // `A.Companion` singleton — in value position `A` denotes that
        // object, so the bound candidate space is the one
        // `A.Companion::member` already resolves: the companion's own
        // members, members of `A` reachable only when the companion itself
        // inherits `A` (`companion object : A()`, JetBrains
        // companionObjectReceiverInheritsFromOuter.kt), and package
        // extensions whose declared receiver accepts the companion type.
        // The unbound interpretation keeps priority: this retry only runs
        // when nothing above matched the expected function type, so
        // `A::instance` stays `(A) -> Boolean` for an `(A) -> Boolean`
        // context and becomes `() -> Boolean` only when the unbound shape
        // cannot apply.
        if chosen == nil,
           receiver != nil,
           !isBoundReceiver,
           !isConstructorReference,
           !isImplicitlyBoundMember,
           companionCallableReferenceReceiverType == nil,
           propertyReferenceCandidate == nil,
           let unboundClassType
        {
            let companionType = classNameCompanionCallableReferenceReceiverType(
                for: unboundClassType,
                ctx: ctx
            )
            // `companion fun A.member` extensions also join the bound
            // interpretation, with the class name itself bound as the
            // receiver — the same interpretation the `candidates.isEmpty`
            // fallback above applies when no instance member shadows the
            // name. They are the only bound candidates when the class has
            // no companion scope at all.
            let boundCompanionExtensions = companionExtensionCallableReferenceCandidates(
                named: member,
                receiverType: sema.types.makeNonNullable(unboundClassType),
                ctx: ctx
            )
            if companionType != nil || !boundCompanionExtensions.isEmpty {
                let boundMembers = companionType.map { companionType in
                    driver.helpers.collectMemberFunctionCandidates(
                        named: member,
                        receiverType: companionType,
                        sema: sema,
                        interner: interner
                    ).filter { candidate in
                        !driver.helpers.declaresExtensionReceiver(
                            candidate,
                            sema: sema,
                            interner: interner
                        )
                    }
                } ?? []
                let boundExtensions: [SymbolID] = companionType.map { companionType in
                    func isApplicableExtension(_ symbolID: SymbolID) -> Bool {
                        guard let symbol = ctx.cachedSymbol(symbolID),
                              symbol.kind == .function,
                              !(symbol.flags.contains(.expectDeclaration)
                                  && sema.symbols.actualSymbol(for: symbolID) != nil),
                              sema.symbols.memberExtensionOwnerSymbol(for: symbolID) == nil,
                              driver.helpers.declaresExtensionReceiver(
                                  symbolID, sema: sema, interner: interner
                              ),
                              let declaredReceiver = sema.symbols.functionSignature(
                                  for: symbolID
                              )?.receiverType
                        else { return false }
                        return driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                            callSiteReceiver: companionType,
                            declaredReceiver: declaredReceiver,
                            sema: sema
                        )
                    }
                    let localExtensions = ctx.scope.lookup(member, matching: { symbolID in
                        ctx.cachedSymbol(symbolID)?.flags.contains(.localFunction) == true
                            && isApplicableExtension(symbolID)
                    })
                    if !localExtensions.isEmpty {
                        return localExtensions
                    }
                    if let local = locals[member],
                       ctx.cachedSymbol(local.symbol)?.flags.contains(.localFunction) == true,
                       isApplicableExtension(local.symbol)
                    {
                        return [local.symbol]
                    }
                    return ctx.scope.lookup(member, matching: isApplicableExtension)
                } ?? []
                // The class-name value itself is the bound receiver for
                // `companion fun A.member` extensions, while the companion
                // object is the bound receiver for the members/extensions in
                // its scope — keep the two receiver spaces distinct.
                func boundCandidateReceiverType(for candidate: SymbolID) -> TypeID {
                    boundCompanionExtensions.contains(candidate)
                        ? sema.types.makeNonNullable(unboundClassType)
                        : (companionType ?? sema.types.makeNonNullable(unboundClassType))
                }
                let boundPool = boundMembers + boundExtensions + boundCompanionExtensions
                if boundPool.count == 1 {
                    driver.inferFunctionReturnTypesIfNeeded(for: boundPool)
                }
                func boundMatch(_ candidate: SymbolID) -> Bool {
                    guard let signature = sema.symbols.functionSignature(for: candidate)
                    else { return false }
                    return driver.helpers.contextualCallableReferenceBinding(
                        for: signature,
                        targetSymbol: candidate,
                        bindReceiver: true,
                        boundReceiver: (candidate, boundCandidateReceiverType(for: candidate)),
                        expectedFunctionType: expectedFunctionType,
                        postponedReturnTypeParameter: postponedReturnParameter,
                        interner: interner,
                        availableContextReceiverTypes: availableContextReceiverTypes,
                        sema: sema
                    ) != nil
                }
                // Members outrank same-named extensions for the bound
                // interpretation, mirroring Kotlin's member-call resolution.
                let boundChosen = boundMembers.filter(boundMatch)
                    + boundExtensions.filter(boundMatch)
                    + boundCompanionExtensions.filter(boundMatch)
                let mostSpecificBound = driver.callChecker.preferMostSpecificMemberReceiverCandidates(
                    boundChosen,
                    receiverType: companionType ?? sema.types.makeNonNullable(unboundClassType),
                    sema: sema, interner: interner
                )
                if mostSpecificBound.count == 1 {
                    candidates = mostSpecificBound
                    chosen = mostSpecificBound[0]
                    let boundType = boundCandidateReceiverType(for: mostSpecificBound[0])
                    companionCallableReferenceReceiverType = boundType
                    boundReceiverType = boundType
                    unboundCallableReceiverType = nil
                    isBoundReceiver = true
                }
            }
        }

        if let chosen,
           let signature = sema.symbols.functionSignature(for: chosen)
        {
            var contextualSpecialization: ContextualCallableReferenceBinding?
            var inferredType = driver.helpers.callableFunctionType(
                for: signature,
                bindReceiver: isBoundReceiver,
                boundReceiver: boundReceiverType.map { (chosen, $0) },
                unboundReceiverType: unboundCallableReceiverType,
                targetSymbol: chosen,
                interner: interner,
                sema: sema
            )
            if let expectedFunctionType,
               let unitCoercedType = driver.helpers.unitCoercedCallableReferenceType(
                   inferredType,
                   expectedFunctionType: expectedFunctionType,
                   sema: sema
               )
            {
                inferredType = unitCoercedType
            }
            let resultType: TypeID
            func resultTypePreservingSuspendConversionSource(_ fallback: TypeID) -> TypeID {
                guard expectedSamInterfaceType == nil,
                      let expectedFunctionType,
                      let convertedType = sema.types.suspendConversionType(from: inferredType, to: expectedFunctionType)
                else {
                    return fallback
                }
                // Arguments retain their source shape for call adaptation;
                // directly typed references materialize the suspend adapter.
                return ctx.isCallableReferenceArgument ? inferredType : convertedType
            }
            // An expected type that still mentions type parameters belongs to a
            // generic signature whose type arguments are inferred from this very
            // argument (`fun <T> runCatching(block: () -> T)`). Checking against
            // it would fail, and adopting it would hide the concrete type the
            // caller needs for inference, so report the reference's own type.
            if let expectedFunctionType {
                let concreteResult = expectedSamInterfaceType
                    ?? expectedType.flatMap { expected in
                        isConcreteKFunctionReferenceShape(expected, sema: sema, interner: interner)
                            ? sema.types.makeNonNullable(expected)
                            : nil
                    }
                    ?? expectedFunctionType
                if !signature.reifiedTypeParameterIndices.isEmpty {
                    if let specialization = driver.helpers.contextualCallableReferenceBinding(
                        for: signature,
                        bindReceiver: isBoundReceiver,
                        boundReceiver: boundReceiverType.map { (chosen, $0) },
                        unboundReceiverType: unboundCallableReceiverType,
                        expectedFunctionType: expectedFunctionType,
                        postponedReturnTypeParameter: postponedReturnParameter,
                        interner: interner,
                        availableContextReceiverTypes: availableContextReceiverTypes,
                        sema: sema
                    ) {
                        inferredType = specialization.functionType
                        contextualSpecialization = specialization
                    } else {
                        ctx.sema.diagnostics.error(
                            "KSWIFTK-SEMA-INFER", "Cannot infer type arguments for reified callable reference.", range: range
                        )
                    }
                    resultType = resultTypePreservingSuspendConversionSource(
                        postponedReturnParameter == nil ? concreteResult : inferredType
                    )
                } else if let postponedReturnParameter,
                          let specialization = driver.helpers.contextualCallableReferenceBinding(
                              for: signature, bindReceiver: isBoundReceiver,
                              boundReceiver: boundReceiverType.map { (chosen, $0) },
                              unboundReceiverType: unboundCallableReceiverType,
                              expectedFunctionType: expectedFunctionType,
                              postponedReturnTypeParameter: postponedReturnParameter,
                              interner: interner,
                              availableContextReceiverTypes: availableContextReceiverTypes,
                              sema: sema
                          ) {
                    inferredType = specialization.functionType
                    contextualSpecialization = specialization
                    resultType = inferredType
                } else if !sema.types.typeContainsAnyTypeParam(concreteResult) {
                    if let specialization = driver.helpers.contextualCallableReferenceBinding(
                        for: signature,
                        bindReceiver: isBoundReceiver,
                        boundReceiver: boundReceiverType.map { (chosen, $0) },
                        unboundReceiverType: unboundCallableReceiverType,
                        expectedFunctionType: expectedFunctionType,
                        interner: interner,
                        availableContextReceiverTypes: availableContextReceiverTypes,
                        sema: sema
                    ) {
                        inferredType = specialization.functionType
                        contextualSpecialization = specialization
                    } else {
                        ctx.sema.diagnostics.error(
                            "KSWIFTK-TYPE-0001",
                            "Type constraint could not be satisfied.",
                            range: range
                        )
                    }
                    // Keep the selected reference's concrete function type.
                    // `expectedFunctionType` may be an input-only placeholder
                    // such as `(Char) -> Any?` synthesized while an overloaded
                    // call compares HOF candidates. Widening the reference to
                    // that placeholder hides its real return type from the
                    // enclosing overload resolver.
                    resultType = resultTypePreservingSuspendConversionSource(
                        expectedSamInterfaceType ?? inferredType
                    )
                } else if isConstructorReference,
                          let unboundInnerConstructorReceiverType,
                          let innerConstructorExpectedType = driver.helpers.specializeInnerConstructorExpectedFunctionType(
                              expectedFunctionType,
                              targetSymbol: chosen,
                              unboundReceiverType: unboundInnerConstructorReceiverType,
                              inferenceParameters: ctx.callableReferenceInferenceParameters,
                              sema: sema
                          ),
                          let specialization = driver.helpers.contextualCallableReferenceBinding(
                              for: signature,
                              targetSymbol: chosen,
                              bindReceiver: isBoundReceiver,
                              boundReceiver: boundReceiverType.map { (chosen, $0) },
                              unboundReceiverType: unboundCallableReceiverType,
                              expectedFunctionType: innerConstructorExpectedType,
                              postponedReturnTypeParameter: postponedReturnParameter,
                              interner: interner,
                              availableContextReceiverTypes: availableContextReceiverTypes,
                              sema: sema
                          )
                {
                    // An inner constructor's own class parameters still need
                    // the contextual return type when its enclosing generic
                    // type is being inferred.
                    inferredType = specialization.functionType
                    contextualSpecialization = specialization
                    resultType = inferredType
                } else {
                    // A generic call may infer its input type arguments from a
                    // callable reference. Preserve the reference's concrete
                    // function shape, but still bind a scalar-vararg adapter
                    // so the call resolver can infer from its expanded inputs.
                    if ctx.isCallableReferenceArgument,
                       signature.valueParameterIsVararg.contains(true),
                       let specialization = driver.helpers.contextualCallableReferenceBinding(
                           for: signature,
                           targetSymbol: chosen,
                           bindReceiver: isBoundReceiver,
                           boundReceiver: boundReceiverType.map { (chosen, $0) },
                           unboundReceiverType: unboundCallableReceiverType,
                           expectedFunctionType: expectedFunctionType,
                           postponedReturnTypeParameter: postponedReturnParameter,
                           interner: interner,
                           availableContextReceiverTypes: availableContextReceiverTypes,
                           sema: sema
                       )
                    {
                        inferredType = specialization.functionType
                        contextualSpecialization = specialization
                    }
                    resultType = inferredType
                }

            } else {
                if !signature.reifiedTypeParameterIndices.isEmpty {
                    if isBoundReceiver,
                       let specialization = driver.helpers.contextualCallableReferenceBinding(
                           for: signature, bindReceiver: true,
                           boundReceiver: boundReceiverType.map { (chosen, $0) },
                           unboundReceiverType: unboundCallableReceiverType,
                           expectedFunctionType: nil,
                           expectedCallableReferenceReturnType: expectedCallableReferenceReturnType,
                           interner: interner,
                           availableContextReceiverTypes: availableContextReceiverTypes,
                           sema: sema
                       ) {
                        inferredType = specialization.functionType
                        contextualSpecialization = specialization
                    } else {
                        ctx.sema.diagnostics.error(
                            "KSWIFTK-SEMA-INFER", "Reified callable reference requires contextual type arguments.", range: range
                        )
                    }
                }
                if let expectedCallableReferenceReturnType,
                   !signature.typeParameterSymbols.isEmpty
                {
                    if let specialization = driver.helpers.contextualCallableReferenceBinding(
                        for: signature,
                        bindReceiver: isBoundReceiver,
                        boundReceiver: boundReceiverType.map { (chosen, $0) },
                        unboundReceiverType: unboundCallableReceiverType,
                        expectedFunctionType: nil,
                        expectedCallableReferenceReturnType: expectedCallableReferenceReturnType,
                        interner: interner,
                        availableContextReceiverTypes: availableContextReceiverTypes,
                        sema: sema
                    ) {
                        inferredType = specialization.functionType
                        contextualSpecialization = specialization
                    } else {
                        ctx.sema.diagnostics.error(
                            "KSWIFTK-TYPE-0001",
                            "Type constraint could not be satisfied.",
                            range: range
                        )
                    }
                }
                resultType = inferredType
            }
            // BUG-164: A callable reference passed to a fun-interface parameter
            // must be SAM-converted and bound to the interface type, not left as a
            // bare function type.  `lowerCallableRefExpr` checks `isSamConversion`
            // and emits the wrapper object that makes interface dispatch work.
            // Only perform the conversion when the resolved result is the concrete
            // interface type; if the expected type still contains type parameters,
            // leave the reference as a function value so generic inference can
            // substitute a concrete instantiation later.
            if let expectedSamInterfaceType,
               resultType == expectedSamInterfaceType
            {
                sema.bindings.markSamConversion(id)
                sema.bindings.bindSamInterfaceType(id, type: expectedSamInterfaceType)
                sema.bindings.bindSamUnderlyingFunctionType(id, type: expectedFunctionType ?? inferredType)
            }
            let requiresFunctionConversion: Bool = {
                guard case let .functionType(function) = sema.types.kind(of: resultType) else { return false }
                return function.isSuspend != signature.isSuspend
                    || (function.returnType == sema.types.unitType && signature.returnType != sema.types.unitType)
            }()
            if let contextualSpecialization,
               contextualSpecialization.requiresAdapter || !contextualSpecialization.typeArguments.isEmpty
                   || requiresFunctionConversion
            {
                bindCallableReferenceBinding(
                    id, target: chosen, specialization: contextualSpecialization, range: range, ctx: ctx,
                    requiresFunctionConversion: requiresFunctionConversion,
                    dispatchReceiverSymbol: importedObjectCallableReferenceReceiver?.symbol
                )
            }
            sema.bindings.bindIdentifier(id, symbol: chosen)
            sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            // REFL-003: Tag the callable reference as KFunction so KIR
            // lowering can emit type identity metadata.
            sema.bindings.bindCallableRefKind(id, kind: .functionRef)
            if isImplicitlyBoundMember {
                sema.bindings.markImplicitReceiverMember(
                    id,
                    name: member,
                    receiverType: implicitBoundReceiver?.type
                )
                if let receiverSymbol = implicitBoundReceiver?.symbol {
                    sema.bindings.markImplicitReceiverOuterReceiver(id, symbol: receiverSymbol)
                }
            }
            if unboundClassType != nil,
               companionCallableReferenceReceiverType == nil,
               (!isConstructorReference || unboundInnerConstructorReceiverType != nil)
            {
                sema.bindings.markUnboundCallableRef(id)
            } else {
                // Re-inference under a different expected type may flip the
                // reference to a bound interpretation (companion member or
                // `companion fun C.member` extension). Clear the mark an
                // earlier unbound-shaped inference left so KIR lowering
                // captures the receiver (KUU-3820).
                sema.bindings.unmarkUnboundCallableRef(id)
            }
            let captures = receiver.map { recv in
                driver.captureAnalyzer.collectCapturedOuterSymbols(
                    in: recv,
                    ast: ast,
                    sema: sema,
                    outerSymbols: outerSymbols
                )
            } ?? []
            sema.bindings.bindCaptureSymbols(id, symbols: captures)
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }

        if candidates.isEmpty {
            // Inherited `private` members never enter the candidate set
            // (they are not inherited), but a qualified reference still
            // resolves the name — report it as inaccessible rather than
            // unresolved, matching kotlinc (KUU-3762). A type-name receiver
            // (`Type::member`) also reaches the companion's member scope.
            var privateMemberProbeTypes = effectiveReceiverType.map {
                [sema.types.makeNonNullable($0)]
            } ?? []
            if unboundClassType != nil,
               let (_, ownerSymbol) = effectiveReceiverType.flatMap({
                   resolveClassTypeSymbol($0, sema: sema)
               }),
               let companionType = driver.helpers.companionScopeType(
                   for: ownerSymbol.id, ctx: ctx
               )
            {
                privateMemberProbeTypes.append(companionType)
            }
            // An unqualified reference also reaches the implicit receiver
            // tower's private members (KUU-3766).
            if let privateMember = driver.helpers.inaccessiblePrivateQualifiedMember(
                named: member,
                probeReceiverTypes: privateMemberProbeTypes,
                ctx: ctx
            ) ?? driver.helpers.inaccessiblePrivateImplicitReceiverMember(
                named: member, ctx: ctx
            ) {
                driver.helpers.emitVisibilityError(
                    for: privateMember,
                    name: interner.resolve(member),
                    range: range,
                    diagnostics: ctx.sema.diagnostics
                )
            } else {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0022",
                    "Unresolved reference '::\(interner.resolve(member))'.",
                    range: range
                )
            }
        } else {
            ctx.sema.diagnostics.error(
                "KSWIFTK-TYPE-0001",
                "No unambiguous callable reference matches the expected function type.",
                range: range
            )
        }
        let fallbackType: TypeID = if let expectedType,
                                      case .functionType = sema.types.kind(of: expectedType)
        {
            expectedType
        } else if candidates.isEmpty {
            sema.types.errorType
        } else {
            sema.types.anyType
        }
        let fallbackCaptures = receiver.map { recv in
            driver.captureAnalyzer.collectCapturedOuterSymbols(
                in: recv,
                ast: ast,
                sema: sema,
                outerSymbols: outerSymbols
            )
        } ?? []
        sema.bindings.bindCaptureSymbols(id, symbols: fallbackCaptures)
        sema.bindings.bindExprType(id, type: fallbackType)
        return fallbackType
    }

    private func companionExtensionCallableReferenceCandidates(
        named name: InternedString,
        receiverType: TypeID,
        ctx: TypeInferenceContext
    ) -> [SymbolID] {
        let sema = ctx.sema
        var candidates = ctx.cachedScopeLookup(name)
        // Name-indexed companion extension decls replace a per-call scan of
        // every file's `topLevelDecls` (same order, built once per module).
        for symbol in driver.companionExtensionFunctionDeclsByName[name] ?? []
        where !candidates.contains(symbol) {
            candidates.append(symbol)
        }
        return candidates.filter { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  isCompanionExtension(candidate, ctx: ctx),
                  let declaredReceiver = sema.symbols.functionSignature(for: candidate)?.receiverType
            else {
                return false
            }
            return driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                callSiteReceiver: receiverType,
                declaredReceiver: declaredReceiver,
                sema: sema
            )
        }
    }

    private func isCompanionExtension(_ symbolID: SymbolID, ctx: TypeInferenceContext) -> Bool {
        guard let symbol = ctx.sema.symbols.symbol(symbolID),
              let sourceFileID = symbol.declSite?.start.file,
              let file = ctx.ast.file(for: sourceFileID)
        else {
            return false
        }
        for declID in file.topLevelDecls {
            guard let decl = ctx.ast.arena.decl(declID) else { continue }
            switch decl {
            case let .funDecl(function) where function.range == symbol.declSite:
                return function.modifiers.contains(.companion) && function.receiverType != nil
            case let .propertyDecl(property) where property.range == symbol.declSite:
                return property.modifiers.contains(.companion) && property.receiverType != nil
            default:
                continue
            }
        }
        return false
    }

    /// REFL-PRIMOP: `Int::plus` / `Int::times` (and the other primitive
    /// numeric types where an expected function type selects the
    /// homogeneous `(T, T) -> T` overload -- Byte/Short/Char are excluded
    /// because their real stdlib `plus`/`times` overloads promote the result to `Int`, unlike
    /// Int/Long/UInt/ULong/Float/Double's own-type result) have no real
    /// `plus`/`times` member symbol to resolve: arithmetic on primitives is
    /// a table-driven type-inference special case
    /// (`tryInferRegularMemberCallPrimitiveSpecials`), not a function
    /// declaration. Synthesizes the reference's function type directly and
    /// records the raw binary operator on `sema.bindings` for KIR lowering
    /// (`LambdaLowerer.lowerPrimitiveOperatorCallableRef`) to build a
    /// wrapper around, since there is no symbol for it to call either.
    ///
    /// Returns `nil` when `receiverName`/`member` don't name a supported
    /// primitive-operator pair, so the caller falls through to ordinary
    /// candidate resolution.
    private func inferPrimitiveOperatorCallableRefExpr(
        _ id: ExprID,
        receiverName: InternedString,
        member: InternedString,
        expectedType: TypeID?,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        guard let primitive = driver.builtinTypeNamesCache.primitiveType(for: receiverName) else {
            return nil
        }
        let op: BinaryOp
        switch interner.resolve(member) {
        case "plus": op = .add
        case "times": op = .multiply
        default: return nil
        }
        switch primitive {
        case .int, .long, .uint, .ulong, .float, .double:
            break
        default:
            return nil
        }
        let contextualType = expectedType.map { type in
            sema.types.nominalFunctionType(for: type).map {
                sema.types.make(.functionType($0))
            } ?? type
        }
        guard let expectedType = contextualType, case .functionType = sema.types.kind(of: expectedType) else {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0003",
                "Ambiguous overload resolution for '\(interner.resolve(receiverName))::\(interner.resolve(member))'.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        let operandType = sema.types.make(.primitive(primitive, .nonNull))
        let functionType = sema.types.make(.functionType(FunctionType(
            params: [operandType, operandType],
            returnType: operandType,
            isSuspend: false,
            isCallableReference: true,
            nullability: .nonNull
        )))
        driver.emitSubtypeConstraint(
            left: functionType,
            right: expectedType,
            range: range,
            solver: ConstraintSolver(),
            sema: sema,
            diagnostics: ctx.sema.diagnostics
        )
        sema.bindings.bindPrimitiveOperatorCallableRef(id, op: op)
        sema.bindings.bindCallableRefKind(id, kind: .functionRef)
        sema.bindings.bindExprType(id, type: expectedType)
        return expectedType
    }

    /// REFL-PRIMOP: `Boolean::not` has no real member symbol because ordinary
    /// Boolean negation is a compiler intrinsic. Synthesize its unique
    /// callable-reference type and record the unary operator for KIR lowering.
    private func inferPrimitiveUnaryOperatorCallableRefExpr(
        _ id: ExprID,
        receiverName: InternedString,
        member: InternedString,
        expectedType: TypeID?,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        guard interner.resolve(member) == "not",
              let primitive = driver.builtinTypeNamesCache.primitiveType(for: receiverName)
        else {
            return nil
        }
        guard case .boolean = primitive else { return nil }

        let booleanType = sema.types.booleanType
        let functionType = sema.types.make(.functionType(FunctionType(
            params: [booleanType],
            returnType: booleanType,
            isSuspend: false,
            isCallableReference: true,
            nullability: .nonNull
        )))
        if let expectedType {
            let constraintTarget = sema.types.nominalFunctionType(for: expectedType).map {
                sema.types.make(.functionType($0))
            } ?? expectedType
            driver.emitSubtypeConstraint(
                left: functionType,
                right: constraintTarget,
                range: range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.sema.diagnostics
            )
        }

        sema.bindings.bindPrimitiveUnaryOperatorCallableRef(id, op: .not)
        sema.bindings.bindCallableRefKind(id, kind: .functionRef)
        let resultType = expectedType ?? functionType
        sema.bindings.bindExprType(id, type: resultType)
        return resultType
    }

    private func resolveExtensionPropertyReferenceType(
        _ propertySymbol: SymbolID,
        receiverType: TypeID,
        fallbackPropertyType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> (valueType: TypeID, specialization: ContextualCallableReferenceBinding?)? {
        guard let getter = sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol),
              let signature = sema.symbols.functionSignature(for: getter)
        else {
            return (fallbackPropertyType, nil)
        }
        guard !signature.typeParameterSymbols.isEmpty else {
            return (fallbackPropertyType, nil)
        }
        guard let specialization = driver.helpers.contextualCallableReferenceBinding(
            for: signature,
            bindReceiver: false,
            boundReceiver: (propertySymbol, receiverType),
            expectedFunctionType: nil,
            interner: interner,
            sema: sema
        ), case let .functionType(functionType) = sema.types.kind(of: specialization.functionType)
        else {
            return nil
        }
        return (functionType.returnType, specialization)
    }

    /// Binds an unbound `Type::property` (or, when `ownerType` is `nil`, a
    /// bound `instance::property`) callable reference to `propertySymbol` and
    /// returns its result type. Shared by the FQ-based owner-member lookup
    /// and the package-level extension-property fallback in
    /// `inferCallableRefExpr`, which differ only in how they find
    /// `propertySymbol`.
    private func bindPropertyCallableRef(
        _ id: ExprID,
        propertySymbol: SymbolID,
        ownerType: TypeID?,
        isUnbound: Bool,
        expectedType: TypeID?,
        range: SourceRange,
        ctx: TypeInferenceContext,
        sema: SemaModule,
        interner: StringInterner,
        resolvedPropertyType: TypeID? = nil
    ) -> TypeID {
        let getterAccessor = sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol)
            ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: propertySymbol)
        if sema.symbols.functionSignature(for: getterAccessor)?.contextReceiverTypes.isEmpty == false {
            sema.diagnostics.error(
                "KSWIFTK-TYPE-0001",
                "Callable references to properties with context parameters are not supported.",
                range: range
            )
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }

        var propertyType = resolvedPropertyType
            ?? sema.symbols.propertyType(for: propertySymbol)
            ?? sema.types.errorType
        if resolvedPropertyType == nil,
           let ownerType,
           let owner = sema.symbols.parentSymbol(for: propertySymbol)
        {
            propertyType = driver.helpers.resolveMemberPropertyType(
                propertyType,
                receiverType: ownerType,
                ownerSymbol: owner,
                sema: sema
            )
        }
        let isMutable = isPropertySetterAccessible(propertySymbol, ctx: ctx)
        let inferredType = kPropertyReferenceType(
            ownerType: ownerType,
            valueType: propertyType,
            isMutable: isMutable,
            sema: sema,
            interner: interner
        ) ?? propertyType
        let resultType = resolvedPropertyReferenceResultType(
            expectedType: expectedType,
            inferredType: inferredType,
            sema: sema,
            interner: interner
        )
        sema.bindings.bindIdentifier(id, symbol: propertySymbol)
        sema.bindings.bindCallableTarget(id, target: .symbol(propertySymbol))
        sema.bindings.bindCallableRefKind(id, kind: .propertyRef)
        if isUnbound {
            sema.bindings.markUnboundCallableRef(id)
        } else {
            // See the function-reference commit above: re-inference can
            // switch a `Type::property` reference to a bound shape (for
            // example a `companion val C.prop` extension), so any earlier
            // unbound mark must not survive the bound commit.
            sema.bindings.unmarkUnboundCallableRef(id)
        }
        markPropertyReferenceSamConversionIfNeeded(
            id,
            expectedType: expectedType,
            resultType: resultType,
            sema: sema
        )
        sema.bindings.bindExprType(id, type: resultType)
        return resultType
    }

    /// Builds the concrete `KProperty0<V>` / `KMutableProperty0<V>` /
    /// `KProperty1<Owner, V>` / `KMutableProperty1<Owner, V>` type for a plain
    /// property callable reference (`Type::property`, `instance::property`, or
    /// bare `::property`), so a reference used without an expected type (e.g.
    /// `val ref = C::v`, or as an argument whose parameter type is itself
    /// inferred, like `listOf(C::v)`) still gets a real KProperty-conforming
    /// type instead of degrading to the property's own value type.
    ///
    /// `ownerType` is `nil` for a bound (`instance::property`) or top-level
    /// (bare `::property`) reference (arity 0: `KProperty0`/`KMutableProperty0`),
    /// and the receiver's class type for an unbound (`Type::property`)
    /// reference (arity 1: `KProperty1`/`KMutableProperty1`).
    ///
    /// Returns `nil` when the interface symbol isn't registered (e.g.
    /// `kotlin.reflect` wasn't injected), in which case callers should keep
    /// their previous fallback behavior.
    private func kPropertyReferenceType(
        ownerType: TypeID?,
        valueType: TypeID,
        isMutable: Bool,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let reflectPkg = [interner.intern("kotlin"), interner.intern("reflect")]
        let interfaceName: String
        let typeArgs: [TypeArg]
        if let ownerType {
            interfaceName = isMutable ? "KMutableProperty1" : "KProperty1"
            typeArgs = [.invariant(ownerType), .invariant(valueType)]
        } else {
            interfaceName = isMutable ? "KMutableProperty0" : "KProperty0"
            typeArgs = [.invariant(valueType)]
        }
        guard let interfaceSymbol = sema.symbols.lookup(fqName: reflectPkg + [interner.intern(interfaceName)]) else {
            return nil
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: interfaceSymbol,
            args: typeArgs,
            nullability: .nonNull
        )))
    }

    private func isPropertySetterAccessible(_ propertySymbol: SymbolID, ctx: TypeInferenceContext) -> Bool {
        guard let property = ctx.sema.symbols.symbol(propertySymbol),
              property.flags.contains(.mutable)
        else {
            return false
        }
        guard let setterVisibility = ctx.sema.symbols.propertySetterVisibility(for: propertySymbol) else {
            return ctx.visibilityChecker.isAccessible(
                property,
                fromFile: ctx.currentFileID,
                enclosingClass: ctx.enclosingClassSymbol
            )
        }
        let setter = SemanticSymbol(
            id: property.id,
            kind: property.kind,
            name: property.name,
            fqName: property.fqName,
            declSite: property.declSite,
            visibility: setterVisibility,
            flags: property.flags
        )
        return ctx.visibilityChecker.isAccessible(
            setter,
            fromFile: ctx.currentFileID,
            enclosingClass: ctx.enclosingClassSymbol
        )
    }

    /// KSP-496: a *property* callable reference used in a fun-interface
    /// position (`fun interface IntFromC { fun apply(c: C): Int }` +
    /// `useSam(C::v)`) needs the same SAM-conversion bookkeeping BUG-164 added
    /// for function references. `resolvedPropertyReferenceResultType` already
    /// adopts the interface as the reference's type, but `lowerCallableRefExpr`
    /// only builds the wrapper object that makes interface dispatch work when
    /// `isSamConversion` is set — without it the raw tagged callable value was
    /// handed to the interface parameter and the call panicked at runtime
    /// ("Virtual dispatch failed: method not found in vtable/itable").
    private func markPropertyReferenceSamConversionIfNeeded(
        _ id: ExprID,
        expectedType: TypeID?,
        resultType: TypeID,
        sema: SemaModule
    ) {
        guard let expectedType,
              resultType == expectedType,
              let samFunctionType = driver.helpers.samCallableReferenceFunctionType(for: expectedType, sema: sema)
        else {
            return
        }
        sema.bindings.markSamConversion(id)
        sema.bindings.bindSamInterfaceType(id, type: expectedType)
        sema.bindings.bindSamUnderlyingFunctionType(
            id,
            type: sema.types.make(.functionType(samFunctionType))
        )
    }

    /// A property reference is also a valid function value — Kotlin allows
    /// `list.map(Person::name)` or `val f: (Person) -> String = Person::name`
    /// — so an `expectedType` that is a function type (or SAM-convertible
    /// interface) is always trusted as-is, exactly like before this fix and
    /// exactly like the sibling function-reference branch above.
    ///
    /// Otherwise, `expectedType` is only trusted when it is itself one of the
    /// four concrete KProperty shapes (`KProperty0`/`KMutableProperty0`/
    /// `KProperty1`/`KMutableProperty1`) — the same set
    /// `propertyReferenceShape` in `LambdaLowerer+PropertyReferenceLowering.swift`
    /// recognizes to build the real KIR wrapper object. A broader or unrelated
    /// expected type (`Any`, `KProperty<*>`, `KCallable<*>`, ...) would
    /// silently defeat that wrapper and fall back to a non-conforming legacy
    /// value, so `inferredType` (the correct concrete shape this reference
    /// actually has) is used instead in that case.
    private func resolvedPropertyReferenceResultType(
        expectedType: TypeID?,
        inferredType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        guard let expectedType else {
            return inferredType
        }
        if case .functionType = sema.types.kind(of: expectedType) {
            // A concrete function-type expectation is only safe to adopt when
            // the reference's own `KPropertyN` type is a subtype of it via the
            // `KPropertyN` → `FunctionN` inheritance path (KUU-1195). The
            // previous unconditional trust accepted signature mismatches
            // (`supply(Box::value)` for a `() -> Int` parameter, receiver or
            // return-type mismatches) whose binaries then crashed at runtime
            // on invoke. On a mismatch keep the real inferred type so the
            // caller's own subtype check reports the failure. When the
            // expected type still mentions type parameters (a generic call
            // signature whose arguments are being inferred), returning the
            // concrete `KMutablePropertyN`/`KPropertyN` type instead lets the
            // argument constraint `KMutableProperty1<Box,Int> <: (T) -> R`
            // actually bind `T`/`R` through the `FunctionN` supertype — the
            // adopted `(T) -> R` would decompose to a vacuous self-constraint
            // and leave `R` unbound. A non-`KPropertyN` inferred type means
            // `kotlin.reflect` was unavailable; keep trusting then too.
            if sema.types.typeContainsAnyTypeParam(expectedType) {
                if isConcreteKPropertyReferenceShape(inferredType, sema: sema, interner: interner) {
                    return inferredType
                }
                return expectedType
            }
            if isConcreteKPropertyReferenceShape(inferredType, sema: sema, interner: interner),
               !sema.types.isSubtype(inferredType, expectedType)
            {
                return inferredType
            }
            return expectedType
        }
        if let samFunctionType = driver.helpers.samCallableReferenceFunctionType(for: expectedType, sema: sema) {
            // Same check against the SAM signature for a fun-interface
            // expected type (`useSam(C::v)`): adopt the interface type only
            // when the reference's function view matches the SAM. A SAM
            // signature with context receivers additionally accepts the
            // flattened positional view (`context(C) () -> V` matches
            // `KProperty1<C, V>`'s `(C) -> V` function view — KUU-3170).
            let samFunctionTypeID = sema.types.make(.functionType(samFunctionType))
            if !sema.types.typeContainsAnyTypeParam(expectedType),
               isConcreteKPropertyReferenceShape(inferredType, sema: sema, interner: interner),
               !sema.types.isSubtype(inferredType, samFunctionTypeID),
               !sema.types.isSubtype(
                   inferredType,
                   driver.helpers.contextFlattenedFunctionType(samFunctionTypeID, sema: sema)
               )
            {
                return inferredType
            }
            return expectedType
        }
        guard isConcreteKPropertyReferenceShape(expectedType, sema: sema, interner: interner) else {
            return inferredType
        }
        guard isConcreteKPropertyReferenceShape(inferredType, sema: sema, interner: interner) else {
            return expectedType
        }
        // Keep the reference's actual shape when a concrete KPropertyN
        // expectation has the wrong arity or type arguments. The enclosing
        // expression's subtype check then emits the mismatch diagnostic.
        if sema.types.typeContainsAnyTypeParam(expectedType)
            || !sema.types.isSubtype(inferredType, expectedType)
        {
            return inferredType
        }
        return expectedType
    }

    private func isConcreteKPropertyReferenceShape(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(type)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        switch interner.resolve(symbol.name) {
        case "KProperty0", "KMutableProperty0", "KProperty1", "KMutableProperty1":
            return true
        default:
            return false
        }
    }

    private func isConcreteKFunctionReferenceShape(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(type)),
              let symbol = sema.symbols.symbol(classType.classSymbol),
              Array(symbol.fqName.dropLast()) == ["kotlin", "reflect"].map(interner.intern)
        else {
            return false
        }
        let prefix = "KFunction"
        let name = interner.resolve(symbol.name)
        guard name.hasPrefix(prefix),
              let arity = Int(name.dropFirst(prefix.count)),
              (0 ... 22).contains(arity)
        else {
            return false
        }
        return classType.args.count == arity + 1
    }
}
