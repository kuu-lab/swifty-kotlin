
extension DataFlowSemaPhase {
    func parseLibraryMetadata(
        path: String,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) -> [ImportedLibrarySymbolRecord]? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            diagnostics.warning(
                "KSWIFTK-LIB-0001",
                "Unable to read library metadata: \(path)",
                range: nil
            )
            return nil
        }

        let decoder = MetadataDecoder()
        let metadataRecords = decoder.decode(content)
        let nominalTypeParametersByFQName = Dictionary(
            uniqueKeysWithValues: metadataRecords.compactMap { record -> (String, String)? in
                guard let signature = record.nominalTypeParametersSignature else {
                    return nil
                }
                return (record.fqName, signature)
            }
        )

        var records: [ImportedLibrarySymbolRecord] = []
        for metadataRecord in metadataRecords {
            let fqName = metadataRecord.fqName
                .split(separator: ".")
                .map { interner.intern(String($0)) }
            guard !fqName.isEmpty else {
                continue
            }
            let ownerNominalTypeParametersSignature: String? = if fqName.count >= 2 {
                nominalTypeParametersByFQName[
                    fqName.dropLast().map { interner.resolve($0) }.joined(separator: ".")
                ]
            } else {
                nil
            }
            let superFQNames: [[InternedString]]? = metadataRecord.superFQName.flatMap { value in
                // Multiple direct supertypes are encoded as comma-separated FQ names,
                // e.g. "kotlin.collections.Collection,kotlin.collections.Iterable".
                let names = value.split(separator: ",")
                guard !names.isEmpty else { return nil }
                let parsed = names.map { name in
                    name.split(separator: ".").map { interner.intern(String($0)) }
                }
                return parsed.isEmpty || parsed.contains(where: { $0.isEmpty }) ? nil : parsed
            }
            let companionObjectFQName: [InternedString]? = metadataRecord.companionObjectFQName.flatMap { value in
                let parsed = value.split(separator: ".").map { interner.intern(String($0)) }
                return parsed.isEmpty ? nil : parsed
            }
            let fieldOffsets: [ImportedFieldOffsetEntry] = if let fieldOffsetsStr = metadataRecord.fieldOffsets {
                parseImportedFieldOffsets(
                    token: fieldOffsetsStr,
                    diagnostics: diagnostics,
                    metadataPath: path,
                    ownerFQName: fqName,
                    interner: interner
                )
            } else {
                []
            }
            let vtableSlots: [ImportedVTableSlotEntry] = if let vtableSlotsStr = metadataRecord.vtableSlots {
                parseImportedVTableSlots(
                    token: vtableSlotsStr,
                    diagnostics: diagnostics,
                    metadataPath: path,
                    ownerFQName: fqName,
                    interner: interner
                )
            } else {
                []
            }
            let itableSlots: [ImportedITableSlotEntry] = if let itableSlotsStr = metadataRecord.itableSlots {
                parseImportedITableSlots(
                    token: itableSlotsStr,
                    diagnostics: diagnostics,
                    metadataPath: path,
                    ownerFQName: fqName,
                    interner: interner
                )
            } else {
                []
            }
            // P5-78: parse sealed subclass FQ names for cross-module exhaustiveness
            let sealedSubclassFQNames: [[InternedString]] = metadataRecord.sealedSubclassFQNames.compactMap { fqStr in
                let parsed = fqStr.split(separator: ".").map { interner.intern(String($0)) }
                return parsed.isEmpty ? nil : parsed
            }

            records.append(ImportedLibrarySymbolRecord(
                kind: metadataRecord.kind,
                mangledName: metadataRecord.mangledName,
                fqName: fqName,
                arity: metadataRecord.arity,
                isSuspend: metadataRecord.isSuspend,
                isInline: metadataRecord.isInline,
                isOperator: metadataRecord.isOperator,
                isOverride: metadataRecord.isOverride,
                valueParameterIsVararg: metadataRecord.valueParameterIsVararg,
                valueParameterAllowsNonLocalReturn: metadataRecord.valueParameterAllowsNonLocalReturn,
                valueParameterHasDefaultValues: metadataRecord.valueParameterHasDefaultValues,
                canThrow: metadataRecord.canThrow,
                valueParameterNames: metadataRecord.valueParameterNames,
                reifiedTypeParameterIndices: metadataRecord.reifiedTypeParameterIndices,
                typeSignature: metadataRecord.typeSignature,
                typeParameterUpperBoundsSignatures: metadataRecord.typeParameterUpperBoundsSignatures,
                defaultStubExternalLinkName: metadataRecord.defaultStubExternalLinkName,
                externalLinkName: metadataRecord.externalLinkName,
                declaredFieldCount: metadataRecord.declaredFieldCount,
                declaredInstanceSizeWords: metadataRecord.declaredInstanceSizeWords,
                declaredVtableSize: metadataRecord.declaredVtableSize,
                declaredItableSize: metadataRecord.declaredItableSize,
                superFQName: superFQNames?.first,
                superFQNames: superFQNames,
                companionObjectFQName: companionObjectFQName,
                fieldOffsets: fieldOffsets,
                vtableSlots: vtableSlots,
                itableSlots: itableSlots,
                objectInitializerLinkName: metadataRecord.objectInitializerLinkName,
                companionInitializerLinkName: metadataRecord.companionInitializerLinkName,
                enumStaticInitLinkName: metadataRecord.enumStaticInitLinkName,
                isDataClass: metadataRecord.isDataClass,
                isOpenClass: metadataRecord.isOpenClass,
                modality: metadataRecord.modality,
                isSealedClass: metadataRecord.isSealedClass,
                isFunInterface: metadataRecord.isFunInterface,
                isValueClass: metadataRecord.isValueClass,
                isExpect: metadataRecord.isExpect,
                isActual: metadataRecord.isActual,
                valueClassUnderlyingTypeSig: metadataRecord.valueClassUnderlyingTypeSig,
                annotations: metadataRecord.annotations,
                sealedSubclassFQNames: sealedSubclassFQNames,
                propertyReceiverTypeSignature: metadataRecord.propertyReceiverTypeSignature,
                propertyGetterExternalLinkName: metadataRecord.propertyGetterExternalLinkName,
                abiReturnTypeSignature: metadataRecord.abiReturnTypeSignature,
                propertyGetterAbiReturnTypeSignature: metadataRecord.propertyGetterAbiReturnTypeSignature,
                isMutable: metadataRecord.isMutable,
                nominalTypeParametersSignature: metadataRecord.nominalTypeParametersSignature,
                ownerNominalTypeParametersSignature: ownerNominalTypeParametersSignature,
                nominalSupertypeSignatures: metadataRecord.nominalSupertypeSignatures,
                constValueLiteral: metadataRecord.constValueLiteral,
                nominalTypeParameters: metadataRecord.nominalTypeParameters
            ))
        }

        return records
    }

    func importedFunctionSignature(
        record: ImportedLibrarySymbolRecord,
        ownerSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        metadataPath: String,
        cache: LibraryMetadataCache? = nil,
        allowPlaceholders: Bool = false
    ) -> FunctionSignature {
        let platformAny = types.withNullability(.platformType, for: types.anyType)
        let fallback = FunctionSignature(
            parameterTypes: Array(repeating: platformAny, count: max(0, record.arity)),
            returnType: platformAny,
            isSuspend: record.isSuspend
        )
        guard let encodedSignature = record.typeSignature else {
            return fallback
        }
        guard let decodedRaw = decodeImportedTypeSignature(
            token: encodedSignature,
            symbols: symbols,
            types: types,
            interner: interner,
            diagnostics: diagnostics,
            metadataPath: metadataPath,
            ownerFQName: record.fqName,
            cache: cache,
            allowPlaceholders: allowPlaceholders
        ) else {
            return fallback
        }
        let decoded = normalizeImportedOwnerTypeParameters(
            decodedRaw,
            record: record,
            symbols: symbols,
            types: types,
            diagnostics: diagnostics,
            interner: interner,
            metadataPath: metadataPath,
            cache: cache,
            allowPlaceholders: allowPlaceholders
        )
        guard case let .functionType(functionType) = types.kind(of: decoded) else {
            diagnostics.warning(
                "KSWIFTK-LIB-0003",
                "Invalid function signature metadata at \(metadataPath): \(renderFQName(record.fqName, interner: interner))",
                range: nil
            )
            return fallback
        }
        if record.arity != functionType.params.count || record.isSuspend != functionType.isSuspend {
            diagnostics.warning(
                "KSWIFTK-LIB-0005",
                "Metadata signature/arity mismatch at \(metadataPath): \(renderFQName(record.fqName, interner: interner))",
                range: nil
            )
        }
        var valueParameterIsVararg = Array(repeating: false, count: functionType.params.count)
        for index in record.valueParameterIsVararg.indices where index < valueParameterIsVararg.count {
            valueParameterIsVararg[index] = record.valueParameterIsVararg[index]
        }
        var valueParameterHasDefaultValues = Array(repeating: false, count: functionType.params.count)
        for index in record.valueParameterHasDefaultValues.indices where index < valueParameterHasDefaultValues.count {
            valueParameterHasDefaultValues[index] = record.valueParameterHasDefaultValues[index]
        }
        // Metadata emitted before BUG-209 has no non-local-return mask. Such
        // artifacts predate crossinline/noinline tracking, so retain the
        // historical permissive behavior for their inline function parameters.
        var valueParameterAllowsNonLocalReturn = Array(repeating: true, count: functionType.params.count)
        for index in record.valueParameterAllowsNonLocalReturn.indices where index < valueParameterAllowsNonLocalReturn.count {
            valueParameterAllowsNonLocalReturn[index] = record.valueParameterAllowsNonLocalReturn[index]
        }
        let typeParameterSymbols = collectTypeParameterSymbols(
            from: functionType,
            types: types
        )
        var typeParameterUpperBoundsList = Array(
            repeating: [TypeID](),
            count: typeParameterSymbols.count
        )
        for index in typeParameterUpperBoundsList.indices {
            guard index < record.typeParameterUpperBoundsSignatures.count else {
                continue
            }
            typeParameterUpperBoundsList[index] = record.typeParameterUpperBoundsSignatures[index].compactMap { encodedBound in
                guard let decodedBound = decodeImportedTypeSignature(
                    token: encodedBound,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    diagnostics: diagnostics,
                    metadataPath: metadataPath,
                    ownerFQName: record.fqName,
                    cache: cache,
                    allowPlaceholders: allowPlaceholders
                ) else {
                    return nil
                }
                return normalizeImportedOwnerTypeParameters(
                    decodedBound,
                    record: record,
                    symbols: symbols,
                    types: types,
                    diagnostics: diagnostics,
                    interner: interner,
                    metadataPath: metadataPath,
                    cache: cache,
                    allowPlaceholders: allowPlaceholders
                )
            }
        }
        var valueParameterSymbols: [SymbolID] = []
        for (index, _) in functionType.params.enumerated() {
            let name: String
            if index < record.valueParameterNames.count && !record.valueParameterNames[index].isEmpty {
                name = record.valueParameterNames[index]
            } else {
                name = "__param\(index)"
            }
            let paramName = interner.intern(name)
            let paramFQName = record.fqName + [paramName]
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: paramFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .importedLibrary]
            )
            symbols.setParentSymbol(ownerSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }
        return FunctionSignature(
            receiverType: functionType.receiver,
            parameterTypes: functionType.params,
            returnType: functionType.returnType,
            isSuspend: functionType.isSuspend,
            canThrow: record.canThrow,
            valueParameterSymbols: valueParameterSymbols,
            valueParameterHasDefaultValues: valueParameterHasDefaultValues,
            valueParameterIsVararg: valueParameterIsVararg,
            valueParameterAllowsNonLocalReturn: valueParameterAllowsNonLocalReturn,
            typeParameterSymbols: typeParameterSymbols,
            reifiedTypeParameterIndices: record.reifiedTypeParameterIndices,
            typeParameterUpperBoundsList: typeParameterUpperBoundsList,
            classTypeParameterCount: ownerNominalTypeParameterCount(
                of: functionType,
                record: record,
                symbols: symbols,
                types: types
            )
        )
    }

    /// Number of leading type parameters that belong to the owner nominal type
    /// rather than the callable itself. `collectTypeParameterSymbols` visits the
    /// receiver first, so a member of a generic class starts with exactly the
    /// type parameters carried by its owner's type arguments. Extension
    /// callables are excluded: their receiver type arguments are the function's
    /// own type parameters.
    private func ownerNominalTypeParameterCount(
        of functionType: FunctionType,
        record: ImportedLibrarySymbolRecord,
        symbols: SymbolTable,
        types: TypeSystem
    ) -> Int {
        guard record.fqName.count >= 2,
              let receiver = functionType.receiver,
              case let .classType(classType) = types.kind(of: types.makeNonNullable(receiver)),
              let ownerSymbol = symbols.symbol(classType.classSymbol),
              ownerSymbol.fqName == Array(record.fqName.dropLast())
        else {
            return 0
        }
        var seen: Set<SymbolID> = []
        for arg in classType.args {
            switch arg {
            case let .invariant(inner), let .out(inner), let .in(inner):
                guard case let .typeParam(typeParam) = types.kind(of: inner) else {
                    return 0
                }
                seen.insert(typeParam.symbol)
            case .star:
                return 0
            }
        }
        return seen.count
    }

    /// Collects the type parameter symbols referenced by a decoded function type
    /// in declaration order (first occurrence), so imported generic signatures
    /// can be solved during overload resolution.
    private func collectTypeParameterSymbols(
        from functionType: FunctionType,
        types: TypeSystem
    ) -> [SymbolID] {
        var seen: Set<SymbolID> = []
        var result: [SymbolID] = []

        func visit(_ type: TypeID) {
            switch types.kind(of: type) {
            case let .typeParam(typeParam):
                if seen.insert(typeParam.symbol).inserted {
                    result.append(typeParam.symbol)
                }
            case let .classType(classType):
                for arg in classType.args {
                    switch arg {
                    case let .invariant(t), let .out(t), let .in(t): visit(t)
                    case .star: break
                    }
                }
            case let .functionType(fn):
                for ctx in fn.contextReceivers { visit(ctx) }
                if let receiver = fn.receiver { visit(receiver) }
                for param in fn.params { visit(param) }
                visit(fn.returnType)
            case let .kClassType(kc):
                visit(kc.argument)
            case let .intersection(parts):
                for part in parts { visit(part) }
            case .nothing, .any, .primitive, .unit, .error, .stringStruct:
                break
            }
        }

        for ctx in functionType.contextReceivers { visit(ctx) }
        if let receiver = functionType.receiver { visit(receiver) }
        for param in functionType.params { visit(param) }
        visit(functionType.returnType)
        return result
    }

    func importedPropertyType(
        record: ImportedLibrarySymbolRecord,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        metadataPath: String,
        cache: LibraryMetadataCache? = nil,
        allowPlaceholders: Bool = false
    ) -> TypeID {
        let platformAny = types.withNullability(.platformType, for: types.anyType)
        guard let encodedSignature = record.typeSignature else {
            return platformAny
        }
        guard let decoded = decodeImportedTypeSignature(
            token: encodedSignature,
            symbols: symbols,
            types: types,
            interner: interner,
            diagnostics: diagnostics,
            metadataPath: metadataPath,
            ownerFQName: record.fqName,
            cache: cache,
            allowPlaceholders: allowPlaceholders
        ) else {
            return platformAny
        }
        return normalizeImportedOwnerTypeParameters(
            decoded,
            record: record,
            symbols: symbols,
            types: types,
            diagnostics: diagnostics,
            interner: interner,
            metadataPath: metadataPath,
            cache: cache,
            allowPlaceholders: allowPlaceholders
        )
    }

    func normalizeImportedOwnerTypeParameters(
        _ type: TypeID,
        record: ImportedLibrarySymbolRecord,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        metadataPath: String,
        cache: LibraryMetadataCache?,
        allowPlaceholders: Bool
    ) -> TypeID {
        guard let ownerSignature = record.ownerNominalTypeParametersSignature,
              record.fqName.count >= 2
        else {
            return type
        }
        let ownerFQName = Array(record.fqName.dropLast())
        guard let ownerSymbol = symbols.lookupAll(fqName: ownerFQName)
            .compactMap({ symbols.symbol($0) })
            .first(where: { isNominalLayoutTargetSymbol($0.kind) })?.id
        else {
            return type
        }
        let actualSymbols = types.nominalTypeParameterSymbols(for: ownerSymbol)
        guard !actualSymbols.isEmpty,
              let ownerType = decodeImportedTypeSignature(
                  token: ownerSignature,
                  symbols: symbols,
                  types: types,
                  interner: interner,
                  diagnostics: diagnostics,
                  metadataPath: metadataPath,
                  ownerFQName: ownerFQName,
                  cache: cache,
                  allowPlaceholders: allowPlaceholders
              ),
              case let .classType(ownerClassType) = types.kind(of: ownerType)
        else {
            return type
        }
        let metadataSymbols = ownerClassType.args.compactMap { arg -> SymbolID? in
            switch arg {
            case let .invariant(inner), let .out(inner), let .in(inner):
                guard case let .typeParam(typeParam) = types.kind(of: inner) else { return nil }
                return typeParam.symbol
            case .star:
                return nil
            }
        }
        guard metadataSymbols.count == actualSymbols.count else {
            return type
        }
        let typeVarBySymbol = types.makeTypeVarBySymbol(metadataSymbols)
        var substitution: [TypeVarID: TypeID] = [:]
        for (metadataSymbol, actualSymbol) in zip(metadataSymbols, actualSymbols) {
            guard let typeVar = typeVarBySymbol[metadataSymbol] else { continue }
            substitution[typeVar] = types.make(.typeParam(TypeParamType(symbol: actualSymbol)))
        }
        guard !substitution.isEmpty else {
            return type
        }
        return types.substituteTypeParameters(
            in: type,
            substitution: substitution,
            typeVarBySymbol: typeVarBySymbol
        )
    }

    func importedTypeAliasUnderlyingType(
        record: ImportedLibrarySymbolRecord,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        metadataPath: String,
        cache: LibraryMetadataCache? = nil,
        allowPlaceholders: Bool = false
    ) -> TypeID? {
        guard let encodedSignature = record.typeSignature else {
            return nil
        }
        guard let decoded = decodeImportedTypeSignature(
            token: encodedSignature,
            symbols: symbols,
            types: types,
            interner: interner,
            diagnostics: diagnostics,
            metadataPath: metadataPath,
            ownerFQName: record.fqName,
            cache: cache,
            allowPlaceholders: allowPlaceholders
        ) else {
            return nil
        }
        if case .error = types.kind(of: decoded) {
            diagnostics.warning(
                "KSWIFTK-LIB-0006",
                "Inconsistent typealias metadata at \(metadataPath): underlying type for '\(renderFQName(record.fqName, interner: interner))' resolved to error type.",
                range: nil
            )
            return decoded
        }
        return decoded
    }

    func importedValueClassUnderlyingType(
        signature: String,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        metadataPath: String,
        ownerFQName: [InternedString],
        allowPlaceholders: Bool = false
    ) -> TypeID? {
        guard let decoded = decodeImportedTypeSignature(
            token: signature,
            symbols: symbols,
            types: types,
            interner: interner,
            diagnostics: diagnostics,
            metadataPath: metadataPath,
            ownerFQName: ownerFQName,
            allowPlaceholders: allowPlaceholders
        ) else {
            return nil
        }
        return decoded
    }

    package func decodeImportedTypeSignature(
        token: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        diagnostics: DiagnosticEngine,
        metadataPath: String,
        ownerFQName: [InternedString],
        cache: LibraryMetadataCache? = nil,
        allowPlaceholders: Bool = false
    ) -> TypeID? {
        if let cache, let cached = cache.cachedSignature(token, types: types, symbols: symbols) {
            return cached
        }
        var parser = MetadataTypeSignatureParser(
            source: token,
            symbols: symbols,
            types: types,
            interner: interner,
            diagnostics: diagnostics,
            metadataPath: metadataPath,
            ownerFQName: ownerFQName,
            allowPlaceholders: allowPlaceholders
        )
        let result = parser.parse()
        cache?.cacheSignature(result, for: token, types: types, symbols: symbols)
        return result
    }

    private struct MetadataTypeSignatureParser {
        private let source: [Character]
        private var index: Int
        private var depth: Int
        private var depthLimitReported: Bool
        private var isOversized: Bool
        private let symbols: SymbolTable
        private let types: TypeSystem
        private let interner: StringInterner
        private let diagnostics: DiagnosticEngine
        private let metadataPath: String
        private let ownerFQName: [InternedString]
        private let allowPlaceholders: Bool
        private let syntheticTypeParameterBase: Int32 = DataFlowSemaPhase.syntheticTypeParameterBase
        // Keep enough headroom for the smaller stacks used by macOS test workers.
        // A signature with more than 63 nested wrappers is not practical metadata.
        private static let maxDepth: Int = 64
        private static let maxSourceLength: Int = 1_048_576

        init(
            source: String,
            symbols: SymbolTable,
            types: TypeSystem,
            interner: StringInterner,
            diagnostics: DiagnosticEngine,
            metadataPath: String,
            ownerFQName: [InternedString],
            allowPlaceholders: Bool = false
        ) {
            if source.count > Self.maxSourceLength {
                self.source = []
                self.isOversized = true
            } else {
                self.source = Array(source)
                self.isOversized = false
            }
            index = 0
            depth = 0
            depthLimitReported = false
            self.symbols = symbols
            self.types = types
            self.interner = interner
            self.diagnostics = diagnostics
            self.metadataPath = metadataPath
            self.ownerFQName = ownerFQName
            self.allowPlaceholders = allowPlaceholders
        }

        mutating func parse() -> TypeID? {
            if isOversized {
                diagnostics.warning(
                    "KSWIFTK-LIB-0003",
                    "Type signature in metadata exceeds maximum length at \(metadataPath) (\(ownerName()))",
                    range: nil
                )
                return nil
            }
            guard let type = parseType(), index == source.count else {
                if depthLimitReported {
                    return nil
                }
                diagnostics.warning(
                    "KSWIFTK-LIB-0003",
                    "Malformed type signature in metadata at \(metadataPath): \(truncatedSource) (\(ownerName()))",
                    range: nil
                )
                return nil
            }
            return type
        }

        private var truncatedSource: String {
            let prefix = source.prefix(200)
            let suffix = source.count > 200 ? "..." : ""
            return String(prefix) + suffix
        }

        private mutating func parseType() -> TypeID? {
            guard depth < Self.maxDepth else {
                if !depthLimitReported {
                    depthLimitReported = true
                    diagnostics.warning(
                        "KSWIFTK-LIB-0003",
                        "Type signature nesting exceeds maximum depth of \(Self.maxDepth) in metadata at \(metadataPath) (\(ownerName()))",
                        range: nil
                    )
                }
                return nil
            }
            depth += 1
            defer { depth -= 1 }

            if consume(prefix: "Q<") {
                guard let inner = parseType(), consume(character: ">") else {
                    return nil
                }
                return makeNullable(inner)
            }
            if consume(prefix: "SF"), let next = peek(), next.isNumber {
                return parseFunctionType(isSuspend: true)
            }
            if consume(character: "F") {
                if let next = peek(), next.isNumber {
                    return parseFunctionType(isSuspend: false)
                }
                return types.make(.primitive(.float, .nonNull))
            }
            if consume(character: "E") {
                return types.errorType
            }
            if consume(prefix: "UB") {
                return types.ubyteType
            }
            if consume(prefix: "US") {
                return types.ushortType
            }
            if consume(prefix: "UI") {
                return types.uintType
            }
            if consume(prefix: "UJ") {
                return types.ulongType
            }
            if consume(character: "B") {
                return types.make(.primitive(.byte, .nonNull))
            }
            if consume(character: "S") {
                return types.make(.primitive(.short, .nonNull))
            }
            if consume(character: "U") {
                return types.unitType
            }
            if consume(character: "N") {
                return types.nothingType
            }
            if consume(character: "A") {
                return types.anyType
            }
            if consume(character: "Z") {
                return types.make(.primitive(.boolean, .nonNull))
            }
            if consume(character: "C") {
                return types.make(.primitive(.char, .nonNull))
            }
            if consume(character: "I") {
                return types.make(.primitive(.int, .nonNull))
            }
            if consume(character: "J") {
                return types.make(.primitive(.long, .nonNull))
            }
            if consume(character: "D") {
                return types.make(.primitive(.double, .nonNull))
            }
            if consume(character: "L") {
                return parseClassType()
            }
            if consume(character: "T") {
                return parseTypeParameterType()
            }
            if consume(prefix: "X<") {
                return parseIntersectionType()
            }
            if consume(prefix: "KC<") {
                guard let argument = parseType(), consume(character: ">") else {
                    return nil
                }
                return types.make(.kClassType(KClassType(argument: argument, nullability: .nonNull)))
            }
            return nil
        }

        private mutating func parseClassType() -> TypeID? {
            let name = parseUntilDelimiters(["<", ";"])
            guard !name.isEmpty else {
                return nil
            }

            var args: [TypeArg] = []
            if consume(character: "<") {
                while true {
                    guard let arg = parseTypeArg() else {
                        return nil
                    }
                    args.append(arg)
                    if consume(character: ">") {
                        break
                    }
                    guard consume(character: ",") else {
                        return nil
                    }
                }
            }
            guard consume(character: ";") else {
                return nil
            }
            if name == "kotlin_String" {
                return types.stringType
            }

            let fqName = name.split(separator: ".").map { interner.intern(String($0)) }
            guard !fqName.isEmpty else {
                return nil
            }
            let candidates = symbols.lookupAll(fqName: fqName)
                .compactMap { symbols.symbol($0) }
                .filter { symbol in
                    switch symbol.kind {
                    case .class, .interface, .object, .enumClass, .annotationClass:
                        true
                    default:
                        false
                    }
                }
                .sorted(by: { $0.id.rawValue < $1.id.rawValue })
            guard let classSymbol = candidates.first?.id else {
                if allowPlaceholders, fqName.count >= 2 {
                    let placeholder = symbols.define(
                        kind: .class,
                        name: fqName.last!,
                        fqName: fqName,
                        declSite: nil,
                        visibility: .public,
                        flags: [.synthetic]
                    )
                    return types.make(.classType(ClassType(classSymbol: placeholder, args: args, nullability: .nonNull)))
                }
                diagnostics.warning(
                    "KSWIFTK-LIB-0004",
                    "Unknown nominal type in metadata signature at \(metadataPath): \(name) (\(ownerName()))",
                    range: nil
                )
                return types.anyType
            }
            return types.make(.classType(ClassType(classSymbol: classSymbol, args: args, nullability: .nonNull)))
        }

        private mutating func parseTypeArg() -> TypeArg? {
            if consume(character: "*") {
                return .star
            }
            if consume(prefix: "O<") {
                guard let type = parseType(), consume(character: ">") else {
                    return nil
                }
                return .out(type)
            }
            if consume(prefix: "N<") {
                guard let type = parseType(), consume(character: ">") else {
                    return nil
                }
                return .in(type)
            }
            guard let type = parseType() else {
                return nil
            }
            return .invariant(type)
        }

        private mutating func parseFunctionType(isSuspend: Bool) -> TypeID? {
            guard let arity = parseNumber(), consume(character: "<") else {
                return nil
            }

            var contextReceivers: [TypeID] = []
            if peek() == "C",
               index + 1 < source.count,
               source[index + 1].isNumber
            {
                _ = consume(character: "C")
                guard let contextArity = parseNumber(), consume(character: "<") else {
                    return nil
                }
                contextReceivers.reserveCapacity(contextArity)
                for index in 0 ..< contextArity {
                    guard let contextType = parseType() else {
                        return nil
                    }
                    contextReceivers.append(contextType)
                    if index + 1 < contextArity, !consume(character: ",") {
                        return nil
                    }
                }
                guard consume(character: ">"), consume(character: ",") else {
                    return nil
                }
            }

            var receiver: TypeID?
            if consume(character: "R") {
                guard let receiverType = parseType(), consume(character: ",") else {
                    return nil
                }
                receiver = receiverType
            }

            var params: [TypeID] = []
            params.reserveCapacity(arity)
            for _ in 0 ..< arity {
                guard let parameterType = parseType() else {
                    return nil
                }
                params.append(parameterType)
                guard consume(character: ",") else {
                    return nil
                }
            }

            guard let returnType = parseType(), consume(character: ">") else {
                return nil
            }
            return types.make(.functionType(FunctionType(
                contextReceivers: contextReceivers,
                receiver: receiver,
                params: params,
                returnType: returnType,
                isSuspend: isSuspend,
                nullability: .nonNull
            )))
        }

        private mutating func parseTypeParameterType() -> TypeID? {
            guard let rawIndex = parseNumber() else {
                return nil
            }
            let rawSymbol = syntheticTypeParameterBase - Int32(truncatingIfNeeded: rawIndex)
            return types.make(.typeParam(TypeParamType(symbol: SymbolID(rawValue: rawSymbol), nullability: .nonNull)))
        }

        private mutating func parseIntersectionType() -> TypeID? {
            var parts: [TypeID] = []
            while true {
                guard let type = parseType() else {
                    return nil
                }
                parts.append(type)
                if consume(character: ">") {
                    break
                }
                guard consume(character: "&") else {
                    return nil
                }
            }
            return types.make(.intersection(parts))
        }

        private func makeNullable(_ type: TypeID) -> TypeID {
            switch types.kind(of: type) {
            case .any:
                types.nullableAnyType
            case let .primitive(primitive, _):
                types.make(.primitive(primitive, .nullable))
            case .stringStruct:
                types.makeNullable(type)
            case let .classType(classType):
                types.make(.classType(ClassType(
                    classSymbol: classType.classSymbol,
                    args: classType.args,
                    nullability: .nullable
                )))
            case let .typeParam(typeParam):
                types.make(.typeParam(TypeParamType(symbol: typeParam.symbol, nullability: .nullable)))
            case let .functionType(functionType):
                types.make(.functionType(FunctionType(
                    contextReceivers: functionType.contextReceivers,
                    receiver: functionType.receiver,
                    params: functionType.params,
                    returnType: functionType.returnType,
                    isSuspend: functionType.isSuspend,
                    nullability: .nullable
                )))
            case let .kClassType(kClassType):
                types.make(.kClassType(KClassType(
                    argument: kClassType.argument,
                    nullability: .nullable
                )))
            case .nothing:
                types.nullableNothingType
            default:
                types.nullableAnyType
            }
        }

        private mutating func parseNumber() -> Int? {
            let start = index
            while let ch = peek(), ch.isNumber {
                index += 1
            }
            guard index > start else {
                return nil
            }
            return Int(String(source[start ..< index]))
        }

        private mutating func parseUntilDelimiters(_ delimiters: Set<Character>) -> String {
            let start = index
            while let ch = peek(), !delimiters.contains(ch) {
                index += 1
            }
            return String(source[start ..< index])
        }

        private func peek() -> Character? {
            guard index < source.count else {
                return nil
            }
            return source[index]
        }

        private mutating func consume(prefix: String) -> Bool {
            let chars = Array(prefix)
            guard index + chars.count <= source.count else {
                return false
            }
            for (offset, ch) in chars.enumerated() where source[index + offset] != ch {
                return false
            }
            index += chars.count
            return true
        }

        private mutating func consume(character: Character) -> Bool {
            guard let ch = peek(), ch == character else {
                return false
            }
            index += 1
            return true
        }

        private func ownerName() -> String {
            ownerFQName.map { interner.resolve($0) }.joined(separator: ".")
        }
    }
}
