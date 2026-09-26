
final class DataEnumSealedSynthesisPass: LoweringPass {
    static let name = "DataEnumSealedSynthesis"
    static let requiredStage: KIRStage = .propertyLowered
    static let producedStage: KIRStage = .propertyLowered

    func run(module: KIRModule, ctx: KIRContext) throws {
        module.arena.transformFunctions { function in
            var updated = function
            if updated.body.isEmpty {
                updated.replaceBody([.nop, .returnUnit], locations: [nil, nil])
            }
            return updated
        }

        guard let sema = ctx.sema else {
            module.recordLowering(Self.name)
            return
        }

        appendReferencedBundledEnumNominalsIfNeeded(
            module: module,
            sema: sema,
            interner: ctx.interner
        )

        let intType = sema.types.make(.primitive(.int, .nonNull))
        let existingFunctionSymbols = Set(module.arena.declarations.compactMap { decl -> SymbolID? in
            guard case let .function(function) = decl else {
                return nil
            }
            return function.symbol
        })
        let nominalSymbols = module.arena.declarations.compactMap { decl -> SymbolID? in
            guard case let .nominalType(nominal) = decl else {
                return nil
            }
            return nominal.symbol
        }

        var enumStaticInitCallees: [(name: InternedString, symbol: SymbolID)] = []

        for nominalSymbolID in nominalSymbols {
            guard let nominalSymbol = sema.symbols.symbol(nominalSymbolID) else {
                continue
            }
            if nominalSymbol.kind == .enumClass {
                synthesizeEnumHelpers(
                    nominalSymbol: nominalSymbol, intType: intType,
                    module: module, sema: sema,
                    existingFunctionSymbols: existingFunctionSymbols, ctx: ctx
                )
                let entries = enumEntrySymbols(owner: nominalSymbol, symbols: sema.symbols)
                if !entries.isEmpty {
                    let initName = ctx.interner.intern("__enum_static_init_\(ctx.interner.resolve(nominalSymbol.name))")
                    if let initSymbol = sema.symbols.lookup(fqName: nominalSymbol.fqName + [initName]) {
                        enumStaticInitCallees.append((initName, initSymbol))
                    }
                }
            }
            if nominalSymbol.flags.contains(.sealedType) {
                synthesizeSealedHelper(
                    nominalSymbol: nominalSymbol, intType: intType,
                    module: module, sema: sema,
                    existingFunctionSymbols: existingFunctionSymbols, ctx: ctx
                )
            }
            if nominalSymbol.flags.contains(.dataType) {
                synthesizeDataHelpers(
                    nominalSymbol: nominalSymbol,
                    module: module, sema: sema,
                    existingFunctionSymbols: existingFunctionSymbols, ctx: ctx
                )
            }
        }

        // `__enum_static_init_<Class>` populates the global ordinal slots that
        // equality comparisons and `when` branches read back. Nothing else
        // ever calls it, so without this the globals stay at their
        // zero-initialized default and every entry of a given enum class
        // compares equal. Inject one call per enum class at the very start of
        // `main`, mirroring how top-level property/companion initializers are
        // threaded in by `postProcessTopLevelInitializersAndDelegates`.
        if !enumStaticInitCallees.isEmpty {
            let mainName = ctx.interner.intern("main")
            let unitType = sema.types.unitType
            module.arena.transformFunctions { function in
                guard function.name == mainName else {
                    return function
                }
                var initInstructions: [KIRInstruction] = []
                for callee in enumStaticInitCallees {
                    let result = module.arena.appendTemporary(type: unitType)
                    initInstructions.append(.call(
                        symbol: callee.symbol,
                        callee: callee.name,
                        arguments: [],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }
                var updated = function
                let initLocations = Array(repeating: SourceRange?.none, count: initInstructions.count)
                if let first = updated.body.first, case .beginBlock = first {
                    updated.replaceBody(
                        [first] + initInstructions + updated.body.dropFirst(),
                        locations: Array(updated.instructionLocations.prefix(1))
                            + initLocations
                            + updated.instructionLocations.dropFirst()
                    )
                } else {
                    updated.replaceBody(
                        initInstructions + updated.body,
                        locations: initLocations + updated.instructionLocations
                    )
                }
                return updated
            }
        }

        // Rewrite symbolRef references to synthetic enum entries (e.g.
        // RegexOption.DOT_MATCHES_ALL) into boxed ordinal int literals.
        // User-defined enum entries are backed by global variables, but
        // synthetic entries have no globals — so we inline the ordinal.
        rewriteSyntheticEnumEntryRefs(module: module, sema: sema)

        module.recordLowering(Self.name)
    }

    /// Describes a bundled enum nominal that is appended to consumer KIR only
    /// when referenced: where it lives in the bundled sources and which
    /// generated members count as a reference.
    private struct BundledEnumSpec {
        let pathSegments: [String]
        let requiresSourceBacked: Bool
        /// Member names looked up directly under the enum's fqName.
        let ownMemberNames: [String]
        /// Member names looked up under the companion object's fqName.
        let companionMemberNames: [String]
        /// Whether a typed expression of this enum type also counts as a reference.
        let checksExprTypes: Bool
    }

    /// A bundled enum resolved against `sema.symbols`, ready for membership
    /// checks during the combined binding scan.
    private struct BundledEnumProbe {
        let classSymbol: SymbolID
        let memberSymbols: Set<SymbolID>
        let checksExprTypes: Bool
    }

    /// Makes the bundled MemoryModel / OsFamily / KVariance / CpuArchitecture
    /// enum nominals visible to the shared enum synthesis pass when a consumer
    /// KIR references one of their generated APIs or the enum type itself.
    /// Bundled source declarations are omitted from consumer KIR, but their
    /// source-backed nominal identity is still required by enum helper bodies.
    /// A single combined pass over the binding maps records which enums are
    /// referenced instead of rescanning each map once per enum.
    private func appendReferencedBundledEnumNominalsIfNeeded(
        module: KIRModule,
        sema: SemaModule,
        interner: StringInterner
    ) {
        let specs: [BundledEnumSpec] = [
            BundledEnumSpec(
                pathSegments: ["kotlin", "native", "MemoryModel"],
                requiresSourceBacked: false,
                ownMemberNames: ["entries", "valueOf", "values"],
                companionMemberNames: [],
                checksExprTypes: false
            ),
            BundledEnumSpec(
                pathSegments: ["kotlin", "native", "OsFamily"],
                requiresSourceBacked: true,
                ownMemberNames: ["values"],
                companionMemberNames: ["entries", "valueOf"],
                checksExprTypes: true
            ),
            BundledEnumSpec(
                pathSegments: ["kotlin", "reflect", "KVariance"],
                requiresSourceBacked: true,
                ownMemberNames: ["values"],
                companionMemberNames: ["entries", "valueOf"],
                checksExprTypes: true
            ),
            BundledEnumSpec(
                pathSegments: ["kotlin", "native", "CpuArchitecture"],
                requiresSourceBacked: true,
                ownMemberNames: ["values"],
                companionMemberNames: ["entries", "valueOf"],
                checksExprTypes: true
            ),
        ]

        var probes: [BundledEnumProbe] = []
        for spec in specs {
            let enumFQName = spec.pathSegments.map { interner.intern($0) }
            guard let classSymbol = sema.symbols.lookup(fqName: enumFQName),
                  let classInfo = sema.symbols.symbol(classSymbol),
                  classInfo.kind == .enumClass,
                  !spec.requiresSourceBacked || sema.symbols.isSourceBackedSymbol(classSymbol)
            else {
                continue
            }

            var memberSymbols = Set(spec.ownMemberNames.flatMap { name in
                sema.symbols.lookupAll(fqName: enumFQName + [interner.intern(name)])
            })
            if let companionSymbol = sema.symbols.companionObjectSymbol(for: classSymbol),
               let companion = sema.symbols.symbol(companionSymbol)
            {
                memberSymbols.formUnion(spec.companionMemberNames.flatMap { name in
                    sema.symbols.lookupAll(fqName: companion.fqName + [interner.intern(name)])
                })
            }
            guard !memberSymbols.isEmpty else {
                continue
            }
            probes.append(BundledEnumProbe(
                classSymbol: classSymbol,
                memberSymbols: memberSymbols,
                checksExprTypes: spec.checksExprTypes
            ))
        }
        guard !probes.isEmpty else {
            return
        }

        var memberToProbes: [SymbolID: [Int]] = [:]
        for (index, probe) in probes.enumerated() {
            for member in probe.memberSymbols {
                memberToProbes[member, default: []].append(index)
            }
        }
        var classToProbes: [SymbolID: [Int]] = [:]
        for (index, probe) in probes.enumerated() where probe.checksExprTypes {
            classToProbes[probe.classSymbol, default: []].append(index)
        }

        var isReferenced = [Bool](repeating: false, count: probes.count)
        for symbol in sema.bindings.identifierSymbols.values {
            for index in memberToProbes[symbol] ?? [] {
                isReferenced[index] = true
            }
        }
        for binding in sema.bindings.callBindings.values {
            for index in memberToProbes[binding.chosenCallee] ?? [] {
                isReferenced[index] = true
            }
        }
        if !classToProbes.isEmpty {
            for type in sema.bindings.exprTypes.values {
                guard case let .classType(classType) = sema.types.kind(of: type) else {
                    continue
                }
                for index in classToProbes[classType.classSymbol] ?? [] {
                    isReferenced[index] = true
                }
            }
        }

        let declaredNominalSymbols = Set(module.arena.declarations.compactMap { declaration -> SymbolID? in
            guard case let .nominalType(nominal) = declaration else {
                return nil
            }
            return nominal.symbol
        })
        for (index, probe) in probes.enumerated() where isReferenced[index] {
            guard !declaredNominalSymbols.contains(probe.classSymbol) else {
                continue
            }
            _ = module.arena.appendDecl(.nominalType(KIRNominalType(symbol: probe.classSymbol)))
        }
    }

    /// Replaces `constValue(result: r, value: .symbolRef(sym))` where `sym`
    /// is a synthetic field owned by a synthetic enum class with
    /// `constValue(result: r, value: .intLiteral(ordinal))` followed by a
    /// `call kk_box_int` so the value is a boxed enum ordinal.
    private func rewriteSyntheticEnumEntryRefs(
        module: KIRModule,
        sema: SemaModule
    ) {
        // Build a lookup: syntheticEnumEntrySymbol -> ordinal.
        // Use `isSourceBackedSymbol` rather than the `synthetic` flag so that
        // real source-backed enum entries (including those imported from a
        // precompiled .kklib) keep their global-object symbolRef; only
        // compiler-synthesised enum entries (e.g. RegexOption.DOT_MATCHES_ALL)
        // are inlined as raw ordinals.
        var syntheticEntriesByParent: [[InternedString]: [SymbolID]] = [:]
        for sym in sema.symbols.allSymbols() {
            guard sym.kind == .field,
                  !sema.symbols.isSourceBackedSymbol(sym.id),
                  sym.fqName.count >= 2
            else {
                continue
            }
            syntheticEntriesByParent[Array(sym.fqName.dropLast()), default: []].append(sym.id)
        }

        var syntheticEntryOrdinal: [SymbolID: Int] = [:]
        for (parentFQ, entryIDs) in syntheticEntriesByParent {
            guard let parentSymbol = sema.symbols.lookup(fqName: parentFQ),
                  let parentInfo = sema.symbols.symbol(parentSymbol),
                  parentInfo.kind == .enumClass,
                  !sema.symbols.isSourceBackedSymbol(parentSymbol)
            else {
                continue
            }
            // Ordinal = index among all field children of the parent enum.
            // The sorted sibling list is computed once per enum, not per entry.
            let siblings = sema.symbols.children(ofFQName: parentFQ)
                .filter { id in
                    guard let s = sema.symbols.symbol(id) else { return false }
                    return s.kind == .field
                }
                .sorted(by: { $0.rawValue < $1.rawValue })
            let entrySet = Set(entryIDs)
            for (ordinal, sibling) in siblings.enumerated() where entrySet.contains(sibling) {
                syntheticEntryOrdinal[sibling] = ordinal
            }
        }
        guard !syntheticEntryOrdinal.isEmpty else { return }

        module.arena.transformFunctions { function in
            var newBody: [KIRInstruction] = []
            var changed = false
            for instruction in function.body {
                guard case let .constValue(result, .symbolRef(sym)) = instruction,
                      let ordinal = syntheticEntryOrdinal[sym]
                else {
                    newBody.append(instruction)
                    continue
                }
                changed = true
                // Replace the symbolRef with a raw ordinal int literal,
                // matching how all other enum synthesis paths represent entries.
                newBody.append(.constValue(result: result, value: .intLiteral(Int64(ordinal))))
            }
            if changed {
                var updated = function
                updated.replaceBody(newBody, locations: function.instructionLocations)
                return updated
            }
            return function
        }
    }

    private func synthesizeEnumHelpers(
        nominalSymbol: SemanticSymbol,
        intType: TypeID,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        ctx: KIRContext
    ) {
        let entries = enumEntrySymbols(owner: nominalSymbol, symbols: sema.symbols)
        let helperName = ctx.interner.intern("\(ctx.interner.resolve(nominalSymbol.name))$enumValuesCount")
        appendSyntheticCountFunctionIfNeeded(
            name: helperName, owner: nominalSymbol, value: Int64(entries.count),
            returnType: intType, module: module, sema: sema,
            existingFunctionSymbols: existingFunctionSymbols
        )
        let stringType = sema.types.stringType
        for (ordinal, entry) in entries.enumerated() {
            appendSyntheticCountFunctionIfNeeded(
                name: NameMangler.enumEntryOrdinalHelperName(for: entry, interner: ctx.interner),
                owner: nominalSymbol, value: Int64(ordinal),
                returnType: intType, module: module, sema: sema,
                existingFunctionSymbols: existingFunctionSymbols
            )
            appendSyntheticStringFunctionIfNeeded(
                name: NameMangler.enumEntryNameHelperName(for: entry, interner: ctx.interner),
                owner: nominalSymbol, value: entry.name,
                returnType: stringType, module: module, sema: sema,
                existingFunctionSymbols: existingFunctionSymbols
            )
        }
        appendSyntheticEnumValuesIfNeeded(
            name: ctx.interner.intern("values"), owner: nominalSymbol,
            entries: entries,
            module: module, sema: sema, existingFunctionSymbols: existingFunctionSymbols,
            interner: ctx.interner
        )
        appendSyntheticEnumOrdinalToNameIfNeeded(
            owner: nominalSymbol,
            entries: entries,
            module: module,
            sema: sema,
            existingFunctionSymbols: existingFunctionSymbols,
            interner: ctx.interner
        )
        appendSyntheticEnumEntryDispatchesIfNeeded(
            owner: nominalSymbol,
            entries: entries,
            module: module,
            sema: sema,
            existingFunctionSymbols: existingFunctionSymbols,
            interner: ctx.interner
        )
        // valueOf and entries live on the companion (Color.valueOf, Color.entries)
        let valueOfOwner: SemanticSymbol = if let companionSymbol = sema.symbols.companionObjectSymbol(for: nominalSymbol.id),
                                              let companionSym = sema.symbols.symbol(companionSymbol)
        {
            companionSym
        } else {
            nominalSymbol
        }
        appendSyntheticEnumEntriesGetterIfNeeded(
            owner: valueOfOwner,
            enumSymbol: nominalSymbol,
            entries: entries,
            module: module,
            sema: sema,
            existingFunctionSymbols: existingFunctionSymbols,
            interner: ctx.interner
        )
        appendSyntheticEnumValueOfIfNeeded(
            name: ctx.interner.intern("valueOf"),
            owner: valueOfOwner,
            enumName: nominalSymbol.fqName.map(ctx.interner.resolve).joined(separator: "."),
            enumType: sema.types.make(.classType(ClassType(
                classSymbol: nominalSymbol.id,
                args: [],
                nullability: .nonNull
            ))),
            entries: entries,
            module: module,
            sema: sema,
            existingFunctionSymbols: existingFunctionSymbols,
            interner: ctx.interner
        )
        appendSyntheticEnumStaticInitIfNeeded(
            owner: nominalSymbol,
            entries: entries,
            module: module,
            sema: sema,
            existingFunctionSymbols: existingFunctionSymbols,
            interner: ctx.interner
        )
    }

    private func synthesizeSealedHelper(
        nominalSymbol: SemanticSymbol,
        intType: TypeID,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        ctx: KIRContext
    ) {
        let subtypeCount = Int64(sema.symbols.directSubtypes(of: nominalSymbol.id).count)
        let helperName = ctx.interner.intern("\(ctx.interner.resolve(nominalSymbol.name))$sealedSubtypeCount")
        appendSyntheticCountFunctionIfNeeded(
            name: helperName, owner: nominalSymbol, value: subtypeCount,
            returnType: intType, module: module, sema: sema,
            existingFunctionSymbols: existingFunctionSymbols
        )
    }

    private func synthesizeDataHelpers(
        nominalSymbol: SemanticSymbol,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        ctx: KIRContext
    ) {
        let copyName = ctx.interner.intern("copy")
        let existingCopySymbol = sema.symbols.lookupAll(fqName: nominalSymbol.fqName + [copyName]).first {
            sema.symbols.symbol($0).map { $0.flags.contains(.synthetic) } ?? false
        }
        appendSyntheticDataCopyIfNeeded(
            name: copyName,
            owner: nominalSymbol, module: module, sema: sema,
            existingSymbol: existingCopySymbol,
            existingFunctionSymbols: existingFunctionSymbols, interner: ctx.interner,
            diagnostics: ctx.diagnostics
        )
        if nominalSymbol.kind == .class {
            let hashCodeName = ctx.interner.intern("hashCode")
            let existingHashCodeSymbol = sema.symbols.lookupAll(fqName: nominalSymbol.fqName + [hashCodeName]).first {
                sema.symbols.symbol($0).map { $0.flags.contains(.synthetic) } ?? false
            }
            appendSyntheticDataClassHashCodeIfNeeded(
                owner: nominalSymbol, existingSymbol: existingHashCodeSymbol,
                module: module, sema: sema,
                existingFunctionSymbols: existingFunctionSymbols, interner: ctx.interner
            )
        }
        synthesizeDataClassComponentN(
            nominalSymbol: nominalSymbol,
            module: module,
            sema: sema,
            existingFunctionSymbols: existingFunctionSymbols,
            ctx: ctx
        )
        let toStringName = ctx.interner.intern("toString")
        let existingToStringSymbol = sema.symbols.lookupAll(fqName: nominalSymbol.fqName + [toStringName]).first {
            sema.symbols.symbol($0).map { $0.flags.contains(.synthetic) } ?? false
        }
        let equalsName = ctx.interner.intern("equals")
        let existingEqualsSymbol = sema.symbols.lookupAll(fqName: nominalSymbol.fqName + [equalsName]).first {
            sema.symbols.symbol($0).map { $0.flags.contains(.synthetic) } ?? false
        }

        if nominalSymbol.kind == .object {
            appendSyntheticDataObjectToStringIfNeeded(
                name: toStringName, owner: nominalSymbol, objectName: nominalSymbol.name,
                existingSymbol: existingToStringSymbol, module: module, sema: sema,
                existingFunctionSymbols: existingFunctionSymbols, interner: ctx.interner
            )
            appendSyntheticDataObjectEqualsIfNeeded(
                owner: nominalSymbol, existingSymbol: existingEqualsSymbol,
                module: module, sema: sema,
                existingFunctionSymbols: existingFunctionSymbols, interner: ctx.interner
            )
        } else if nominalSymbol.kind == .class {
            let properties = dataClassPropertySymbols(owner: nominalSymbol, symbols: sema.symbols)
            appendSyntheticDataClassToStringIfNeeded(
                name: toStringName, owner: nominalSymbol, properties: properties,
                existingSymbol: existingToStringSymbol, module: module, sema: sema,
                existingFunctionSymbols: existingFunctionSymbols, interner: ctx.interner
            )
            appendSyntheticDataClassEqualsIfNeeded(
                owner: nominalSymbol, properties: properties,
                existingSymbol: existingEqualsSymbol, module: module, sema: sema,
                existingFunctionSymbols: existingFunctionSymbols, interner: ctx.interner
            )
        }
    }

    /// Returns the primary-constructor data properties of a data class, sorted by constructor order.
    private func dataClassPropertySymbols(owner: SemanticSymbol, symbols: SymbolTable) -> [SemanticSymbol] {
        let primaryConstructorParamNames: [InternedString] = primaryConstructorSymbol(owner: owner, symbols: symbols)
            .flatMap { constructor in
                symbols.functionSignature(for: constructor.id)?.valueParameterSymbols.compactMap { paramSymbol in
                    symbols.symbol(paramSymbol)?.name
                }
            } ?? []
        guard !primaryConstructorParamNames.isEmpty else {
            return []
        }

        let propertiesByName = Dictionary(
            symbols.children(ofFQName: owner.fqName)
                .compactMap { symbols.symbol($0) }
                .filter { $0.kind == .property && !$0.flags.contains(.synthetic) }
                .map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return primaryConstructorParamNames.compactMap { propertiesByName[$0] }
    }

    private func primaryConstructorSymbol(owner: SemanticSymbol, symbols: SymbolTable) -> SemanticSymbol? {
        symbols.children(ofFQName: owner.fqName)
            .compactMap { symbols.symbol($0) }
            .filter { $0.kind == .constructor }
            .min { lhs, rhs in
                let lhsOffset = lhs.declSite?.start.offset ?? Int.max
                let rhsOffset = rhs.declSite?.start.offset ?? Int.max
                if lhsOffset != rhsOffset {
                    return lhsOffset < rhsOffset
                }
                return lhs.id.rawValue < rhs.id.rawValue
            }
    }

    /// DATA-002 / STDLIB-090: Synthesizes `componentN()` KIR function bodies for data classes.
    /// Each componentN takes the receiver ($self) and returns the Nth constructor property
    /// by reading the corresponding field via `kk_array_get_inbounds`.
    private func synthesizeDataClassComponentN(
        nominalSymbol: SemanticSymbol,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        ctx: KIRContext
    ) {
        let interner = ctx.interner

        let componentSymbols = syntheticDataClassComponentSymbols(
            owner: nominalSymbol,
            sema: sema,
            interner: interner
        )

        guard !componentSymbols.isEmpty else { return }

        let propertySymbols = primaryConstructorPropertySymbols(
            owner: nominalSymbol,
            sema: sema
        )

        let layout = sema.symbols.nominalLayout(for: nominalSymbol.id)

        for (componentIndex, functionSymbol, signature) in componentSymbols {
            guard !existingFunctionSymbols.contains(functionSymbol) else { continue }

            let componentName = interner.intern("component\(componentIndex)")
            let returnType = signature.returnType
            let fqName = nominalSymbol.fqName + [componentName]
            let receiverType = signature.receiverType ?? sema.types.make(.classType(ClassType(
                classSymbol: nominalSymbol.id,
                args: [],
                nullability: .nonNull
            )))

            // Create receiver parameter ($self)
            let selfParamName = interner.intern("$self")
            let selfParamSymbol = sema.symbols.define(
                kind: .valueParameter,
                name: selfParamName,
                fqName: fqName + [selfParamName],
                declSite: nominalSymbol.declSite,
                visibility: .private,
                flags: [.synthetic]
            )
            let selfParam = KIRParameter(symbol: selfParamSymbol, type: receiverType)

            let selfRef = module.arena.appendExpr(.symbolRef(selfParamSymbol), type: receiverType)

            var body: [KIRInstruction] = []
            body.append(.constValue(result: selfRef, value: .symbolRef(selfParamSymbol)))

            let propertyIndex = componentIndex - 1 // 0-based
            let resultExpr = module.arena.appendTemporary(type: returnType
            )

            // Read the primary-constructor-backed field via layout offset.
            if let layout = layout,
               propertyIndex < propertySymbols.count,
               let propertySymbol = propertySymbols[propertyIndex]
            {
                let backingField = sema.symbols.backingFieldSymbol(for: propertySymbol.id) ?? propertySymbol.id
                if let fieldOffset = layout.fieldOffsets[backingField] ?? layout.fieldOffsets[propertySymbol.id] {
                    let offsetExpr = module.arena.appendExpr(
                        .intLiteral(Int64(fieldOffset)),
                        type: sema.types.make(.primitive(.int, .nonNull))
                    )
                    body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
                    body.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_array_get_inbounds"),
                        arguments: [selfRef, offsetExpr],
                        result: resultExpr,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    body.append(.returnValue(resultExpr))
                    appendSyntheticFunctionWithSymbol(
                        functionSymbol: functionSymbol,
                        name: componentName,
                        module: module,
                        sema: sema,
                        signature: signature,
                        params: [selfParam],
                        body: body
                    )
                    continue
                }
            }

            let nullOutThrown = module.arena.appendExpr(.null, type: sema.types.nullableAnyType)
            body.append(.constValue(result: nullOutThrown, value: .null))
            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_abort_unreachable"),
                arguments: [nullOutThrown],
                result: resultExpr,
                canThrow: false,
                thrownResult: nil
            ))
            body.append(.returnValue(resultExpr))

            appendSyntheticFunctionWithSymbol(
                functionSymbol: functionSymbol,
                name: componentName,
                module: module,
                sema: sema,
                signature: signature,
                params: [selfParam],
                body: body
            )
        }
    }

    private func syntheticDataClassComponentSymbols(
        owner: SemanticSymbol,
        sema: SemaModule,
        interner: StringInterner
    ) -> [(index: Int, symbolID: SymbolID, signature: FunctionSignature)] {
        sema.symbols.children(ofFQName: owner.fqName)
            .compactMap { childID -> (Int, SymbolID, FunctionSignature)? in
                guard let sym = sema.symbols.symbol(childID),
                      sym.kind == .function,
                      sym.flags.contains(.synthetic),
                      let signature = sema.symbols.functionSignature(for: childID),
                      signature.parameterTypes.isEmpty
                else {
                    return nil
                }

                let name = interner.resolve(sym.name)
                guard name.hasPrefix("component"),
                      let index = Int(name.dropFirst("component".count)),
                      index >= 1
                else {
                    return nil
                }

                return (index, childID, signature)
            }
            .sorted { lhs, rhs in
                if lhs.0 == rhs.0 {
                    return lhs.1.rawValue < rhs.1.rawValue
                }
                return lhs.0 < rhs.0
            }
    }

    func primaryConstructorPropertySymbols(
        owner: SemanticSymbol,
        sema: SemaModule
    ) -> [SemanticSymbol?] {
        let childProperties = sema.symbols.children(ofFQName: owner.fqName)
            .compactMap { childID -> SemanticSymbol? in
                guard let symbol = sema.symbols.symbol(childID), symbol.kind == .property else {
                    return nil
                }
                return symbol
            }
        let propertiesByName = Dictionary(uniqueKeysWithValues: childProperties.map { ($0.name, $0) })

        guard let primaryCtorSymbol = sema.symbols.children(ofFQName: owner.fqName)
            .compactMap({ childID -> SymbolID? in
                guard let symbol = sema.symbols.symbol(childID),
                      symbol.kind == .constructor,
                      symbol.declSite == owner.declSite
                else {
                    return nil
                }
                return childID
            })
            .first,
            let primaryCtorSignature = sema.symbols.functionSignature(for: primaryCtorSymbol)
        else {
            return []
        }

        return primaryCtorSignature.valueParameterSymbols.map { paramSymbol in
            guard let param = sema.symbols.symbol(paramSymbol) else {
                return nil
            }
            return propertiesByName[param.name]
        }
    }

    private func enumEntrySymbols(owner: SemanticSymbol, symbols: SymbolTable) -> [SemanticSymbol] {
        let fieldOffsets = symbols.nominalLayout(for: owner.id)?.fieldOffsets ?? [:]
        return symbols.children(ofFQName: owner.fqName)
            .compactMap { symbols.symbol($0) }
            .filter { $0.kind == .field }
            .sorted(by: {
                // Source-backed entries have precise declaration ranges.
                let lhsDeclOffset = $0.declSite?.start.offset
                let rhsDeclOffset = $1.declSite?.start.offset
                if let lhsDeclOffset, let rhsDeclOffset, lhsDeclOffset != rhsDeclOffset {
                    return lhsDeclOffset < rhsDeclOffset
                }
                if (lhsDeclOffset == nil) != (rhsDeclOffset == nil) {
                    return lhsDeclOffset != nil
                }
                // Imported library entries have no source declaration range;
                // their metadata field offsets preserve declaration order.
                let lhsFieldOffset = fieldOffsets[$0.id] ?? Int.max
                let rhsFieldOffset = fieldOffsets[$1.id] ?? Int.max
                if lhsFieldOffset != rhsFieldOffset {
                    return lhsFieldOffset < rhsFieldOffset
                }
                return $0.id.rawValue < $1.id.rawValue
            })
    }

    private func appendSyntheticCountFunctionIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        value: Int64,
        returnType: TypeID,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>
    ) {
        let signature = FunctionSignature(parameterTypes: [], returnType: returnType, isSuspend: false)
        let resultExpr = module.arena.appendTemporary(type: returnType
        )
        let body: [KIRInstruction] = [
            .constValue(result: resultExpr, value: .intLiteral(value)),
            .returnValue(resultExpr),
        ]
        appendSyntheticFunctionIfNeeded(
            name: name,
            owner: owner,
            module: module,
            sema: sema,
            signature: signature,
            params: [],
            body: body,
            existingFunctionSymbols: existingFunctionSymbols
        )
    }

    private func appendSyntheticStringFunctionIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        value: InternedString,
        returnType: TypeID,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>
    ) {
        let signature = FunctionSignature(parameterTypes: [], returnType: returnType, isSuspend: false)
        let resultExpr = module.arena.appendTemporary(type: returnType
        )
        let body: [KIRInstruction] = [
            .constValue(result: resultExpr, value: .stringLiteral(value)),
            .returnValue(resultExpr),
        ]
        appendSyntheticFunctionIfNeeded(
            name: name,
            owner: owner,
            module: module,
            sema: sema,
            signature: signature,
            params: [],
            body: body,
            existingFunctionSymbols: existingFunctionSymbols
        )
    }

    /// Synthesizes `values()` which returns an `Array<T>` containing all
    func appendSyntheticFunctionWithSymbol(
        functionSymbol: SymbolID,
        name: InternedString,
        module: KIRModule,
        sema: SemaModule,
        signature: FunctionSignature,
        params: [KIRParameter],
        body: [KIRInstruction]
    ) {
        // Preserve the generic receiver contract collected for source-backed data
        // class members when the lowering body is synthesized with erased KIR types.
        let effectiveSignature: FunctionSignature = if
            signature.classTypeParameterCount == 0,
            let existingSignature = sema.symbols.functionSignature(for: functionSymbol),
            existingSignature.classTypeParameterCount > 0
        {
            FunctionSignature(
                receiverType: existingSignature.receiverType,
                parameterTypes: signature.parameterTypes,
                returnType: existingSignature.returnType,
                isSuspend: signature.isSuspend,
                canThrow: signature.canThrow,
                valueParameterSymbols: signature.valueParameterSymbols,
                valueParameterHasDefaultValues: signature.valueParameterHasDefaultValues,
                valueParameterIsVararg: signature.valueParameterIsVararg,
                valueParameterAllowsNonLocalReturn: signature.valueParameterAllowsNonLocalReturn,
                typeParameterSymbols: existingSignature.typeParameterSymbols,
                reifiedTypeParameterIndices: existingSignature.reifiedTypeParameterIndices,
                typeParameterUpperBounds: existingSignature.typeParameterUpperBounds,
                typeParameterUpperBoundsList: existingSignature.typeParameterUpperBoundsList,
                classTypeParameterCount: existingSignature.classTypeParameterCount
            )
        } else {
            signature
        }
        sema.symbols.setFunctionSignature(effectiveSignature, for: functionSymbol)
        _ = module.arena.appendDecl(.function(
            KIRFunction(
                symbol: functionSymbol,
                name: name,
                params: params,
                returnType: effectiveSignature.returnType,
                body: body,
                isSuspend: false,
                isInline: false
            )
        ))
    }

    func appendSyntheticFunctionIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        module: KIRModule,
        sema: SemaModule,
        signature: FunctionSignature,
        params: [KIRParameter],
        body: [KIRInstruction],
        existingFunctionSymbols: Set<SymbolID>
    ) {
        let fqName = owner.fqName + [name]
        let nonSyntheticConflict = sema.symbols.lookupAll(fqName: fqName).contains { symbolID in
            guard let symbol = sema.symbols.symbol(symbolID) else {
                return false
            }
            return symbol.kind == .function && !symbol.flags.contains(.synthetic)
        }
        if nonSyntheticConflict {
            return
        }

        let functionSymbol = sema.symbols.define(
            kind: .function,
            name: name,
            fqName: fqName,
            declSite: owner.declSite,
            visibility: .public,
            flags: [.synthetic, .static]
        )
        sema.symbols.setParentSymbol(owner.id, for: functionSymbol)
        if existingFunctionSymbols.contains(functionSymbol) {
            return
        }
        sema.symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: signature.receiverType,
                parameterTypes: signature.parameterTypes,
                returnType: signature.returnType,
                isSuspend: signature.isSuspend,
                valueParameterSymbols: params.map(\.symbol),
                valueParameterHasDefaultValues: signature.valueParameterHasDefaultValues.isEmpty
                    ? params.map { _ in false }
                    : signature.valueParameterHasDefaultValues,
                valueParameterIsVararg: signature.valueParameterIsVararg.isEmpty
                    ? params.map { _ in false }
                    : signature.valueParameterIsVararg,
                valueParameterAllowsNonLocalReturn: signature.valueParameterAllowsNonLocalReturn.isEmpty
                    ? params.map { _ in true }
                    : signature.valueParameterAllowsNonLocalReturn,
                typeParameterSymbols: []
            ),
            for: functionSymbol
        )
        _ = module.arena.appendDecl(.function(
            KIRFunction(
                symbol: functionSymbol,
                name: name,
                params: params,
                returnType: signature.returnType,
                body: body,
                isSuspend: false,
                isInline: false
            )
        ))
    }
}
