import Foundation

// MARK: - MetadataEncoder (Export)

/// Encodes compiler symbols into `[MetadataRecord]` and serializes them to the text-based
/// metadata format consumed by `MetadataDecoder`.
package final class MetadataEncoder {
    package init() {}

    /// Build metadata records from the compiler's semantic state.
    /// Public and protected declarations form the cross-module API;
    /// `includeNonPublic` additionally includes internal and private declarations.
    package func buildRecords(
        symbols: SymbolTable,
        types: TypeSystem,
        moduleName: String,
        interner: StringInterner,
        functionLinkNames: [SymbolID: String],
        inlineFunctionSymbols: Set<SymbolID> = [],
        includeNonPublic: Bool = false,
        includeSynthetic: Bool = true,
        includeSyntheticNominalAnchors: Bool = false,
        excludeSourceFileIDs: Set<Int32> = [],
        runtimeCallbackRawReturnSymbolIDs: Set<SymbolID> = [],
        objectInitializerLinkNames: [SymbolID: String] = [:],
        companionInitializerLinkNames: [SymbolID: String] = [:],
        objectLazyInitializerLinkNames: [SymbolID: String] = [:],
        enumStaticInitLinkNames: [SymbolID: String] = [:]
    ) -> [MetadataRecord] {
        let exported = symbols.allSymbols()
            .filter { symbol in
                if !includeNonPublic && symbol.visibility != .public && symbol.visibility != .protected {
                    return false
                }
                // KSP-626: `componentN`/`copy`/`equals`/`hashCode`/`toString` of a
                // source-backed data class are synthesized symbols, but they are part of
                // the class's public surface and are compiled into the artifact. Without
                // them consumers cannot destructure or compare an imported data class.
                let keepAsDataClassMember = !includeSynthetic
                    && Self.isSourceBackedDataClassMember(
                        symbol.id,
                        symbols: symbols,
                        excludedSourceFileIDs: excludeSourceFileIDs
                    )
                let keepAsEnumClassMember = !includeSynthetic
                    && Self.isSourceBackedEnumClassMember(
                        symbol.id,
                        symbols: symbols,
                        excludedSourceFileIDs: excludeSourceFileIDs,
                        allowShellBackedEnum: Self.isPublicImplicitEnumClassHelper(
                            symbol,
                            interner: interner
                        )
                    )
                // `$enumConstructorProperty$` helpers are lowered synthesized
                // functions, but they are the only representation of an enum
                // constructor-property read and their object code is already
                // compiled into the artifact. Consumers cannot re-synthesize
                // them (no AST), so they must be exported like enum API
                // members even when the owning enum reuses a synthetic shell.
                let keepAsEnumCtorPropHelper = !includeSynthetic
                    && symbol.kind == .function
                    && (interner.resolve(symbol.name).hasPrefix("$enumConstructorProperty$")
                        || interner.resolve(symbol.name).hasPrefix("$enumPropertySetter$"))
                    && Self.isSourceBackedEnumClassMember(
                        symbol.id,
                        symbols: symbols,
                        excludedSourceFileIDs: excludeSourceFileIDs,
                        allowShellBackedEnum: true
                    )
                if !includeSynthetic && symbol.flags.contains(.synthetic) && !keepAsDataClassMember && !keepAsEnumClassMember && !keepAsEnumCtorPropHelper {
                    let keepAsSyntheticNominalAnchor = includeSyntheticNominalAnchors && Self.nominalKinds.contains(symbol.kind)
                    let keepAsSyntheticTypeAlias = includeSyntheticNominalAnchors && symbol.kind == .typeAlias
                    if !(keepAsSyntheticNominalAnchor || keepAsSyntheticTypeAlias) {
                        return false
                    }
                    // STDLIB-SHARED-012: Top-level synthetic classes generated during
                    // lowering (e.g. SAM wrappers like `kk_sam_wrapper_*`) are not part
                    // of the stdlib surface and must not survive into the artifact.
                    if keepAsSyntheticNominalAnchor, symbol.fqName.count <= 1 {
                        return false
                    }
                }
                // STDLIB-SHARED-011: When synthetic functions are excluded, their child
                // type/value parameters must also be excluded. Otherwise metadata leaks
                // orphaned records like `List.toMap.K` that become spurious package
                // symbols on the consumer side and block synthetic member re-registration.
                // Source-backed declarations (e.g. bundled stdlib functions under a
                // synthetic package stub) are still exported; only synthesized helpers
                // without a source declSite are pruned by parent synthetics.
                if !includeSynthetic, symbol.declSite == nil, !keepAsDataClassMember, !keepAsEnumClassMember {
                    var parentID = symbols.parentSymbol(for: symbol.id)
                    while let p = parentID, let parent = symbols.symbol(p) {
                        if parent.flags.contains(.synthetic) {
                            let keepAsSyntheticNominalAnchor = includeSyntheticNominalAnchors && Self.nominalKinds.contains(parent.kind)
                            let keepAsSyntheticTypeAlias = includeSyntheticNominalAnchors && parent.kind == .typeAlias
                            if !(keepAsSyntheticNominalAnchor || keepAsSyntheticTypeAlias) {
                                return false
                            }
                        }
                        parentID = symbols.parentSymbol(for: p)
                    }
                }
                if symbol.kind == .package {
                    return !symbols.annotations(for: symbol.id).isEmpty
                }
                // KSP-911: ULongArray(LongArray) is an internal storage
                // constructor. Keep it in the stdlib object for source-backed
                // implementation calls, but do not export it to consumers.
                if includeNonPublic,
                   symbol.kind == .function,
                   symbol.fqName.map({ interner.resolve($0) }) == ["kotlin", "ULongArray"],
                   symbols.functionSignature(for: symbol.id)?.parameterTypes.count == 1
                {
                    return false
                }
                // KSP-908: UIntArray(IntArray) is an internal storage
                // constructor. It must remain in the stdlib object for
                // source-backed implementation calls, but must not be
                // imported as a public overload by consumer modules.
                if includeNonPublic,
                   symbol.kind == .function,
                   symbol.fqName.map({ interner.resolve($0) }) == ["kotlin", "UIntArray"],
                   symbols.functionSignature(for: symbol.id)?.parameterTypes.count == 1
                {
                    return false
                }
                // KSP-1089: AtomicIntArray(IntArray) is an internal storage
                // constructor. Keep it in the stdlib object for the public
                // initializer factory, but do not export it to consumers.
                if includeNonPublic,
                   symbol.kind == .function,
                   symbol.visibility != .public,
                   symbol.fqName.map({ interner.resolve($0) }) == ["kotlin", "concurrent", "AtomicIntArray"],
                   symbols.functionSignature(for: symbol.id)?.parameterTypes.count == 1
                {
                    return false
                }
                // KSP-1093: AtomicLongArray(LongArray) is an internal storage
                // constructor. Keep it in the stdlib object for the public
                // initializer factory, but do not export it to consumers.
                if includeNonPublic,
                   symbol.kind == .function,
                   symbol.visibility != .public,
                   symbol.fqName.map({ interner.resolve($0) }) == ["kotlin", "concurrent", "AtomicLongArray"],
                   symbols.functionSignature(for: symbol.id)?.parameterTypes.count == 1
                {
                    return false
                }
                // STDLIB-SHARED-016: Compiler-generated enum static helpers
                // (values/valueOf/entries) for non-public enum classes are not part
                // of the stdlib surface and cannot be resolved on the consumer side.
                if isNonPublicEnumStaticHelper(symbolID: symbol.id, symbols: symbols, interner: interner) {
                    return false
                }
                // Exclude symbols declared in bundled stdlib virtual files (e.g. __bundled_*.kt).
                // These are compiler internals and are always re-injected on every compilation.
                // Source-backed nominal types that reuse a synthetic shell carry a sourceFileID
                // but leave declSite nil, so also filter by the tracked source file ID.
                if let declSite = symbol.declSite, excludeSourceFileIDs.contains(declSite.start.file.rawValue) {
                    return false
                }
                if let sourceFileID = symbols.sourceFileID(for: symbol.id), excludeSourceFileIDs.contains(sourceFileID.rawValue) {
                    return false
                }
                return true
            }
            .map { (symbol: $0, resolvedFQName: $0.fqName.map { interner.resolve($0) }) }
            .sorted { lhs, rhs in
                if lhs.resolvedFQName.count != rhs.resolvedFQName.count {
                    return lhs.resolvedFQName.count < rhs.resolvedFQName.count
                }
                if lhs.resolvedFQName != rhs.resolvedFQName {
                    return lhs.resolvedFQName.lexicographicallyPrecedes(rhs.resolvedFQName)
                }
                return lhs.symbol.id.rawValue < rhs.symbol.id.rawValue
            }
            .map { $0.symbol }

        let exportedSymbolIDs = Set(exported.map(\.id))
        var records: [MetadataRecord] = []
        for symbol in exported {
            let isSyntheticNominalAnchor = !includeSynthetic
                && includeSyntheticNominalAnchors
                && symbol.flags.contains(.synthetic)
                && Self.nominalKinds.contains(symbol.kind)
            let built = buildRecord(
                for: symbol,
                symbols: symbols,
                types: types,
                moduleName: moduleName,
                interner: interner,
                functionLinkNames: functionLinkNames,
                inlineFunctionSymbols: inlineFunctionSymbols,
                metadataAnchorOnly: isSyntheticNominalAnchor,
                runtimeCallbackRawReturnSymbolIDs: runtimeCallbackRawReturnSymbolIDs,
                includedSymbolIDs: exportedSymbolIDs,
                objectInitializerLinkNames: objectInitializerLinkNames,
                companionInitializerLinkNames: companionInitializerLinkNames,
                objectLazyInitializerLinkNames: objectLazyInitializerLinkNames,
                enumStaticInitLinkNames: enumStaticInitLinkNames
            )
            records.append(built)
        }
        return records
    }

    /// Encodes the generic shape of a nominal declaration so consumers can
    /// rebuild it: the declaration's own type parameters (with declared
    /// variance) and the type arguments it passes to each generic direct
    /// supertype. Without these, an imported `class Sub<T> : Base<T>` looks
    /// like a raw `Sub` / `Base` pair and `Sub<Int>` no longer lifts to
    /// `Base<Int>`.
    private func nominalGenericSignatures(
        symbol: SemanticSymbol,
        symbols: SymbolTable,
        types: TypeSystem,
        mangler: NameMangler,
        interner: StringInterner
    ) -> (selfSignature: String?, supertypeSignatures: [String]) {
        let encode: ([TypeArg], SymbolID) -> String = { args, classSymbol in
            self.metadataTypeSignature(
                types.make(.classType(ClassType(classSymbol: classSymbol, args: args, nullability: .nonNull))),
                symbols: symbols,
                types: types,
                mangler: mangler,
                nameResolver: { interner.resolve($0) }
            )
        }
        let typeParameterSymbols = types.nominalTypeParameterSymbols(for: symbol.id)
        let selfSignature: String?
        if !typeParameterSymbols.isEmpty {
            let variances = types.nominalTypeParameterVariances(for: symbol.id)
            let selfArgs: [TypeArg] = typeParameterSymbols.enumerated().map { index, parameterSymbol in
                let parameterType = types.make(.typeParam(TypeParamType(symbol: parameterSymbol, nullability: .nonNull)))
                switch index < variances.count ? variances[index] : .invariant {
                case .out: return .out(parameterType)
                case .in: return .in(parameterType)
                case .invariant: return .invariant(parameterType)
                }
            }
            selfSignature = encode(selfArgs, symbol.id)
        } else {
            selfSignature = nil
        }
        let supertypeSignatures: [String] = symbols.directSupertypes(for: symbol.id).compactMap { superSymbol in
            let superArgs = types.nominalSupertypeTypeArgs(for: symbol.id, supertype: superSymbol)
            guard !superArgs.isEmpty else { return nil }
            return encode(superArgs, superSymbol)
        }
        return (selfSignature, supertypeSignatures)
    }

    private func metadataTypeSignature(
        _ type: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        mangler: NameMangler,
        nameResolver: ((InternedString) -> String)?
    ) -> String {
        let expandedType = expandMetadataTypeAliases(
            in: type,
            symbols: symbols,
            types: types
        )
        return mangler.encodeType(
            expandedType,
            symbols: symbols,
            types: types,
            nameResolver: nameResolver,
            unboxValueClasses: false
        )
    }

    private func expandMetadataTypeAliases(
        in type: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        seenAliases: Set<SymbolID> = []
    ) -> TypeID {
        switch types.kind(of: type) {
        case let .classType(classType):
            guard let symbol = symbols.symbol(classType.classSymbol),
                  symbol.kind == .typeAlias,
                  !seenAliases.contains(classType.classSymbol),
                  let underlying = symbols.typeAliasUnderlyingType(for: classType.classSymbol)
            else {
                let expandedArgs = classType.args.map {
                    expandMetadataTypeAliasArg($0, symbols: symbols, types: types, seenAliases: seenAliases)
                }
                if expandedArgs == classType.args {
                    return type
                }
                return types.make(.classType(ClassType(
                    classSymbol: classType.classSymbol,
                    args: expandedArgs,
                    nullability: classType.nullability
                )))
            }

            let aliasTypeParams = symbols.typeAliasTypeParameters(for: classType.classSymbol)
            let typeVarBySymbol = types.makeTypeVarBySymbol(aliasTypeParams)
            var substitution: [TypeVarID: TypeID] = [:]
            for (index, typeParamSymbol) in aliasTypeParams.enumerated() {
                guard index < classType.args.count,
                      let typeVar = typeVarBySymbol[typeParamSymbol]
                else {
                    continue
                }
                substitution[typeVar] = expandMetadataTypeAliasValue(
                    classType.args[index],
                    symbols: symbols,
                    types: types,
                    seenAliases: seenAliases
                )
            }

            let substituted = types.substituteTypeParameters(
                in: underlying,
                substitution: substitution,
                typeVarBySymbol: typeVarBySymbol
            )
            let expandedUnderlying = expandMetadataTypeAliases(
                in: substituted,
                symbols: symbols,
                types: types,
                seenAliases: seenAliases.union([classType.classSymbol])
            )
            if classType.nullability == .nullable {
                return types.makeNullable(expandedUnderlying)
            }
            return expandedUnderlying

        case let .functionType(functionType):
            let newContextReceivers = functionType.contextReceivers.map {
                expandMetadataTypeAliases(in: $0, symbols: symbols, types: types, seenAliases: seenAliases)
            }
            let newReceiver = functionType.receiver.map {
                expandMetadataTypeAliases(in: $0, symbols: symbols, types: types, seenAliases: seenAliases)
            }
            let newParams = functionType.params.map {
                expandMetadataTypeAliases(in: $0, symbols: symbols, types: types, seenAliases: seenAliases)
            }
            let newReturn = expandMetadataTypeAliases(
                in: functionType.returnType,
                symbols: symbols,
                types: types,
                seenAliases: seenAliases
            )
            if newContextReceivers == functionType.contextReceivers,
               newReceiver == functionType.receiver,
               newParams == functionType.params,
               newReturn == functionType.returnType
            {
                return type
            }
            return types.make(.functionType(FunctionType(
                contextReceivers: newContextReceivers,
                receiver: newReceiver,
                params: newParams,
                returnType: newReturn,
                isSuspend: functionType.isSuspend,
                isCallableReference: functionType.isCallableReference,
                nullability: functionType.nullability
            )))

        case let .intersection(parts):
            let expandedParts = parts.map {
                expandMetadataTypeAliases(in: $0, symbols: symbols, types: types, seenAliases: seenAliases)
            }
            if expandedParts == parts {
                return type
            }
            return types.make(.intersection(expandedParts))

        case let .kClassType(kClassType):
            let expandedArgument = expandMetadataTypeAliases(
                in: kClassType.argument,
                symbols: symbols,
                types: types,
                seenAliases: seenAliases
            )
            if expandedArgument == kClassType.argument {
                return type
            }
            return types.make(.kClassType(KClassType(
                argument: expandedArgument,
                nullability: kClassType.nullability
            )))

        case .typeParam, .stringStruct, .primitive, .any, .unit, .nullableUnit, .nothing, .error:
            return type
        }
    }

    private func expandMetadataTypeAliasArg(
        _ arg: TypeArg,
        symbols: SymbolTable,
        types: TypeSystem,
        seenAliases: Set<SymbolID>
    ) -> TypeArg {
        switch arg {
        case let .invariant(inner):
            .invariant(expandMetadataTypeAliases(in: inner, symbols: symbols, types: types, seenAliases: seenAliases))
        case let .out(inner):
            .out(expandMetadataTypeAliases(in: inner, symbols: symbols, types: types, seenAliases: seenAliases))
        case let .in(inner):
            .in(expandMetadataTypeAliases(in: inner, symbols: symbols, types: types, seenAliases: seenAliases))
        case .star:
            .star
        }
    }

    private func expandMetadataTypeAliasValue(
        _ arg: TypeArg,
        symbols: SymbolTable,
        types: TypeSystem,
        seenAliases: Set<SymbolID>
    ) -> TypeID {
        switch arg {
        case let .invariant(inner):
            expandMetadataTypeAliases(in: inner, symbols: symbols, types: types, seenAliases: seenAliases)
        case let .out(inner):
            expandMetadataTypeAliases(in: inner, symbols: symbols, types: types, seenAliases: seenAliases)
        case let .in(inner):
            expandMetadataTypeAliases(in: inner, symbols: symbols, types: types, seenAliases: seenAliases)
        case .star:
            types.nullableAnyType
        }
    }

    func buildRecord(
        for symbol: SemanticSymbol,
        symbols: SymbolTable,
        types: TypeSystem,
        moduleName: String,
        interner: StringInterner,
        functionLinkNames: [SymbolID: String] = [:],
        inlineFunctionSymbols: Set<SymbolID> = [],
        metadataAnchorOnly: Bool = false,
        runtimeCallbackRawReturnSymbolIDs: Set<SymbolID> = [],
        includedSymbolIDs: Set<SymbolID>? = nil,
        objectInitializerLinkNames: [SymbolID: String] = [:],
        companionInitializerLinkNames: [SymbolID: String] = [:],
        objectLazyInitializerLinkNames: [SymbolID: String] = [:],
        enumStaticInitLinkNames: [SymbolID: String] = [:]
    ) -> MetadataRecord {
        let mangler = NameMangler()
        let mangled = mangler.mangle(
            moduleName: moduleName,
            symbol: symbol,
            symbols: symbols,
            types: types,
            nameResolver: { interner.resolve($0) }
        )
        let fqName = symbol.fqName.map { interner.resolve($0) }.joined(separator: ".")

        // STDLIB-SHARED-014: Direct supertype FQ names are needed even for
        // synthetic nominal anchors (e.g. List, Iterable) so that consumers
        // can walk the type hierarchy during member-call fallback resolution.
        let computedSuperFQName: String? = {
            guard Self.nominalKinds.contains(symbol.kind) else { return nil }
            let directSupertypeSymbols = symbols.directSupertypes(for: symbol.id)
            let superFQNames = directSupertypeSymbols.compactMap { superSymbolID in
                symbols.symbol(superSymbolID)?.fqName.map { interner.resolve($0) }.joined(separator: ".")
            }
            return superFQNames.isEmpty ? nil : superFQNames.joined(separator: ",")
        }()

        let valueClassUnderlyingTypeSig: String?
        if symbol.flags.contains(.valueType),
           let underlyingType = symbols.valueClassUnderlyingType(for: symbol.id)
        {
            valueClassUnderlyingTypeSig = mangler.encodeType(
                underlyingType,
                symbols: symbols,
                types: types,
                nameResolver: { interner.resolve($0) }
            )
        } else {
            valueClassUnderlyingTypeSig = nil
        }

        if metadataAnchorOnly {
            // Synthetic nominal anchors need their declared layout sizes as
            // consumer-side synthesis hints. Do not serialize partial slot maps:
            // their synthetic members are intentionally not exported and are
            // re-registered by the consumer. Keeping only an inherited itable
            // entry would install an incomplete layout and prevent synthesis from
            // assigning slots to those re-registered members.
            if Self.nominalKinds.contains(symbol.kind), let layout = symbols.nominalLayout(for: symbol.id) {
                return MetadataRecord(
                    kind: symbol.kind,
                    visibility: symbol.visibility,
                    mangledName: mangled,
                    fqName: fqName,
                    declaredFieldCount: layout.instanceFieldCount,
                    declaredInstanceSizeWords: layout.instanceSizeWords,
                    declaredVtableSize: layout.vtableSize,
                    declaredItableSize: layout.itableSize,
                    superFQName: computedSuperFQName,
                    isDataClass: symbol.flags.contains(.dataType),
                    isOpenClass: symbol.flags.contains(.openType),
                    modality: symbol.flags.contains(.abstractType)
                        ? .abstract
                        : (symbol.flags.contains(.openType) ? .open : .final),
                    isSealedClass: symbol.flags.contains(.sealedType),
                    isFunInterface: symbol.flags.contains(.funInterface),
                    isValueClass: symbol.flags.contains(.valueType),
                    valueClassUnderlyingTypeSig: valueClassUnderlyingTypeSig,
                    isExpect: symbol.flags.contains(.expectDeclaration),
                    isActual: symbol.flags.contains(.actualDeclaration)
                )
            }
            return MetadataRecord(
                kind: symbol.kind,
                visibility: symbol.visibility,
                mangledName: mangled,
                fqName: fqName,
                superFQName: computedSuperFQName,
                isDataClass: symbol.flags.contains(.dataType),
                isOpenClass: symbol.flags.contains(.openType),
                modality: symbol.flags.contains(.abstractType)
                    ? .abstract
                    : (symbol.flags.contains(.openType) ? .open : .final),
                isSealedClass: symbol.flags.contains(.sealedType),
                isFunInterface: symbol.flags.contains(.funInterface),
                isValueClass: symbol.flags.contains(.valueType),
                valueClassUnderlyingTypeSig: valueClassUnderlyingTypeSig,
                isExpect: symbol.flags.contains(.expectDeclaration),
                isActual: symbol.flags.contains(.actualDeclaration)
            )
        }

        var arity = 0
        var isSuspend = false
        var isInline = false
        var isOperator = false
        var isInfix = false
        var isOverride = false
        var receiverOwnerFQName: String?
        var typeSignature: String?
        var typeParameterUpperBoundsSignatures: [[String]] = []
        var callableTypeParameterSignatures: [String] = []
        var inputOnlyTypeParameterIndices: Set<Int> = []
        var valueParameterIsVararg: [Bool] = []
        var valueParameterAllowsNonLocalReturn: [Bool] = []
        var valueParameterHasDefaultValues: [Bool] = []
        var valueParameterCallsInPlaceKinds: [InvocationKind?] = []
        var canThrow = false
        var valueParameterNames: [String] = []
        var reifiedTypeParameterIndices: Set<Int> = []
        var defaultStubExternalLinkName: String?
        var externalLinkName = symbols.externalLinkName(for: symbol.id)
        var abiReturnTypeSignature: String?

        if symbol.kind == .function || symbol.kind == .constructor, let signature = symbols.functionSignature(for: symbol.id) {
            arity = signature.parameterTypes.count
            isSuspend = signature.isSuspend
            // Only mark a record as inline when an actual inline KIR body was emitted.
            // Source flags may be set for runtime-backed synthetic functions that have
            // no KIR body, and those must not try to load a missing inline-kir file.
            isInline = inlineFunctionSymbols.contains(symbol.id)
            isOperator = symbol.flags.contains(.operatorFunction)
            isInfix = symbol.flags.contains(.infixFunction)
            isOverride = symbol.flags.contains(.overrideMember)
            valueParameterIsVararg = signature.valueParameterIsVararg
            let callsInPlaceEffects = symbols.contractCallsInPlaceEffects(for: symbol.id)
            if !callsInPlaceEffects.isEmpty {
                valueParameterCallsInPlaceKinds = signature.valueParameterSymbols.map { paramSymbol in
                    callsInPlaceEffects.first { $0.parameterSymbol == paramSymbol }?.kind
                }
            }
            // Auto-inlined HOF bodies still have ordinary Kotlin parameters:
            // their callbacks may escape and must retain their closure values.
            valueParameterAllowsNonLocalReturn = symbol.flags.contains(.inlineFunction)
                ? signature.valueParameterAllowsNonLocalReturn
                : Array(repeating: false, count: signature.parameterTypes.count)
            // KUU-655: an override with an inheritance link
            // (`overrideDefaultsBaseSymbol`) has its *effective* defaults
            // flags copied from the overridden declaration in-memory
            // (`OverrideDefaultArgumentInheritance`), but never gets a
            // `$default` stub of its own -- only the base declaration does.
            // Serializing the effective (true) flags here without a stub
            // link would make a separately-compiled consumer believe this
            // symbol owns a stub that was never emitted. Serialize this
            // override's own (pre-inheritance) flags instead, exactly as if
            // it had been compiled without this fix; the consumer's own
            // `OverrideDefaultArgumentInheritance` pass re-derives the same
            // link independently once it sees the (faithfully serialized)
            // base declaration's defaults and the supertype/parent edges
            // `LibraryImport` already restores.
            let hasInheritedDefaultsLink = symbols.overrideDefaultsBaseSymbol(for: symbol.id) != nil
            valueParameterHasDefaultValues = hasInheritedDefaultsLink
                ? Array(repeating: false, count: signature.valueParameterHasDefaultValues.count)
                : signature.valueParameterHasDefaultValues
            canThrow = signature.canThrow
            valueParameterNames = signature.valueParameterSymbols.compactMap { paramSymbol in
                symbols.symbol(paramSymbol).map { interner.resolve($0.name) }
            }
            // The synthetic enum `valueOf` signature can have an arity without
            // a corresponding value-parameter symbol. Its public Kotlin
            // parameter is still named `name`, which imported consumers need
            // for named-argument resolution.
            if interner.resolve(symbol.name) == "valueOf",
               signature.parameterTypes.count == 1,
               Self.isPublicImplicitEnumClassHelper(symbol, interner: interner),
               Self.isSourceBackedEnumClassMember(
                   symbol.id,
                   symbols: symbols,
                   excludedSourceFileIDs: [],
                   allowShellBackedEnum: true
               ) {
                valueParameterNames = ["name"]
            }
            reifiedTypeParameterIndices = signature.reifiedTypeParameterIndices
            receiverOwnerFQName = signature.receiverType.flatMap { receiverType in
                BundledDeclarationIndex.receiverOwnerFQName(
                    for: receiverType,
                    symbols: symbols,
                    types: types,
                    interner: interner
                )?.map { interner.resolve($0) }.joined(separator: ".")
            }
            typeSignature = mangler.mangledSignature(
                for: symbol,
                symbols: symbols,
                types: types,
                nameResolver: { interner.resolve($0) },
                unboxValueClasses: false
            )
            typeParameterUpperBoundsSignatures = signature.typeParameterUpperBoundsList.map { bounds in
                bounds.map {
                    metadataTypeSignature(
                        $0,
                        symbols: symbols,
                        types: types,
                        mangler: mangler,
                        nameResolver: { interner.resolve($0) }
                    )
                }
            }
            callableTypeParameterSignatures = signature.typeParameterSymbols.map { "T\($0.rawValue)" }
            inputOnlyTypeParameterIndices = Set(signature.typeParameterSymbols.indices.filter { index in
                symbols.annotations(for: signature.typeParameterSymbols[index]).contains {
                    $0.annotationFQName == "kotlin.internal.OnlyInputTypes"
                }
            })
            externalLinkName = functionLinkNames[symbol.id] ?? symbols.externalLinkName(for: symbol.id)
            // KUU-655: uses the (already override-corrected) local flag, not
            // `signature.valueParameterHasDefaultValues` directly, so an
            // override with an inherited defaults link never looks for a
            // stub it was never given (see the comment above).
            if valueParameterHasDefaultValues.contains(true) {
                let stubSymbol = SyntheticSymbolScheme.defaultStubSymbol(for: symbol.id)
                defaultStubExternalLinkName = functionLinkNames[stubSymbol] ?? symbols.externalLinkName(for: stubSymbol)
            }
            if runtimeCallbackRawReturnSymbolIDs.contains(symbol.id),
               symbols.functionABIReturnType(for: symbol.id) == nil
            {
                abiReturnTypeSignature = metadataTypeSignature(
                    types.intType,
                    symbols: symbols,
                    types: types,
                    mangler: mangler,
                    nameResolver: { interner.resolve($0) }
                )
            }
            if let abiReturnType = symbols.functionABIReturnType(for: symbol.id) {
                abiReturnTypeSignature = metadataTypeSignature(
                    abiReturnType,
                    symbols: symbols,
                    types: types,
                    mangler: mangler,
                    nameResolver: { interner.resolve($0) }
                )
            }
        }

        var propertyReceiverTypeSignature: String?
        var propertyGetterExternalLinkName: String?
        var propertySetterExternalLinkName: String?
        var propertyGetterAbiReturnTypeSignature: String?
        var isMutable = false
        var constValueLiteral: String?
        if symbol.kind == .property || symbol.kind == .field,
           symbols.propertyType(for: symbol.id) != nil
        {
            typeSignature = symbols.propertyType(for: symbol.id).map { propertyType in
                metadataTypeSignature(
                    propertyType,
                    symbols: symbols,
                    types: types,
                    mangler: mangler,
                    nameResolver: { interner.resolve($0) }
                )
            }
            propertyReceiverTypeSignature = symbols.extensionPropertyReceiverType(for: symbol.id).map { receiverType in
                metadataTypeSignature(
                    receiverType,
                    symbols: symbols,
                    types: types,
                    mangler: mangler,
                    nameResolver: { interner.resolve($0) }
                )
            }
            receiverOwnerFQName = symbols.extensionPropertyReceiverType(for: symbol.id).flatMap { receiverType in
                BundledDeclarationIndex.receiverOwnerFQName(
                    for: receiverType,
                    symbols: symbols,
                    types: types,
                    interner: interner
                )?.map { interner.resolve($0) }.joined(separator: ".")
            }
            // Property accessors are lowered as functions in the artifact
            // objects. Record the getter link even for abstract properties:
            // inline producer bodies may dispatch through that getter and the
            // consumer must resolve the link to its imported accessor symbol.
            // Enum `entries` is a compiler-synthesized property whose getter
            // is emitted as `entries$get`, rather than through the ordinary
            // property-accessor naming scheme. Preserve that getter link in a
            // precompiled artifact so consumers do not materialize an
            // unresolved global slot for the property itself.
            let enumEntriesGetterSymbol: SymbolID? = {
                guard symbol.name == interner.intern("entries"),
                      let companionID = symbols.parentSymbol(for: symbol.id),
                      let companion = symbols.symbol(companionID),
                      companion.kind == .object,
                      let enumID = symbols.parentSymbol(for: companionID),
                      let enumSymbol = symbols.symbol(enumID),
                      enumSymbol.kind == .enumClass,
                      symbols.companionObjectSymbol(for: enumID) == companionID
                else {
                    return nil
                }
                let getterFQName = companion.fqName + [interner.intern("entries$get")]
                return symbols.lookupAll(fqName: getterFQName).first { candidate in
                    symbols.symbol(candidate)?.kind == .function
                }
            }()
            let getterSymbol = enumEntriesGetterSymbol
                ?? symbols.extensionPropertyGetterAccessor(for: symbol.id)
                ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol.id)
            if let getter = symbols.functionSignature(for: getterSymbol) {
                reifiedTypeParameterIndices = getter.reifiedTypeParameterIndices
                callableTypeParameterSignatures = getter.typeParameterSymbols.map { "T\($0.rawValue)" }
                typeParameterUpperBoundsSignatures = getter.typeParameterUpperBoundsList.map { bounds in
                    bounds.map {
                        metadataTypeSignature($0, symbols: symbols, types: types, mangler: mangler,
                                              nameResolver: { interner.resolve($0) })
                    }
                }
            }
            let hasCustomGetter = symbols.propertyHasCustomGetter(for: symbol.id)
                || symbols.extensionPropertyGetterAccessor(for: symbol.id) != nil
                || enumEntriesGetterSymbol != nil
            // Runtime-backed properties can be declared in bundled source
            // without a Kotlin getter body (for example Collection.size). The
            // property symbol's external link must still cross the library
            // boundary as a synthetic getter link; otherwise consumers restore
            // the property as an itable getter and runtime collection boxes
            // cannot satisfy the dispatch.
            if !hasCustomGetter,
               let propertyLink = symbols.externalLinkName(for: symbol.id),
               !propertyLink.isEmpty
            {
                propertyGetterExternalLinkName = propertyLink
            }
            if propertyGetterExternalLinkName == nil,
               let linkName = functionLinkNames[getterSymbol] ?? symbols.externalLinkName(for: getterSymbol),
               !linkName.isEmpty {
                propertyGetterExternalLinkName = linkName
            }
            // The setter accessor is a precompiled function too (a `var` with
            // a custom `set` body, or any bundled extension `var`); without
            // its link name the consumer resolves writes to a bare `set` call
            // that fails to link (e.g. `atomicInt.value = x`).
            let setterSymbol = symbols.extensionPropertySetterAccessor(for: symbol.id)
                ?? SyntheticSymbolScheme.propertySetterAccessorSymbol(for: symbol.id)
            if let setterLinkName = functionLinkNames[setterSymbol] ?? symbols.externalLinkName(for: setterSymbol),
               !setterLinkName.isEmpty {
                propertySetterExternalLinkName = setterLinkName
            }
            if propertyGetterExternalLinkName != nil {
                let isErasedTypeParameterGetter: Bool = {
                    guard let propertyType = symbols.propertyType(for: symbol.id) else {
                        return false
                    }
                    if case .typeParam = types.kind(of: propertyType) {
                        return true
                    }
                    return false
                }()
                if runtimeCallbackRawReturnSymbolIDs.contains(getterSymbol)
                    || isErasedTypeParameterGetter
                {
                    propertyGetterAbiReturnTypeSignature = metadataTypeSignature(
                        types.intType,
                        symbols: symbols,
                        types: types,
                        mangler: mangler,
                        nameResolver: { interner.resolve($0) }
                    )
                }
            }
            isMutable = symbol.flags.contains(.mutable)
            if !isMutable, let constValue = symbols.constValueExprKind(for: symbol.id) {
                constValueLiteral = MetadataConstValueCoder.encode(constValue) { interner.resolve($0) }
            }
        }

        if symbol.kind == .typeAlias,
           symbols.typeAliasUnderlyingType(for: symbol.id) != nil
        {
            typeSignature = symbols.typeAliasUnderlyingType(for: symbol.id).map { underlyingType in
                metadataTypeSignature(
                    underlyingType,
                    symbols: symbols,
                    types: types,
                    mangler: mangler,
                    nameResolver: { interner.resolve($0) }
                )
            }
        }

        var declaredFieldCount: Int?
        var declaredInstanceSizeWords: Int?
        var declaredVtableSize: Int?
        var declaredItableSize: Int?
        var superFQName: String?
        var companionObjectFQName: String?
        var fieldOffsetsStr: String?
        var vtableSlotsStr: String?
        var itableSlotsStr: String?
        var objectInitializerLinkName: String?
        var companionInitializerLinkName: String?
        var objectLazyInitializerLinkName: String?
        var enumStaticInitLinkName: String?
        var nominalTypeParametersSignature: String?
        var nominalSupertypeSignatures: [String] = []
        var nominalTypeParameters: String?

        if Self.nominalKinds.contains(symbol.kind) {
            superFQName = computedSuperFQName
            let generics = nominalGenericSignatures(
                symbol: symbol,
                symbols: symbols,
                types: types,
                mangler: mangler,
                interner: interner
            )
            nominalTypeParameters = serializeNominalTypeParameters(
                for: symbol.id,
                symbols: symbols,
                types: types,
                mangler: mangler,
                interner: interner
            )
            nominalTypeParametersSignature = generics.selfSignature
            nominalSupertypeSignatures = generics.supertypeSignatures
            if let layout = symbols.nominalLayout(for: symbol.id) {
                declaredInstanceSizeWords = layout.instanceSizeWords
                declaredFieldCount = layout.instanceFieldCount
                declaredVtableSize = layout.vtableSize
                declaredItableSize = layout.itableSize

                let serializedFieldOffsets = serializeFieldOffsets(layout.fieldOffsets, symbols: symbols, interner: interner, includedSymbolIDs: includedSymbolIDs)
                if !serializedFieldOffsets.isEmpty {
                    fieldOffsetsStr = serializedFieldOffsets
                }
                let serializedVTableSlots = serializeVTableSlots(layout.vtableSlots, symbols: symbols, interner: interner, includedSymbolIDs: includedSymbolIDs, mangler: mangler, types: types)
                if !serializedVTableSlots.isEmpty {
                    vtableSlotsStr = serializedVTableSlots
                }
                let serializedITableSlots = serializeITableSlots(layout.itableSlots, symbols: symbols, interner: interner, includedSymbolIDs: includedSymbolIDs)
                if !serializedITableSlots.isEmpty {
                    itableSlotsStr = serializedITableSlots
                }
            }
            if let companionSymbolID = symbols.companionObjectSymbol(for: symbol.id),
               let includedSymbolIDs = includedSymbolIDs,
               includedSymbolIDs.contains(companionSymbolID),
               let companionSymbol = symbols.symbol(companionSymbolID)
            {
                companionObjectFQName = companionSymbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
            }
            if symbol.kind == .object {
                objectInitializerLinkName = objectInitializerLinkNames[symbol.id]
            }
            companionInitializerLinkName = companionInitializerLinkNames[symbol.id]
            if symbol.kind == .object {
                objectLazyInitializerLinkName = objectLazyInitializerLinkNames[symbol.id]
            }
            if symbol.kind == .enumClass {
                enumStaticInitLinkName = enumStaticInitLinkNames[symbol.id]
            }
        }

        let isDataClass = symbol.flags.contains(.dataType)
        let isOpenClass = symbol.flags.contains(.openType)
        // Kotlin override members are implicitly open unless explicitly final;
        // without this, an imported `override val` (e.g. AbstractMap.size)
        // decodes as final and consumers reject valid overrides.
        let modality: MetadataModality = if symbol.flags.contains(.abstractType) {
            .abstract
        } else if symbol.flags.contains(.openType)
                    || (symbol.flags.contains(.overrideMember) && !symbol.flags.contains(.finalMember)) {
            .open
        } else {
            .final
        }
        let isSealedClass = symbol.flags.contains(.sealedType)
        let isFunInterface = symbol.flags.contains(.funInterface)
        let isExpect = symbol.flags.contains(.expectDeclaration)
        let isActual = symbol.flags.contains(.actualDeclaration)
        // Serialize isValueClass independently of whether the underlying type was found.
        // Even if underlying type extraction fails, mark it as a value class so importers
        // can identify it correctly; valueClassUnderlyingTypeSig may be nil in that case.
        let isValueClass = symbol.flags.contains(.valueType)

        let annotationEntries = symbols.annotations(for: symbol.id)

        // P5-78: collect sealed subclass FQ names for cross-module exhaustiveness
        var sealedSubclassFQNames: [String] = []
        if isSealedClass {
            let directSubs = symbols.sealedSubclasses(for: symbol.id) ?? symbols.directSubtypes(of: symbol.id)
            sealedSubclassFQNames = directSubs.compactMap { subID in
                guard let subSymbol = symbols.symbol(subID) else { return nil }
                let subFQ = subSymbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
                return subFQ.isEmpty ? nil : subFQ
            }.sorted()
        }

        return MetadataRecord(
            kind: symbol.kind,
            visibility: symbol.visibility,
            mangledName: mangled,
            fqName: fqName,
            arity: arity,
            isSuspend: isSuspend,
            isInline: isInline,
            isOperator: isOperator,
            isInfix: isInfix,
            isOverride: isOverride,
            isMemberExtension: symbol.flags.contains(.memberExtension),
            receiverOwnerFQName: receiverOwnerFQName,
            typeSignature: typeSignature,
            typeParameterUpperBoundsSignatures: typeParameterUpperBoundsSignatures,
            callableTypeParameterSignatures: callableTypeParameterSignatures,
            inputOnlyTypeParameterIndices: inputOnlyTypeParameterIndices,
            valueParameterIsVararg: valueParameterIsVararg,
            valueParameterAllowsNonLocalReturn: valueParameterAllowsNonLocalReturn,
            valueParameterHasDefaultValues: valueParameterHasDefaultValues,
            valueParameterCallsInPlaceKinds: valueParameterCallsInPlaceKinds,
            contractImplicationEffects: symbols.contractImplicationEffects(for: symbol.id).map { effect in
                ContractImplicationEffect(parameterIndex: effect.parameterIndex,
                    returnCondition: effect.returnCondition, argumentCondition: effect.argumentCondition,
                    targetTypeSignature: effect.targetType.map {
                        metadataTypeSignature($0, symbols: symbols, types: types,
                                              mangler: mangler, nameResolver: { interner.resolve($0) })
                    })
            },
            canThrow: canThrow,
            valueParameterNames: valueParameterNames,
            reifiedTypeParameterIndices: reifiedTypeParameterIndices,
            defaultStubExternalLinkName: defaultStubExternalLinkName,
            externalLinkName: externalLinkName,
            declaredFieldCount: declaredFieldCount,
            declaredInstanceSizeWords: declaredInstanceSizeWords,
            declaredVtableSize: declaredVtableSize,
            declaredItableSize: declaredItableSize,
            superFQName: superFQName,
            companionObjectFQName: companionObjectFQName,
            fieldOffsets: fieldOffsetsStr,
            vtableSlots: vtableSlotsStr,
            itableSlots: itableSlotsStr,
            objectInitializerLinkName: objectInitializerLinkName,
            companionInitializerLinkName: companionInitializerLinkName,
            objectLazyInitializerLinkName: objectLazyInitializerLinkName,
            enumStaticInitLinkName: enumStaticInitLinkName,
            isDataClass: isDataClass,
            isOpenClass: isOpenClass,
            modality: modality,
            isSealedClass: isSealedClass,
            isFunInterface: isFunInterface,
            annotations: annotationEntries,
            isValueClass: isValueClass,
            valueClassUnderlyingTypeSig: valueClassUnderlyingTypeSig,
            sealedSubclassFQNames: sealedSubclassFQNames,
            isExpect: isExpect,
            isActual: isActual,
            propertyReceiverTypeSignature: propertyReceiverTypeSignature,
            propertyGetterExternalLinkName: propertyGetterExternalLinkName,
            propertySetterExternalLinkName: propertySetterExternalLinkName,
            abiReturnTypeSignature: abiReturnTypeSignature,
            propertyGetterAbiReturnTypeSignature: propertyGetterAbiReturnTypeSignature,
            isMutable: isMutable,
            nominalTypeParametersSignature: nominalTypeParametersSignature,
            nominalSupertypeSignatures: nominalSupertypeSignatures,
            constValueLiteral: constValueLiteral,
            nominalTypeParameters: nominalTypeParameters
        )
    }

    /// Encodes a nominal type's declaration-order type parameters as
    /// `<typeSignature>:<variance>` pairs so importers can restore the generic
    /// arity (constructor/member type-argument resolution needs it).
    private func serializeNominalTypeParameters(
        for symbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        mangler: NameMangler,
        interner: StringInterner
    ) -> String? {
        let typeParameterSymbols = types.nominalTypeParameterSymbols(for: symbol)
        guard !typeParameterSymbols.isEmpty else {
            return nil
        }
        let variances = types.nominalTypeParameterVariances(for: symbol)
        let entries: [String] = typeParameterSymbols.enumerated().map { index, typeParameterSymbol in
            let encoded = mangler.encodeType(
                types.make(.typeParam(TypeParamType(symbol: typeParameterSymbol, nullability: .nonNull))),
                symbols: symbols,
                types: types,
                nameResolver: { interner.resolve($0) }
            )
            let variance: String = switch index < variances.count ? variances[index] : .invariant {
            case .invariant: "i"
            case .out: "o"
            case .in: "n"
            }
            return "\(encoded):\(variance)"
        }
        return entries.joined(separator: ",")
    }

    /// Nominal kinds that carry layout information in metadata.
    private static let nominalKinds: Set<SymbolKind> = [.class, .interface, .object, .enumClass, .annotationClass]

    /// True when `symbolID` is (or belongs to) a compiler-generated member of a
    /// source-backed data class (KSP-626).
    private static func isSourceBackedDataClassMember(
        _ symbolID: SymbolID,
        symbols: SymbolTable,
        excludedSourceFileIDs: Set<Int32>
    ) -> Bool {
        var currentID = symbols.parentSymbol(for: symbolID)
        while let parentID = currentID, let parent = symbols.symbol(parentID) {
            if nominalKinds.contains(parent.kind) {
                guard parent.flags.contains(.dataType),
                      !parent.flags.contains(.synthetic),
                      parent.declSite != nil
                else {
                    return false
                }
                if let sourceFileID = symbols.sourceFileID(for: parent.id),
                   excludedSourceFileIDs.contains(sourceFileID.rawValue)
                {
                    return false
                }
                return true
            }
            currentID = symbols.parentSymbol(for: parentID)
        }
        return false
    }

    /// Synthetic enum members are only retained for source-backed shell enums
    /// when they are one of Kotlin's public implicit enum helpers. This keeps
    /// shell-backed metadata from exporting unrelated synthetic or non-public
    /// enum members.
    private static func isPublicImplicitEnumClassHelper(
        _ symbol: SemanticSymbol,
        interner: StringInterner
    ) -> Bool {
        guard symbol.flags.contains(.synthetic), symbol.visibility == .public else {
            return false
        }
        switch (symbol.kind, interner.resolve(symbol.name)) {
        case (.property, "name"), (.property, "ordinal"), (.property, "entries"),
             (.function, "values"), (.function, "valueOf"):
            return true
        default:
            return false
        }
    }

    /// True when `symbolID` is a compiler-generated member of a source-backed enum
    /// class (name, ordinal, values) or its companion (valueOf, entries). These
    /// symbols are synthesized by HeaderCollection but are part of the public
    /// surface of an enum class, so consumers that import the class from a
    /// precompiled artifact must be able to resolve them.
    private static func isSourceBackedEnumClassMember(
        _ symbolID: SymbolID,
        symbols: SymbolTable,
        excludedSourceFileIDs: Set<Int32>,
        allowShellBackedEnum: Bool = false
    ) -> Bool {
        var currentID = symbols.parentSymbol(for: symbolID)
        while let parentID = currentID, let parent = symbols.symbol(parentID) {
            if Self.nominalKinds.contains(parent.kind) {
                if parent.kind == .enumClass,
                   !parent.flags.contains(.synthetic),
                   parent.declSite != nil {
                    if let sourceFileID = symbols.sourceFileID(for: parent.id),
                       excludedSourceFileIDs.contains(sourceFileID.rawValue)
                    {
                        return false
                    }
                    return true
                }
                // Source-backed bundled enums may reuse a synthetic nominal
                // shell (synthetic flag set, declSite nil) while still carrying
                // a tracked sourceFileID. Callers that opt in treat those as
                // source-backed too.
                if allowShellBackedEnum,
                   parent.kind == .enumClass,
                   parent.declSite != nil || symbols.sourceFileID(for: parent.id) != nil {
                    if let sourceFileID = symbols.sourceFileID(for: parent.id),
                       excludedSourceFileIDs.contains(sourceFileID.rawValue)
                    {
                        return false
                    }
                    return true
                }
                // Synthetic companions / nested anchors may sit between the
                // member and the owning enum class; keep walking.
                if parent.flags.contains(.synthetic) {
                    currentID = symbols.parentSymbol(for: parentID)
                    continue
                }
                // valueOf / entries are synthesized on the companion object,
                // which may be a user-declared (non-synthetic) companion. Walk
                // through it to reach the owning enum class.
                if parent.kind == .object,
                   let grandparentID = symbols.parentSymbol(for: parentID),
                   symbols.companionObjectSymbol(for: grandparentID) == parentID
                {
                    currentID = grandparentID
                    continue
                }
                return false
            }
            currentID = symbols.parentSymbol(for: parentID)
        }
        return false
    }

    func metadataAnnotationRecord(for record: MetadataRecord) -> MetadataAnnotationRecord {
        MetadataAnnotationRecord(
            annotationFQName: KnownCompilerAnnotation.metadata.qualifiedName,
            arguments: [serialize([record])]
        )
    }

    /// Serialize records to the text-based metadata format.
    package func serialize(_ records: [MetadataRecord]) -> String {
        var lines = ["symbols=\(records.count)"]
        for record in records {
            var fields: [String] = [
                "\(record.kind)",
                record.mangledName,
                "fq=\(record.fqName)",
                "schema=v1",
            ]
            if record.visibility != .public {
                let encoded: String = switch record.visibility {
                case .public: "public"
                case .private: "private"
                case .internal: "internal"
                case .protected: "protected"
                }
                fields.append("visibility=\(encoded)")
            }
            if record.isMemberExtension { fields.append("memberExtension=1") }
            if record.kind == .function || record.kind == .constructor {
                fields.append("arity=\(record.arity)")
                fields.append("suspend=\(record.isSuspend ? 1 : 0)")
                fields.append("inline=\(record.isInline ? 1 : 0)")
                fields.append("operator=\(record.isOperator ? 1 : 0)")
                fields.append("infix=\(record.isInfix ? 1 : 0)")
                if record.isOverride {
                    fields.append("override=1")
                }
                if !record.valueParameterIsVararg.isEmpty {
                    let mask = record.valueParameterIsVararg.map { $0 ? "1" : "0" }.joined()
                    fields.append("vararg=\(mask)")
                }
                if !record.valueParameterAllowsNonLocalReturn.isEmpty {
                    let mask = record.valueParameterAllowsNonLocalReturn.map { $0 ? "1" : "0" }.joined()
                    fields.append("nonLocal=\(mask)")
                }
                if !record.valueParameterHasDefaultValues.isEmpty {
                    let mask = record.valueParameterHasDefaultValues.map { $0 ? "1" : "0" }.joined()
                    fields.append("default=\(mask)")
                }
                if record.valueParameterCallsInPlaceKinds.contains(where: { $0 != nil }) {
                    let mask = record.valueParameterCallsInPlaceKinds.map { kind -> String in
                        switch kind {
                        case nil: "-"
                        case .atMostOnce: "M"
                        case .atLeastOnce: "A"
                        case .exactlyOnce: "E"
                        case .unknown: "U"
                        }
                    }.joined()
                    fields.append("callsInPlace=\(mask)")
                }
                if record.canThrow {
                    fields.append("canThrow=1")
                }
                if !record.contractImplicationEffects.isEmpty {
                    let effects = record.contractImplicationEffects.map {
                        "\($0.parameterIndex):\($0.returnCondition.rawValue):\($0.argumentCondition.rawValue)"
                            + ($0.targetTypeSignature.map { ":" + Data($0.utf8).base64EncodedString() } ?? "")
                    }.joined(separator: ",")
                    fields.append("contractImplies=\(effects)")
                }
                if !record.valueParameterNames.isEmpty {
                    fields.append("paramNames=\(record.valueParameterNames.joined(separator: ","))")
                }
                if !record.reifiedTypeParameterIndices.isEmpty {
                    let indices = record.reifiedTypeParameterIndices.sorted().map(String.init).joined(separator: ",")
                    fields.append("reified=\(indices)")
                }
                if let sig = record.typeSignature {
                    fields.append("sig=\(sig)")
                }
                if record.typeParameterUpperBoundsSignatures.contains(where: { !$0.isEmpty }),
                   let encodedBounds = encodeMetadataTypeParameterUpperBounds(record.typeParameterUpperBoundsSignatures)
                {
                    fields.append("typeBounds=\(encodedBounds)")
                }
                if !record.callableTypeParameterSignatures.isEmpty {
                    fields.append("callTParams=\(record.callableTypeParameterSignatures.joined(separator: ","))")
                }
                if !record.inputOnlyTypeParameterIndices.isEmpty {
                    fields.append("inputOnlyTParams=\(record.inputOnlyTypeParameterIndices.sorted().map(String.init).joined(separator: ","))")
                }
                if let linkName = record.defaultStubExternalLinkName, !linkName.isEmpty {
                    fields.append("defaultLink=\(linkName)")
                }
                if let abiSig = record.abiReturnTypeSignature {
                    fields.append("abiSig=\(abiSig)")
                }
            }
            if let linkName = record.externalLinkName, !linkName.isEmpty {
                fields.append("link=\(linkName)")
            }
            if record.kind == .property || record.kind == .field {
                if !record.reifiedTypeParameterIndices.isEmpty {
                    fields.append("reified=\(record.reifiedTypeParameterIndices.sorted().map(String.init).joined(separator: ","))")
                }
                if !record.callableTypeParameterSignatures.isEmpty {
                    fields.append("callTParams=\(record.callableTypeParameterSignatures.joined(separator: ","))")
                }
                if record.typeParameterUpperBoundsSignatures.contains(where: { !$0.isEmpty }),
                   let encodedBounds = encodeMetadataTypeParameterUpperBounds(record.typeParameterUpperBoundsSignatures) {
                    fields.append("typeBounds=\(encodedBounds)")
                }
                if let sig = record.typeSignature {
                    fields.append("sig=\(sig)")
                }
                if let recv = record.propertyReceiverTypeSignature {
                    fields.append("recv=\(recv)")
                }
                if let getterLink = record.propertyGetterExternalLinkName, !getterLink.isEmpty {
                    fields.append("getterLink=\(getterLink)")
                }
                if let setterLink = record.propertySetterExternalLinkName, !setterLink.isEmpty {
                    fields.append("setterLink=\(setterLink)")
                }
                if let getterAbiSig = record.propertyGetterAbiReturnTypeSignature {
                    fields.append("getterAbiSig=\(getterAbiSig)")
                }
                if record.isMutable {
                    fields.append("mutable=1")
                }
                if let constValue = record.constValueLiteral, !constValue.isEmpty {
                    fields.append("const=\(constValue)")
                }
            }
            if let receiverOwnerFQName = record.receiverOwnerFQName, !receiverOwnerFQName.isEmpty {
                fields.append("receiverFq=\(receiverOwnerFQName)")
            }
            if record.kind == .typeAlias {
                if let sig = record.typeSignature {
                    fields.append("sig=\(sig)")
                }
            }
            if Self.nominalKinds.contains(record.kind) {
                if let layoutWords = record.declaredInstanceSizeWords {
                    fields.append("layoutWords=\(layoutWords)")
                }
                if let fieldCount = record.declaredFieldCount {
                    fields.append("fields=\(fieldCount)")
                }
                if let vtableSize = record.declaredVtableSize {
                    fields.append("vtable=\(vtableSize)")
                }
                if let itableSize = record.declaredItableSize {
                    fields.append("itable=\(itableSize)")
                }
                if let fo = record.fieldOffsets {
                    fields.append("fieldOffsets=\(fo)")
                }
                if let vs = record.vtableSlots {
                    fields.append("vtableSlots=\(vs)")
                }
                if let is_ = record.itableSlots {
                    fields.append("itableSlots=\(is_)")
                }
                if let superFq = record.superFQName {
                    fields.append("superFq=\(superFq)")
                }
                if let typeParamsSig = record.nominalTypeParametersSignature {
                    fields.append("typeParamsSig=\(typeParamsSig)")
                }
                if !record.nominalSupertypeSignatures.isEmpty {
                    fields.append("superSigs=\(record.nominalSupertypeSignatures.joined(separator: "|"))")
                }
                if let companionFq = record.companionObjectFQName {
                    fields.append("companionFq=\(companionFq)")
                }
                if let objectInitLink = record.objectInitializerLinkName, !objectInitLink.isEmpty {
                    fields.append("objectInitLink=\(objectInitLink)")
                }
                if let companionInitLink = record.companionInitializerLinkName, !companionInitLink.isEmpty {
                    fields.append("companionInitLink=\(companionInitLink)")
                }
                if let objectLazyInitLink = record.objectLazyInitializerLinkName, !objectLazyInitLink.isEmpty {
                    fields.append("objectLazyInitLink=\(objectLazyInitLink)")
                }
                if let enumStaticInitLink = record.enumStaticInitLinkName, !enumStaticInitLink.isEmpty {
                    fields.append("enumStaticInitLink=\(enumStaticInitLink)")
                }
                if let typeParams = record.nominalTypeParameters, !typeParams.isEmpty {
                    fields.append("typeParams=\(typeParams)")
                }
            }
            if record.isDataClass {
                fields.append("dataClass=1")
            }
            if record.isOpenClass {
                fields.append("openClass=1")
            }
            if record.modality != .final {
                fields.append("modality=\(record.modality.rawValue)")
            }
            if record.isSealedClass {
                fields.append("sealedClass=1")
            }
            if record.isFunInterface {
                fields.append("funInterface=1")
            }
            if record.isValueClass {
                fields.append("valueClass=1")
                if let vSig = record.valueClassUnderlyingTypeSig {
                    fields.append("valueUnderlying=\(vSig)")
                }
            }
            if !record.sealedSubclassFQNames.isEmpty {
                fields.append("sealedSubs=\(record.sealedSubclassFQNames.joined(separator: ","))")
            }
            if record.isExpect {
                fields.append("expect=1")
            }
            if record.isActual {
                fields.append("actual=1")
            }
            if !record.annotations.isEmpty {
                fields.append("annotations=\(encodeAnnotations(record.annotations))")
            }
            lines.append(fields.joined(separator: " "))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Serialize metadata with a compact declaration index and a separately
    /// addressable body. Legacy readers continue to accept `serialize(_:)`.
    package func serializeIndexed(_ records: [MetadataRecord]) -> String {
        let legacyLines = serialize(records)
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .map(String.init)

        var body = Data()
        var indexLines: [String] = []
        indexLines.reserveCapacity(records.count)
        for (record, legacyLine) in zip(records, legacyLines) {
            let bodyLine = Data((legacyLine + "\n").utf8)
            let offset = body.count
            body.append(bodyLine)
            indexLines.append(
                "\(offset)\t\(bodyLine.count)\t\(serializeIndexRecordLine(record))"
            )
        }

        let prefix = "kklib-metadata-v2\nrecords=\(records.count)\nindex\n"
            + indexLines.joined(separator: "\n")
            + "\nbody\n"
        var result = Data(prefix.utf8)
        result.append(body)
        return String(decoding: result, as: UTF8.self)
    }

    private func serializeIndexRecordLine(_ record: MetadataRecord) -> String {
        var fields: [String] = [
            "\(record.kind)",
            record.mangledName,
            "fq=\(record.fqName)",
            "schema=v1",
        ]
        // Imported visibility checks run on the compact index record before
        // any body is decoded, so the index must carry it too.
        if record.visibility != .public {
            let encoded: String = switch record.visibility {
            case .public: "public"
            case .private: "private"
            case .internal: "internal"
            case .protected: "protected"
            }
            fields.append("visibility=\(encoded)")
        }
        if record.isMemberExtension { fields.append("memberExtension=1") }
        if record.kind == .function || record.kind == .constructor {
            fields.append("arity=\(record.arity)")
            fields.append("suspend=\(record.isSuspend ? 1 : 0)")
            fields.append("inline=\(record.isInline ? 1 : 0)")
            fields.append("operator=\(record.isOperator ? 1 : 0)")
            fields.append("infix=\(record.isInfix ? 1 : 0)")
            if record.isOverride { fields.append("override=1") }
            if let linkName = record.defaultStubExternalLinkName, !linkName.isEmpty {
                fields.append("defaultLink=\(linkName)")
            }
        }
        if let linkName = record.externalLinkName, !linkName.isEmpty {
            fields.append("link=\(linkName)")
        }
        if let receiverOwnerFQName = record.receiverOwnerFQName, !receiverOwnerFQName.isEmpty {
            fields.append("receiverFq=\(receiverOwnerFQName)")
        }
        if record.kind == .property || record.kind == .field {
            if let receiver = record.propertyReceiverTypeSignature {
                fields.append("recv=\(receiver)")
            }
            if let getterLink = record.propertyGetterExternalLinkName, !getterLink.isEmpty {
                fields.append("getterLink=\(getterLink)")
            }
            if record.isMutable { fields.append("mutable=1") }
        }
        if Self.nominalKinds.contains(record.kind),
           let typeParamsSig = record.nominalTypeParametersSignature
        {
            fields.append("typeParamsSig=\(typeParamsSig)")
        }
        if Self.nominalKinds.contains(record.kind),
           let companionFQName = record.companionObjectFQName,
           !companionFQName.isEmpty
        {
            fields.append("companionFq=\(companionFQName)")
        }
        if record.isDataClass { fields.append("dataClass=1") }
        if record.isOpenClass { fields.append("openClass=1") }
        if record.modality != .final { fields.append("modality=\(record.modality.rawValue)") }
        if record.isSealedClass { fields.append("sealedClass=1") }
        if record.isFunInterface { fields.append("funInterface=1") }
        if record.isValueClass { fields.append("valueClass=1") }
        if record.isExpect { fields.append("expect=1") }
        if record.isActual { fields.append("actual=1") }
        return fields.joined(separator: " ")
    }

    func serializeFieldOffsets(
        _ offsets: [SymbolID: Int],
        symbols: SymbolTable,
        interner: StringInterner,
        includedSymbolIDs: Set<SymbolID>? = nil
    ) -> String {
        // Export a property's storage under its own name. Consumers do not
        // have the producer's property-to-backing-field association, and a
        // private backing field may not be exported at all. Replace its key
        // rather than adding an alias: layout field counts count keys, so two
        // names for one slot would grow the imported object layout.
        // The offsets include inherited fields; inspect each storage owner.
        let storageOwners = Set(offsets.keys.compactMap { symbols.parentSymbol(for: $0) })
        var exportedPropertyByBackingField: [SymbolID: SymbolID] = [:]
        for owner in storageOwners {
            guard let ownerSymbol = symbols.symbol(owner) else { continue }
            for propertyID in symbols.children(ofFQName: ownerSymbol.fqName) {
                guard let property = symbols.symbol(propertyID), property.kind == .property,
                      !property.fqName.isEmpty,
                      symbols.parentSymbol(for: propertyID) == owner,
                      includedSymbolIDs?.contains(propertyID) ?? true,
                      let backingField = symbols.backingFieldSymbol(for: propertyID),
                      offsets[backingField] != nil,
                      symbols.parentSymbol(for: backingField) == owner
                else {
                    continue
                }
                exportedPropertyByBackingField[backingField] = propertyID
            }
        }
        let pairs: [(String, Int)] = offsets.compactMap { storageSymbolID, offset in
            let symbolID = exportedPropertyByBackingField[storageSymbolID] ?? storageSymbolID
            guard let symbol = symbols.symbol(symbolID) else {
                return nil
            }
            if let includedSymbolIDs, !includedSymbolIDs.contains(symbolID) {
                return nil
            }
            let fqName = symbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
            guard !fqName.isEmpty else {
                return nil
            }
            return (fqName, offset)
        }
        let sorted = pairs.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0 < rhs.0
        }
        return sorted.map { "\($0.0)@\($0.1)" }.joined(separator: ",")
    }

    /// True for compiler-generated enum static helpers (`values`, `valueOf`,
    /// `entries`) that belong to a non-public enum class.  These slots are not
    /// reachable from consumer code and cannot be resolved on import, so they
    /// should be omitted from serialized vtable/itable layouts.
    private func isNonPublicEnumStaticHelper(
        symbolID: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> Bool {
        guard let symbol = symbols.symbol(symbolID),
              symbol.kind == .function
        else {
            return false
        }
        let name = interner.resolve(symbol.name)
        guard name == "values" || name == "valueOf" || name == "entries" else {
            return false
        }
        var ancestorID = symbols.parentSymbol(for: symbol.id)
        while let ancestor = ancestorID, let ancestorSymbol = symbols.symbol(ancestor) {
            if ancestorSymbol.kind == .enumClass {
                return ancestorSymbol.visibility != .public
            }
            ancestorID = symbols.parentSymbol(for: ancestor)
        }
        return false
    }

    func serializeVTableSlots(
        _ slots: [SymbolID: Int],
        symbols: SymbolTable,
        interner: StringInterner,
        includedSymbolIDs: Set<SymbolID>? = nil,
        mangler: NameMangler? = nil,
        types: TypeSystem? = nil
    ) -> String {
        let pairs: [(String, Int)] = slots.compactMap { symbolID, slot in
            if let decoded = SyntheticSymbolScheme.decodedPropertyAccessor(symbolID),
               let property = symbols.symbol(decoded.property)
            {
                let fqName = property.fqName.map { interner.resolve($0) }.joined(separator: ".")
                guard !fqName.isEmpty else { return nil }
                let prefix = decoded.kind == .getter ? "pget:" : "pset:"
                return ("\(prefix)\(fqName)", slot)
            }
            if let property = symbols.symbol(symbolID), property.kind == .property {
                let fqName = property.fqName.map { interner.resolve($0) }.joined(separator: ".")
                guard !fqName.isEmpty else { return nil }
                return ("pget:\(fqName)", slot)
            }
            guard let symbol = symbols.symbol(symbolID), symbol.kind == .function else {
                return nil
            }
            // Vtable layout must survive the round-trip even for methods that are
            // private or synthetic (e.g. Any.toString/hashCode/equals, internal
            // helpers like Random.stepXorWow).  The consumer resolves each entry
            // by FQ name/arity/type-signature so that overloaded methods with the
            // same arity map to the correct slot.
            if isNonPublicEnumStaticHelper(symbolID: symbolID, symbols: symbols, interner: interner) {
                return nil
            }
            if let includedSymbolIDs, !includedSymbolIDs.contains(symbolID) {
                // Public synthetic interface members (e.g. MutableMap.put /
                // putAll) are not exported as symbol records: consumers
                // re-register them by fqName during residual synthesis, so
                // their slots must still serialize for the interface layout
                // to round-trip.
                guard symbol.flags.contains(.synthetic), symbol.visibility == .public,
                      let parentID = symbols.parentSymbol(for: symbol.id),
                      symbols.symbol(parentID)?.kind == .interface
                else {
                    return nil
                }
            }
            let fqName = symbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
            guard !fqName.isEmpty else {
                return nil
            }
            let signature = symbols.functionSignature(for: symbolID)
            let arity = signature?.parameterTypes.count ?? 0
            let isSuspend = signature?.isSuspend ?? false
            let typeSignature: String? = if let mangler, let types {
                mangler.mangledSignature(
                    for: symbol,
                    symbols: symbols,
                    types: types,
                    nameResolver: { interner.resolve($0) }
                )
            } else {
                nil
            }
            let key: String
            if let typeSignature, !typeSignature.isEmpty {
                key = "\(fqName)#\(arity)#\(isSuspend ? 1 : 0)#\(typeSignature)"
            } else {
                key = "\(fqName)#\(arity)#\(isSuspend ? 1 : 0)"
            }
            return (key, slot)
        }
        let sorted = pairs.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0 < rhs.0
        }
        // Use `|` as the entry separator because the type-signature component
        // of each key may contain commas (e.g. function parameter lists).
        // Prefix with `v2:` so single-entry tokens are distinguishable from the
        // legacy comma-separated format.
        let body = sorted.map { "\($0.0)@\($0.1)" }.joined(separator: "|")
        return "v2:\(body)"
    }

    func serializeITableSlots(
        _ slots: [SymbolID: Int],
        symbols: SymbolTable,
        interner: StringInterner,
        includedSymbolIDs: Set<SymbolID>? = nil
    ) -> String {
        let pairs: [(String, Int)] = slots.compactMap { symbolID, slot in
            guard let symbol = symbols.symbol(symbolID) else {
                return nil
            }
            if isNonPublicEnumStaticHelper(symbolID: symbolID, symbols: symbols, interner: interner) {
                return nil
            }
            // Dependency interfaces are not re-exported, but their slots still belong to the layout.
            if let includedSymbolIDs, !includedSymbolIDs.contains(symbolID),
               !symbol.flags.contains(.importedLibrary)
            {
                return nil
            }
            let fqName = symbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
            guard !fqName.isEmpty else {
                return nil
            }
            return (fqName, slot)
        }
        let sorted = pairs.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0 < rhs.0
        }
        return sorted.map { "\($0.0)@\($0.1)" }.joined(separator: ",")
    }

    // MARK: - Annotation Encoding

    private func encodeAnnotations(_ annotations: [MetadataAnnotationRecord]) -> String {
        annotations.map { encodeAnnotation($0) }.joined(separator: ";")
    }

    private func encodeAnnotation(_ annotation: MetadataAnnotationRecord) -> String {
        var parts = [annotation.annotationFQName]
        if let target = annotation.useSiteTarget {
            parts.append("target:\(target)")
        }
        if !annotation.arguments.isEmpty {
            let argsB64 = annotation.arguments.map { Data($0.utf8).base64EncodedString() }
            parts.append("args:\(argsB64.joined(separator: ","))")
        }
        return parts.joined(separator: "|")
    }
}

private func encodeMetadataTypeParameterUpperBounds(_ bounds: [[String]]) -> String? {
    let encodedGroups = bounds.map { group in
        group.map { Data($0.utf8).base64EncodedString() }.joined(separator: ",")
    }
    return encodedGroups.isEmpty ? nil : encodedGroups.joined(separator: "|")
}
