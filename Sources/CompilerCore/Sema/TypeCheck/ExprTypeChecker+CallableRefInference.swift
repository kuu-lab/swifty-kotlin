
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
        let outerSymbols = Set(locals.values.map(\.symbol))

        if let expectedType, sema.types.nominalFunctionType(for: expectedType) != nil {
            sema.bindings.bindNominalFunctionExpectedType(id, type: expectedType)
        }

        // ── T::class  — reified type-parameter class reference ──────────
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

        // ── REFL-PRIMOP: Int::plus / Int::times — primitive operator with
        // no backing symbol ───────────────────────────────────────────────
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

        // ── REFL-003: Type::member — unbound callable reference ─────────
        // When the receiver is a name that refers to a class/interface/enum
        // (not an instance variable), treat it as an unbound member reference.
        // The resulting function type includes the receiver type as the
        // first parameter: `Type::method` becomes `(Type) -> ReturnType`.
        var unboundClassType: TypeID?
        if let receiverTypeRef = ast.arena.callableRefReceiverTypeRef(for: id) {
            unboundClassType = driver.helpers.resolveTypeRef(
                receiverTypeRef,
                ast: ast,
                sema: sema,
                interner: interner,
                scope: ctx.scope,
                diagnostics: ctx.semaCtx.diagnostics,
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
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0062",
                        "Type argument count mismatch: expected \(argumentCounts.expected) but got \(argumentCounts.actual).",
                        range: range
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
            }
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
                } else {
                    unboundClassType = sema.types.make(
                        .classType(ClassType(classSymbol: sym.id, args: [], nullability: .nonNull))
                    )
                }
                break
            }

            if unboundClassType == nil,
               let primitive = driver.builtinTypeNamesCache.primitiveType(for: receiverName)
            {
                // Builtin primitive classes may not be present in the lexical scope,
                // but their callable references still use the primitive receiver path.
                unboundClassType = sema.types.make(.primitive(primitive, .nonNull))
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
            receiverType = driver.inferExpr(receiver, ctx: ctx, locals: &locals, expectedType: nil)
        } else {
            receiverType = nil
        }

        // For unbound type references, use the resolved class type for
        // member lookup instead of the expression-inferred type (which
        // may degrade to Any for classes without companion objects).
        let effectiveReceiverType = unboundClassType ?? receiverType

        var candidates: [SymbolID] = []
        // Resolve receiver members before the bare-property shortcut below:
        // a package `val flush` must not hide `Writer.flush` for `::flush` in
        // implicit-receiver scope. Local declarations retain lexical priority.
        let hasLocalDeclaration = locals[member] != nil
        var implicitBoundReceiver: (type: TypeID, symbol: SymbolID)?
        var implicitPropertyCandidate: SymbolID?
        let implicitMemberCandidates: [SymbolID] = {
            guard receiver == nil, !hasLocalDeclaration
            else { return [] }
            var receivers = ctx.implicitReceiverStack
            if let type = ctx.implicitReceiverType,
               let symbol = locals[interner.intern("this")]?.symbol,
               receivers.last?.symbol != symbol
            {
                receivers.append((type, symbol))
            }
            var hiddenDslMarkers = Set<String>()
            for implicitReceiver in receivers.reversed() {
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
                    // Kotlin rejects every `::` form for member-extensions
                    // ("member and an extension at the same time"), including
                    // the implicitly-bound `::name` form inside the owner.
                    !driver.helpers.declaresExtensionReceiver(
                        candidate,
                        sema: sema,
                        interner: interner
                    )
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
                let memberProperties: [SymbolID] = if let (_, owner) = resolveClassTypeSymbol(nonNullImplicitReceiver, sema: sema) {
                    sema.symbols.lookupAll(fqName: owner.fqName + [member]).filter { symbolID in
                        let kind = ctx.cachedSymbol(symbolID)?.kind
                        return (kind == .property || kind == .field)
                            && sema.symbols.extensionPropertyReceiverType(for: symbolID) == nil
                    }
                } else { [] }
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
                    return []
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
            sema.bindings.markImplicitReceiverMember(id, name: member)
            sema.bindings.markImplicitReceiverOuterReceiver(id, symbol: implicitBoundReceiver.symbol)
            return bindPropertyCallableRef(
                id,
                propertySymbol: property,
                ownerType: nil,
                isUnbound: false,
                expectedType: expectedType,
                sema: sema,
                interner: interner
            )
        }
        // REFL-CTOR: set when `candidates` were filled with constructor
        // symbols for a bare `::Foo` reference below. A constructor
        // signature's `receiverType` field carries the class type for the
        // constructor body's own implicit `this` (MemberHeaderCollection.swift),
        // not a real extension-style receiver -- `callableFunctionType` must
        // therefore treat it as already "bound" (excluded from the resulting
        // function type's parameter list) the same way a bound `obj::method`
        // reference is, or `(Int) -> Foo` would gain a spurious leading `Foo`
        // parameter.
        var isConstructorReference = false
        var isImplicitlyBoundMember = false
        if let effectiveReceiverType {
            let nonNullReceiver = sema.types.makeNonNullable(effectiveReceiverType)
            let memberCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: member,
                receiverType: nonNullReceiver,
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
            if !memberCandidates.isEmpty {
                candidates = memberCandidates
            } else {
                // Property references use the same inheritance-aware lookup as
                // ordinary member reads (for example MutableList<Int>::size).
                if let property = driver.helpers.lookupMemberProperty(
                    named: member,
                    receiverType: nonNullReceiver,
                    sema: sema
                ), sema.symbols.extensionPropertyReceiverType(for: property.symbol) == nil {
                    return bindPropertyCallableRef(
                        id,
                        propertySymbol: property.symbol,
                        ownerType: unboundClassType != nil ? nonNullReceiver : nil,
                        isUnbound: unboundClassType != nil,
                        expectedType: expectedType,
                        sema: sema,
                        interner: interner
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
                // accepts `nonNullReceiver`.
                if candidates.isEmpty {
                    let extensionPropertyCandidates = ctx.cachedScopeLookup(member).filter { symbolID in
                        guard let symbol = ctx.cachedSymbol(symbolID),
                              symbol.kind == .property,
                              let declaredReceiver = sema.symbols.extensionPropertyReceiverType(for: symbolID)
                        else {
                            return false
                        }
                        return driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                            callSiteReceiver: nonNullReceiver,
                            declaredReceiver: declaredReceiver,
                            sema: sema
                        )
                    }
                    if let propertySymbol = extensionPropertyCandidates.first {
                        return bindPropertyCallableRef(
                            id,
                            propertySymbol: propertySymbol,
                            ownerType: unboundClassType != nil ? nonNullReceiver : nil,
                            isUnbound: unboundClassType != nil,
                            expectedType: expectedType,
                            sema: sema,
                            interner: interner
                        )
                    }
                }
                // A same-named non-extension function in a nearer scope must
                // not hide a legal receiver extension. Filter for applicable
                // extensions during scope lookup so only matching candidates
                // participate in shadowing. Keep member candidates above as
                // the higher-priority tier.
                candidates = ctx.scope.lookup(member, matching: { symbolID in
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
                    return driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                        callSiteReceiver: nonNullReceiver,
                        declaredReceiver: declaredReceiver,
                        sema: sema
                    )
                })
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
                    let nestedClass = sema.symbols.lookupAll(fqName: owner.fqName + [member])
                        .compactMap { ctx.cachedSymbol($0) }
                        .first { ($0.kind == .class || $0.kind == .enumClass) && !$0.flags.contains(.innerClass) }
                    if let nestedClass,
                       let ctorCandidates = visibleConstructorCandidates(of: nestedClass, ctx: ctx)
                    {
                        candidates = ctorCandidates
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
                let isMutable = sema.symbols.symbol(propertySymbol)?.flags.contains(.mutable) == true
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
            candidates = ctx.cachedScopeLookup(member).filter { symbolID in
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
            if candidates.isEmpty,
               let local = locals[member],
               let localSymbol = ctx.cachedSymbol(local.symbol),
               localSymbol.kind == .function,
               sema.symbols.functionSignature(for: local.symbol)?.receiverType == nil
            {
                candidates = [local.symbol]
            }
            // REFL-CTOR: a bare `::Foo` where `Foo` names a class/enum class
            // is a constructor reference `(Args...) -> Foo`. Constructors are
            // stored under the class's own FQ name with the reserved `<init>`
            // short name (HeaderHelpers.swift), not under `Foo` itself, so the
            // `.function || .constructor` scope lookup above never finds them
            // -- mirrors the KSP-CAP-006 class+ctor lookup CallTypeChecker.swift
            // uses for a direct call `Foo(...)`.
            if candidates.isEmpty {
                let classCandidates = ctx.cachedScopeLookup(member).filter { symbolID in
                    guard let symbol = ctx.cachedSymbol(symbolID) else { return false }
                    return symbol.kind == .class || symbol.kind == .enumClass
                }
                if let classSym = classCandidates.first,
                   let classSymbol = ctx.cachedSymbol(classSym),
                   let ctorCandidates = visibleConstructorCandidates(of: classSymbol, ctx: ctx)
                {
                    candidates = ctorCandidates
                    isConstructorReference = true
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
        }

        // For unbound type references (Type::member), the receiver is not
        // bound — it becomes a parameter of the function type.  For bound
        // references (obj::member), the receiver is captured. A constructor
        // reference has no receiver at all; see `isConstructorReference`'s
        // declaration above for why it is folded into the "bound" side here.
        let isBoundReceiver = (receiver != nil && unboundClassType == nil)
            || isConstructorReference || isImplicitlyBoundMember

        // BUG-164: callable references must also support SAM-conversion to a
        // functional interface expected type, the same way lambda literals do.
        let expectedFunctionType: TypeID?
        let expectedSamInterfaceType: TypeID?
        if let expectedType {
            if case .functionType = sema.types.kind(of: expectedType) {
                expectedFunctionType = expectedType
                expectedSamInterfaceType = nil
            } else if let functionType = sema.types.nominalFunctionType(for: expectedType) {
                expectedFunctionType = sema.types.make(.functionType(functionType))
                expectedSamInterfaceType = nil
            } else if let samFT = driver.helpers.samFunctionType(for: expectedType, sema: sema) {
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
                    diagnostics: ctx.semaCtx.diagnostics
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
        let boundReceiverType: TypeID? = if isImplicitlyBoundMember {
            implicitBoundReceiver?.type
        } else if receiver != nil && !isConstructorReference {
            effectiveReceiverType
        } else {
            nil
        }
        let chosen = driver.helpers.chooseCallableReferenceTarget(
            from: candidates,
            expectedType: expectedFunctionType,
            bindReceiver: isBoundReceiver,
            boundReceiverType: boundReceiverType,
            sema: sema
        )

        if let chosen,
           let signature = sema.symbols.functionSignature(for: chosen)
        {
            var inferredType = driver.helpers.callableFunctionType(
                for: signature,
                bindReceiver: isBoundReceiver,
                boundReceiver: boundReceiverType.map { (chosen, $0) },
                sema: sema
            )
            let resultType: TypeID
            // An expected type that still mentions type parameters belongs to a
            // generic signature whose type arguments are inferred from this very
            // argument (`fun <T> runCatching(block: () -> T)`). Checking against
            // it would fail, and adopting it would hide the concrete type the
            // caller needs for inference, so report the reference's own type.
            if let expectedFunctionType {
                let concreteResult = expectedSamInterfaceType ?? expectedFunctionType
                if !sema.types.typeContainsAnyTypeParam(concreteResult) {
                    if let specializedType = driver.helpers.contextualCallableFunctionType(
                        for: signature,
                        bindReceiver: isBoundReceiver,
                        boundReceiver: boundReceiverType.map { (chosen, $0) },
                        expectedFunctionType: expectedFunctionType,
                        sema: sema
                    ) {
                        inferredType = specializedType
                    } else {
                        ctx.semaCtx.diagnostics.error(
                            "KSWIFTK-TYPE-0001",
                            "Type constraint could not be satisfied.",
                            range: range
                        )
                    }
                    resultType = concreteResult
                } else {
                    resultType = inferredType
                }

            } else {
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
            sema.bindings.bindIdentifier(id, symbol: chosen)
            sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            // REFL-003: Tag the callable reference as KFunction so KIR
            // lowering can emit type identity metadata.
            sema.bindings.bindCallableRefKind(id, kind: .functionRef)
            if isImplicitlyBoundMember {
                sema.bindings.markImplicitReceiverMember(id, name: member)
                if let implicitBoundReceiver {
                    sema.bindings.markImplicitReceiverOuterReceiver(id, symbol: implicitBoundReceiver.symbol)
                }
            }
            if unboundClassType != nil && !isConstructorReference {
                sema.bindings.markUnboundCallableRef(id)
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
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0022",
                "Unresolved reference '::\(interner.resolve(member))'.",
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
            ctx.semaCtx.diagnostics.error(
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
            diagnostics: ctx.semaCtx.diagnostics
        )
        sema.bindings.bindPrimitiveOperatorCallableRef(id, op: op)
        sema.bindings.bindCallableRefKind(id, kind: .functionRef)
        sema.bindings.bindExprType(id, type: expectedType)
        return expectedType
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
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        var propertyType = sema.symbols.propertyType(for: propertySymbol) ?? sema.types.errorType
        if let ownerType, let owner = sema.symbols.parentSymbol(for: propertySymbol) {
            propertyType = driver.helpers.resolveMemberPropertyType(
                propertyType,
                receiverType: ownerType,
                ownerSymbol: owner,
                sema: sema
            )
        }
        let isMutable = sema.symbols.symbol(propertySymbol)?.flags.contains(.mutable) == true
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
              let samFunctionType = driver.helpers.samFunctionType(for: expectedType, sema: sema)
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

    /// Decides the expression type for a property callable reference.
    ///
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
        if let samFunctionType = driver.helpers.samFunctionType(for: expectedType, sema: sema) {
            // Same check against the SAM signature for a fun-interface
            // expected type (`useSam(C::v)`): adopt the interface type only
            // when the reference's function view matches the SAM.
            if !sema.types.typeContainsAnyTypeParam(expectedType),
               isConcreteKPropertyReferenceShape(inferredType, sema: sema, interner: interner),
               !sema.types.isSubtype(inferredType, sema.types.make(.functionType(samFunctionType)))
            {
                return inferredType
            }
            return expectedType
        }
        guard isConcreteKPropertyReferenceShape(expectedType, sema: sema, interner: interner) else {
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
}
