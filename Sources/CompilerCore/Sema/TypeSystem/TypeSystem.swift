struct TypeSystemSemaSnapshot: Codable {
    struct TypeEntry: Codable {
        let id: TypeID
        let kind: TypeKind
    }

    let nextCaptureIdentity: Int
    let types: [TypeEntry]
    let nominalDirectSupertypes: [SymbolID: [SymbolID]]
    let nominalTypeParameterVariances: [SymbolID: [TypeVariance]]
    let nominalTypeParameterUpperBounds: [SymbolID: [[TypeID]]]
    let nominalTypeParameterSymbols: [SymbolID: [SymbolID]]
    let nominalSupertypeTypeArgs: [SymbolID: [SymbolID: [TypeArg]]]
    let comparableInterfaceSymbol: SymbolID?
    let serializableInterfaceSymbol: SymbolID?
    let annotationInterfaceSymbol: SymbolID?
    let closeableInterfaceSymbol: SymbolID?
    let ioCloseableInterfaceSymbol: SymbolID?
    let charSequenceInterfaceSymbol: SymbolID?
    let closeableTypeID: TypeID?
    let kFunctionInterfaceSymbol: SymbolID?
    let kCallableInterfaceSymbol: SymbolID?
    let functionInterfaceSymbol: SymbolID?
    let functionNInterfaceSymbols: [Int: SymbolID]
    let suspendFunctionNInterfaceSymbols: [Int: SymbolID]
    let kClassInterfaceSymbol: SymbolID?
    let numberClassSymbol: SymbolID?
    let stringClassSymbol: SymbolID?
    let charClassSymbol: SymbolID?
    let anyClassSymbol: SymbolID?
    let arrayClassSymbol: SymbolID?
    let unitClassSymbol: SymbolID?
}

struct NominalSupertypeClosureCacheEntry {
    let symbols: Set<SymbolID>
    let linkedTargets: Set<SymbolID>
    let directSupertypesVersion: UInt64
    let linkVersion: UInt64?
}

public final class TypeSystem {
    private var nextCaptureIdentity = 0

    var attribution: TypeCheckAttribution?

    func makeCapturedType(
        parameter: SymbolID,
        lower: TypeID,
        upper: TypeID,
        writeForbidden: Bool = false,
        origin: CapturedTypeOrigin? = nil
    ) -> TypeID {
        let capture = CapturedTypeBounds(
            identity: nextCaptureIdentity,
            lower: lower,
            upper: upper,
            writeForbidden: writeForbidden,
            origin: origin
        )
        nextCaptureIdentity += 1
        return make(.typeParam(TypeParamType(
            symbol: parameter, nullability: nullability(of: upper), capture: capture
        )))
    }

    func makeProjectedReceiverCapture(
        receiverType: TypeID,
        parameter: SymbolID,
        lower: TypeID,
        upper: TypeID,
        writeForbidden: Bool,
        argumentIndex: Int
    ) -> TypeID {
        makeCapturedType(
            parameter: parameter,
            lower: lower,
            upper: upper,
            writeForbidden: writeForbidden,
            origin: CapturedTypeOrigin(
                receiverType: receiverType,
                parameter: parameter,
                argumentIndex: argumentIndex
            )
        )
    }

    func capturedTypeForStarProjection(
        parameter: SymbolID,
        ownerTypeParameters: [SymbolID],
        origin: CapturedTypeOrigin? = nil
    ) -> TypeID {
        let upperBounds = declaredUpperBounds(for: parameter)
        let hasDependentUpperBound = upperBounds.contains { bound in
            ownerTypeParameters.contains { typeContainsTypeParam(bound, symbol: $0) }
        }
        let hasOnlyNullableAnyBound = upperBounds == [nullableAnyType]
        guard !upperBounds.isEmpty, !hasDependentUpperBound, !hasOnlyNullableAnyBound else {
            return nullableAnyType
        }

        let upperBound: TypeID
        if upperBounds.count == 1 {
            upperBound = upperBounds[0]
        } else {
            upperBound = make(.intersection(upperBounds))
        }
        return makeCapturedType(parameter: parameter, lower: nothingType, upper: upperBound, origin: origin)
    }
    private var kindToID: [TypeKind: TypeID] = [:]
    private var idToKind: [TypeKind] = []
    private var nominalDirectSupertypes: [SymbolID: [SymbolID]] = [:]
    private var nominalTypeParameterVariancesMap: [SymbolID: [TypeVariance]] = [:]
    private var nominalTypeParameterUpperBoundsMap: [SymbolID: [[TypeID]]] = [:]
    private var nominalTypeParameterSymbolsMap: [SymbolID: [SymbolID]] = [:]
    private var nominalTypeParameterOwnerMap: [SymbolID: (owner: SymbolID, index: Int)] = [:]
    private var nominalSupertypeTypeArgsMap: [SymbolID: [SymbolID: [TypeArg]]] = [:]
    private var nominalDirectSupertypesVersion: UInt64 = 0
    private var nominalSupertypeClosures: [SymbolID: NominalSupertypeClosureCacheEntry] = [:]
    private var nominalForwardLinksCache: [SymbolID: (targets: Set<SymbolID>, linkVersion: UInt64)] = [:]
    var activeNominalLUBInputs: Set<Set<TypeID>> = []
    static let maxNominalLUBDepth = 16

    public internal(set) var comparableInterfaceSymbol: SymbolID?

    public internal(set) var serializableInterfaceSymbol: SymbolID?

    public internal(set) var annotationInterfaceSymbol: SymbolID?

    public internal(set) var closeableInterfaceSymbol: SymbolID?

    public internal(set) var ioCloseableInterfaceSymbol: SymbolID?

    public internal(set) var charSequenceInterfaceSymbol: SymbolID?

    public internal(set) var closeableTypeID: TypeID?

    public internal(set) var kFunctionInterfaceSymbol: SymbolID?
    public internal(set) var kCallableInterfaceSymbol: SymbolID?

    public internal(set) var functionInterfaceSymbol: SymbolID?

    public internal(set) var functionNInterfaceSymbols: [Int: SymbolID] = [:]

    func functionNInterfaceArity(named path: [InternedString], interner: StringInterner) -> Int? {
        guard let name = path.last else { return nil }
        let kotlinName = interner.intern("kotlin")
        guard path == [name] || path == [kotlinName, name] else { return nil }

        let nameString = interner.resolve(name)
        let prefix = "Function"
        guard nameString.hasPrefix(prefix) else { return nil }
        let arityText = String(nameString.dropFirst(prefix.count))
        guard let arity = Int(arityText), String(arity) == arityText, (0...255).contains(arity) else {
            return nil
        }
        return arity
    }

    public internal(set) var suspendFunctionNInterfaceSymbols: [Int: SymbolID] = [:]

    public internal(set) var kClassInterfaceSymbol: SymbolID?

    public internal(set) var numberClassSymbol: SymbolID?

    public internal(set) var stringClassSymbol: SymbolID?

    public internal(set) var charClassSymbol: SymbolID?

    public internal(set) var anyClassSymbol: SymbolID?

    public internal(set) var arrayClassSymbol: SymbolID?

    public internal(set) var unitClassSymbol: SymbolID?


    public weak var symbolTable: SymbolTable?

    public let errorType: TypeID
    public let unitType: TypeID
    public let nothingType: TypeID
    public let nullableNothingType: TypeID
    public let anyType: TypeID
    public let nullableAnyType: TypeID
    public let booleanType: TypeID
    public let charType: TypeID
    public let intType: TypeID
    public let longType: TypeID
    public let floatType: TypeID
    public let doubleType: TypeID
    public let stringType: TypeID
    public let uintType: TypeID
    public let ulongType: TypeID
    public let ubyteType: TypeID
    public let ushortType: TypeID
    public let byteType: TypeID
    public let shortType: TypeID

    func makeSemaWorkerTypes() -> TypeSystem {
        let worker = TypeSystem()
        worker.nextCaptureIdentity = nextCaptureIdentity
        worker.kindToID = kindToID
        worker.idToKind = idToKind
        worker.nominalDirectSupertypes = nominalDirectSupertypes
        worker.nominalTypeParameterVariancesMap = nominalTypeParameterVariancesMap
        worker.nominalTypeParameterUpperBoundsMap = nominalTypeParameterUpperBoundsMap
        worker.nominalTypeParameterSymbolsMap = nominalTypeParameterSymbolsMap
        worker.nominalTypeParameterOwnerMap = nominalTypeParameterOwnerMap
        worker.nominalSupertypeTypeArgsMap = nominalSupertypeTypeArgsMap
        worker.nominalDirectSupertypesVersion = nominalDirectSupertypesVersion
        worker.nominalSupertypeClosures = nominalSupertypeClosures
        worker.nominalForwardLinksCache = nominalForwardLinksCache
        worker.comparableInterfaceSymbol = comparableInterfaceSymbol
        worker.serializableInterfaceSymbol = serializableInterfaceSymbol
        worker.annotationInterfaceSymbol = annotationInterfaceSymbol
        worker.closeableInterfaceSymbol = closeableInterfaceSymbol
        worker.ioCloseableInterfaceSymbol = ioCloseableInterfaceSymbol
        worker.charSequenceInterfaceSymbol = charSequenceInterfaceSymbol
        worker.closeableTypeID = closeableTypeID
        worker.kFunctionInterfaceSymbol = kFunctionInterfaceSymbol
        worker.kCallableInterfaceSymbol = kCallableInterfaceSymbol
        worker.functionInterfaceSymbol = functionInterfaceSymbol
        worker.functionNInterfaceSymbols = functionNInterfaceSymbols
        worker.suspendFunctionNInterfaceSymbols = suspendFunctionNInterfaceSymbols
        worker.kClassInterfaceSymbol = kClassInterfaceSymbol
        worker.numberClassSymbol = numberClassSymbol
        worker.stringClassSymbol = stringClassSymbol
        worker.charClassSymbol = charClassSymbol
        worker.anyClassSymbol = anyClassSymbol
        worker.arrayClassSymbol = arrayClassSymbol
        worker.unitClassSymbol = unitClassSymbol
        worker.symbolTable = symbolTable
        return worker
    }

    var internedTypeCount: Int { idToKind.count }

    func workerTypeKinds(since count: Int) -> [TypeKind] {
        Array(idToKind.dropFirst(count))
    }

    func mergeWorkerTypes(_ kinds: [TypeKind], startingAt count: Int) -> [TypeID: TypeID] {
        var mapping: [TypeID: TypeID] = [:]
        for (offset, kind) in kinds.enumerated() {
            let local = TypeID(rawValue: Int32(count + offset))
            mapping[local] = make(kind.mapTypes { mapping[$0] ?? $0 })
        }
        return mapping
    }

    public init() {
        errorType = TypeID(rawValue: 0)
        unitType = TypeID(rawValue: 1)
        nothingType = TypeID(rawValue: 2)
        nullableNothingType = TypeID(rawValue: 3)
        anyType = TypeID(rawValue: 4)
        nullableAnyType = TypeID(rawValue: 5)
        booleanType = TypeID(rawValue: 6)
        charType = TypeID(rawValue: 7)
        intType = TypeID(rawValue: 8)
        longType = TypeID(rawValue: 9)
        floatType = TypeID(rawValue: 10)
        doubleType = TypeID(rawValue: 11)
        stringType = TypeID(rawValue: 12)
        uintType = TypeID(rawValue: 13)
        ulongType = TypeID(rawValue: 14)
        ubyteType = TypeID(rawValue: 15)
        ushortType = TypeID(rawValue: 16)
        byteType = TypeID(rawValue: 17)
        shortType = TypeID(rawValue: 18)

        idToKind = [
            .error,
            .unit,
            .nothing(.nonNull),
            .nothing(.nullable),
            .any(.nonNull),
            .any(.nullable),
            .primitive(.boolean, .nonNull),
            .primitive(.char, .nonNull),
            .primitive(.int, .nonNull),
            .primitive(.long, .nonNull),
            .primitive(.float, .nonNull),
            .primitive(.double, .nonNull),
            .stringStruct(.nonNull),
            .primitive(.uint, .nonNull),
            .primitive(.ulong, .nonNull),
            .primitive(.ubyte, .nonNull),
            .primitive(.ushort, .nonNull),
            .primitive(.byte, .nonNull),
            .primitive(.short, .nonNull),
        ]
        kindToID = Dictionary(uniqueKeysWithValues: idToKind.enumerated().map { ($1, TypeID(rawValue: Int32($0))) })
    }

    public func isDefinitelyNonNull(_ type: TypeID) -> Bool {
        switch kind(of: type) {
        case .error:
            false
        case .nullableUnit, .platformUnit:
            false
        case .unit:
            true
        case let .nothing(n):
            n == .nonNull
        case let .any(n):
            n == .nonNull
        case let .stringStruct(n):
            n == .nonNull
        case let .primitive(_, n):
            n == .nonNull
        case let .classType(ct):
            ct.nullability == .nonNull
        case let .functionType(ft):
            ft.nullability == .nonNull
        case let .typeParam(tp):
            tp.nullability == .nonNull
        case let .kClassType(kc):
            kc.nullability == .nonNull
        case let .intersection(parts):
            !parts.contains { kind(of: $0) == .nothing(.nullable) }
                && parts.contains { isDefinitelyNonNull($0) }
        }
    }

    public func nullability(of type: TypeID) -> Nullability {
        switch kind(of: type) {
        case .error, .unit:
            .nonNull
        case .nullableUnit:
            .nullable
        case .platformUnit:
            .platformType
        case let .nothing(n), let .any(n), let .stringStruct(n), let .primitive(_, n):
            n
        case let .classType(ct):
            ct.nullability
        case let .functionType(ft):
            ft.nullability
        case let .typeParam(tp):
            tp.nullability
        case let .kClassType(kc):
            kc.nullability
        case let .intersection(parts):
            parts.contains { kind(of: $0) == .nothing(.nullable) }
                ? .nullable
                : parts.contains { nullability(of: $0) == .nonNull } ? .nonNull : .nullable
        }
    }

    public func isSigned(_ type: TypeID) -> Bool {
        switch kind(of: type) {
        case .primitive(.int, _), .primitive(.long, _), .primitive(.byte, _), .primitive(.short, _):
            true
        default:
            false
        }
    }

    public func isUnsigned(_ type: TypeID) -> Bool {
        switch kind(of: type) {
        case .primitive(.uint, _), .primitive(.ulong, _), .primitive(.ubyte, _), .primitive(.ushort, _):
            true
        default:
            false
        }
    }

    public func withNullability(_ nullability: Nullability, for type: TypeID) -> TypeID {
        switch kind(of: type) {
        case .error:
            return type
        case .unit, .nullableUnit, .platformUnit:
            switch nullability {
            case .nonNull: return unitType
            case .nullable: return make(.nullableUnit)
            case .platformType: return make(.platformUnit)
            }
        case let .intersection(parts):
            if nullability == .nonNull {
                if parts.contains(where: { kind(of: $0) == .nothing(.nullable) }) {
                    let rest = parts.filter { kind(of: $0) != .nothing(.nullable) }
                    if rest.isEmpty { return nothingType }
                    return makeNonNullable(rest.count == 1 ? rest[0] : make(.intersection(rest)))
                }
                if parts.contains(where: { isDefinitelyNonNull($0) }) {
                    return type
                }
                return make(.intersection(parts + [anyType]))
            }
            let remaining = parts.filter { kind(of: $0) != .any(.nonNull) }
            if remaining.contains(where: { kind(of: $0) == .nothing(.nullable) }) {
                return nullableNothingType
            }
            if remaining.isEmpty { return make(.any(.nullable)) }
            if remaining.count == 1 { return makeNullable(remaining[0]) }
            return make(.intersection(remaining.map { makeNullable($0) }))
        case let .nothing(existing):
            let normalized: Nullability = (nullability == .platformType) ? .nullable : nullability
            if existing == normalized { return type }
            return make(.nothing(normalized))
        case let .any(existing):
            if existing == nullability { return type }
            return make(.any(nullability))
        case let .stringStruct(existing):
            if existing == nullability { return type }
            return make(.stringStruct(nullability))
        case let .primitive(prim, existing):
            if existing == nullability { return type }
            return make(.primitive(prim, nullability))
        case let .classType(ct):
            if ct.nullability == nullability { return type }
            return make(.classType(ClassType(
                classSymbol: ct.classSymbol,
                args: ct.args,
                enclosingTypeArgs: ct.enclosingTypeArgs,
                nullability: nullability
            )))
        case let .typeParam(tp):
            if tp.nullability == nullability { return type }
            return make(.typeParam(TypeParamType(symbol: tp.symbol, nullability: nullability, capture: tp.capture)))
        case let .functionType(ft):
            if ft.nullability == nullability { return type }
            return make(.functionType(FunctionType(contextReceivers: ft.contextReceivers, receiver: ft.receiver, params: ft.params, returnType: ft.returnType, isSuspend: ft.isSuspend, isCallableReference: ft.isCallableReference, nullability: nullability)))
        case let .kClassType(kc):
            if kc.nullability == nullability { return type }
            return make(.kClassType(KClassType(argument: kc.argument, nullability: nullability)))
        }
    }

    public func makeNullable(_ type: TypeID) -> TypeID {
        withNullability(.nullable, for: type)
    }

    public func makeNonNullable(_ type: TypeID) -> TypeID {
        withNullability(.nonNull, for: type)
    }

    public func definitelyNonNullForm(of type: TypeID) -> TypeID {
        if case .typeParam = kind(of: type) {
            return make(.intersection([makeNonNullable(type), anyType]))
        }
        return makeNonNullable(type)
    }

    public func make(_ kind: TypeKind) -> TypeID {
        let normalizedKind: TypeKind = switch kind {
        case .nothing(.platformType):
            .nothing(.nullable)
        default:
            kind
        }
        if let existing = kindToID[normalizedKind] {
            return existing
        }
        let id = TypeID(rawValue: Int32(idToKind.count))
        idToKind.append(normalizedKind)
        kindToID[normalizedKind] = id
        return id
    }

    public func kind(of id: TypeID) -> TypeKind {
        let index = Int(id.rawValue)
        guard index >= 0, index < idToKind.count else {
            return .error
        }
        return idToKind[index]
    }

    public func isString(_ type: TypeID) -> Bool {
        if case .stringStruct = kind(of: type) {
            return true
        }
        return false
    }

    @discardableResult
    private func ensureImportedNominalMetadataLoaded(for symbol: SymbolID) -> Bool {
        guard let symbolTable,
              symbolTable.symbol(symbol)?.flags.contains(.importedLibrary) == true
        else {
            return false
        }
        _ = symbolTable.directSupertypes(for: symbol)
        return true
    }

    public func setNominalDirectSupertypes(_ supertypes: [SymbolID], for symbol: SymbolID) {
        if let symbolTable,
           symbolTable.deferUntilAfterImportedShellMaterializes(symbol, work: { [weak self] in
               self?.setNominalDirectSupertypes(supertypes, for: symbol)
           }) {
            return
        }
        let isImported = ensureImportedNominalMetadataLoaded(for: symbol)
        let existing = isImported ? nominalDirectSupertypes[symbol] ?? [] : []
        let unique = Array(Set(existing + supertypes)).sorted(by: { $0.rawValue < $1.rawValue })
        let changed = (nominalDirectSupertypes[symbol] ?? []) != unique
        nominalDirectSupertypes[symbol] = unique
        if changed {
            nominalDirectSupertypesVersion &+= 1
        }
    }

    public func directNominalSupertypes(for symbol: SymbolID) -> [SymbolID] {
        ensureImportedNominalMetadataLoaded(for: symbol)
        return nominalDirectSupertypes[symbol] ?? []
    }

    func nominalSupertypeClosure(for symbol: SymbolID) -> NominalSupertypeClosureCacheEntry {
        while true {
            let linkVersion = currentNominalLinkVersion()
            if let cached = nominalSupertypeClosures[symbol],
               cached.directSupertypesVersion == nominalDirectSupertypesVersion,
               cached.linkVersion == linkVersion
            {
                return cached
            }

            let directSupertypesVersion = nominalDirectSupertypesVersion
            var symbols: Set<SymbolID> = [symbol]
            var queue = directNominalSupertypes(for: symbol)
            var head = 0
            while head < queue.count {
                let current = queue[head]
                head += 1
                if symbols.insert(current).inserted {
                    queue.append(contentsOf: directNominalSupertypes(for: current))
                }
            }

            var linkedTargets: Set<SymbolID> = []
            for reachable in symbols {
                linkedTargets.formUnion(nominalForwardLinks(for: reachable))
            }

            guard nominalDirectSupertypesVersion == directSupertypesVersion,
                  currentNominalLinkVersion() == linkVersion
            else {
                continue
            }
            let entry = NominalSupertypeClosureCacheEntry(
                symbols: symbols,
                linkedTargets: linkedTargets,
                directSupertypesVersion: directSupertypesVersion,
                linkVersion: linkVersion
            )
            nominalSupertypeClosures[symbol] = entry
            return entry
        }
    }

    func nominalForwardLinks(for symbol: SymbolID) -> Set<SymbolID> {
        guard let symbolTable else { return [] }
        let linkVersion = symbolTable.nominalLinkMutationVersion
        if let cached = nominalForwardLinksCache[symbol], cached.linkVersion == linkVersion {
            return cached.targets
        }

        var targets: Set<SymbolID> = []
        if let actual = symbolTable.actualSymbol(for: symbol) {
            targets.insert(actual)
        }
        if let target = actualTypeAliasTargetNominalSymbol(for: symbol, symbols: symbolTable) {
            targets.insert(target)
        }

        if symbolTable.nominalLinkMutationVersion == linkVersion {
            nominalForwardLinksCache[symbol] = (targets: targets, linkVersion: linkVersion)
        }
        return targets
    }

    private func currentNominalLinkVersion() -> UInt64? {
        guard let symbolTable else { return nil }
        return symbolTable.nominalLinkMutationVersion
    }

    public func setNominalTypeParameterVariances(_ variances: [TypeVariance], for symbol: SymbolID) {
        if let symbolTable,
           symbolTable.deferUntilAfterImportedShellMaterializes(symbol, work: { [weak self] in
               self?.setNominalTypeParameterVariances(variances, for: symbol)
           }) {
            return
        }
        ensureImportedNominalMetadataLoaded(for: symbol)
        nominalTypeParameterVariancesMap[symbol] = variances
    }

    public func nominalTypeParameterVariances(for symbol: SymbolID) -> [TypeVariance] {
        ensureImportedNominalMetadataLoaded(for: symbol)
        return nominalTypeParameterVariancesMap[symbol] ?? []
    }

    public func setNominalTypeParameterUpperBounds(_ bounds: [[TypeID]], for symbol: SymbolID) {
        nominalTypeParameterUpperBoundsMap[symbol] = bounds
    }

    public func nominalTypeParameterUpperBounds(for symbol: SymbolID) -> [[TypeID]]? {
        ensureImportedNominalMetadataLoaded(for: symbol)
        return nominalTypeParameterUpperBoundsMap[symbol]
    }

    public func setNominalTypeParameterSymbols(_ symbols: [SymbolID], for nominal: SymbolID) {
        if let symbolTable,
           symbolTable.deferUntilAfterImportedShellMaterializes(nominal, work: { [weak self] in
               self?.setNominalTypeParameterSymbols(symbols, for: nominal)
           }) {
            return
        }
        ensureImportedNominalMetadataLoaded(for: nominal)
        nominalTypeParameterSymbolsMap[nominal] = symbols
        for (index, parameter) in symbols.enumerated() {
            nominalTypeParameterOwnerMap[parameter] = (nominal, index)
        }
    }

    public func nominalTypeParameterSymbols(for nominal: SymbolID) -> [SymbolID] {
        ensureImportedNominalMetadataLoaded(for: nominal)
        return nominalTypeParameterSymbolsMap[nominal] ?? []
    }

    /// Declared upper bounds for a type parameter. Imported declarations keep
    /// producer-local bounds on the owning nominal rather than the per-symbol
    /// map (synthetic metadata ids are not unique across artifacts), so a
    /// per-symbol miss resolves through the nominal registration — matching
    /// `substitutingCovariantStarUpperBounds`.
    public func declaredUpperBounds(for symbol: SymbolID) -> [TypeID] {
        let symbolBounds = symbolTable?.typeParameterUpperBounds(for: symbol) ?? []
        guard symbolBounds.isEmpty,
              let owner = nominalTypeParameterOwnerMap[symbol],
              let nominalBounds = nominalTypeParameterUpperBounds(for: owner.owner),
              nominalBounds.indices.contains(owner.index)
        else {
            return symbolBounds
        }
        return nominalBounds[owner.index]
    }

    public func enclosingTypeParameterSymbols(for nominal: SymbolID) -> [SymbolID] {
        guard let symbolTable,
              symbolTable.symbol(nominal)?.flags.contains(.innerClass) == true
        else {
            return []
        }

        var owners: [SymbolID] = []
        var currentOwner = symbolTable.parentSymbol(for: nominal)
        while let owner = currentOwner, let ownerSymbol = symbolTable.symbol(owner) {
            owners.append(owner)
            guard ownerSymbol.flags.contains(.innerClass) else { break }
            currentOwner = symbolTable.parentSymbol(for: owner)
        }
        return owners.reversed().flatMap { nominalTypeParameterSymbols(for: $0) }
    }

    public func allTypeParameterSymbols(for nominal: SymbolID) -> [SymbolID] {
        enclosingTypeParameterSymbols(for: nominal) + nominalTypeParameterSymbols(for: nominal)
    }

    public func implicitInnerClassEnclosingArgs(
        for nominal: SymbolID,
        enclosingInstanceTypes: [TypeID] = []
    ) -> [TypeArg] {
        let enclosingParameters = enclosingTypeParameterSymbols(for: nominal)
        guard !enclosingParameters.isEmpty,
              let outerOwner = symbolTable?.parentSymbol(for: nominal)
        else {
            return []
        }
        for instanceType in enclosingInstanceTypes {
            guard case let .classType(receiverClass) = kind(of: makeNonNullable(instanceType)),
                  let lifted = liftedNominalSupertypeArgs(from: receiverClass, to: outerOwner),
                  lifted.count == enclosingParameters.count
            else {
                continue
            }
            return lifted
        }
        return []
    }

    public func enclosingTypeParameterVariances(for nominal: SymbolID) -> [TypeVariance] {
        guard let symbolTable,
              symbolTable.symbol(nominal)?.flags.contains(.innerClass) == true
        else {
            return []
        }

        var owners: [SymbolID] = []
        var currentOwner = symbolTable.parentSymbol(for: nominal)
        while let owner = currentOwner, let ownerSymbol = symbolTable.symbol(owner) {
            owners.append(owner)
            guard ownerSymbol.flags.contains(.innerClass) else { break }
            currentOwner = symbolTable.parentSymbol(for: owner)
        }
        return owners.reversed().flatMap { owner in
            normalizedNominalVariances(
                for: owner,
                arity: max(
                    nominalTypeParameterSymbols(for: owner).count,
                    nominalTypeParameterVariances(for: owner).count
                )
            )
        }
    }

    public func allTypeParameterVariances(for nominal: SymbolID, fallbackArity: Int = 0) -> [TypeVariance] {
        let declaredArity = max(
            nominalTypeParameterSymbols(for: nominal).count,
            nominalTypeParameterVariances(for: nominal).count,
            fallbackArity
        )
        return enclosingTypeParameterVariances(for: nominal)
            + normalizedNominalVariances(for: nominal, arity: declaredArity)
    }

    public func allTypeArguments(for classType: ClassType) -> [TypeArg] {
        classType.enclosingTypeArgs + classType.args
    }

    public func classType(
        for nominal: SymbolID,
        arguments: [TypeArg],
        nullability: Nullability = .nonNull
    ) -> ClassType {
        let enclosingCount = min(enclosingTypeParameterSymbols(for: nominal).count, arguments.count)
        return ClassType(
            classSymbol: nominal,
            args: Array(arguments.dropFirst(enclosingCount)),
            enclosingTypeArgs: Array(arguments.prefix(enclosingCount)),
            nullability: nullability
        )
    }

    public func liftedNominalSupertypeArgs(
        from child: ClassType,
        to parent: SymbolID
    ) -> [TypeArg]? {
        if child.classSymbol == parent {
            return allTypeArguments(for: child)
        }
        return liftedNominalSupertypeArgs(
            from: child.classSymbol,
            childArgs: allTypeArguments(for: child),
            to: parent,
            includeEnclosingParameters: true
        )
    }

    public func typeContainsTypeParam(_ type: TypeID, symbol: SymbolID) -> Bool {
        typeContainsTypeParam(type) { $0.symbol == symbol }
    }

    public func typeContainsTypeParamThroughUpperBounds(_ type: TypeID, symbol: SymbolID) -> Bool {
        guard let symbolTable else {
            return typeContainsTypeParam(type, symbol: symbol)
        }

        var visitedTypeParameters: Set<SymbolID> = []
        func contains(_ candidate: TypeID) -> Bool {
            typeContainsTypeParam(candidate) { typeParameter in
                if typeParameter.symbol == symbol {
                    return true
                }
                guard visitedTypeParameters.insert(typeParameter.symbol).inserted else {
                    return false
                }
                return symbolTable.typeParameterUpperBounds(for: typeParameter.symbol).contains(where: contains)
            }
        }

        return contains(type)
    }

    public func typeContainsAnyTypeParam(_ type: TypeID) -> Bool {
        typeContainsTypeParam(type) { _ in true }
    }

    private func typeContainsTypeParam(_ type: TypeID, where predicate: (TypeParamType) -> Bool) -> Bool {
        switch kind(of: type) {
        case let .typeParam(tp):
            return tp.capture == nil && predicate(tp)
        case let .classType(ct):
            return allTypeArguments(for: ct).contains { arg in
                switch arg {
                case let .invariant(inner), let .out(inner), let .in(inner):
                    typeContainsTypeParam(inner, where: predicate)
                case .star:
                    false
                }
            }
        case let .functionType(ft):
            if ft.contextReceivers.contains(where: { typeContainsTypeParam($0, where: predicate) }) {
                return true
            }
            if let receiver = ft.receiver, typeContainsTypeParam(receiver, where: predicate) {
                return true
            }
            if ft.params.contains(where: { typeContainsTypeParam($0, where: predicate) }) {
                return true
            }
            return typeContainsTypeParam(ft.returnType, where: predicate)
        case let .kClassType(kc):
            return typeContainsTypeParam(kc.argument, where: predicate)
        case let .intersection(parts):
            return parts.contains { typeContainsTypeParam($0, where: predicate) }
        default:
            return false
        }
    }

    public func setNominalSupertypeTypeArgs(_ args: [TypeArg], for child: SymbolID, supertype parent: SymbolID) {
        if let symbolTable,
           symbolTable.deferUntilAfterImportedShellMaterializes(child, work: { [weak self] in
               self?.setNominalSupertypeTypeArgs(args, for: child, supertype: parent)
           }) {
            return
        }
        ensureImportedNominalMetadataLoaded(for: child)
        nominalSupertypeTypeArgsMap[child, default: [:]][parent] = args
    }

    public func nominalSupertypeTypeArgs(for child: SymbolID, supertype parent: SymbolID) -> [TypeArg] {
        ensureImportedNominalMetadataLoaded(for: child)
        return nominalSupertypeTypeArgsMap[child]?[parent] ?? []
    }

    public func makeKClassType(argument: TypeID, nullability: Nullability = .nonNull) -> TypeID {
        make(.kClassType(KClassType(argument: argument, nullability: nullability)))
    }

    public func liftedNominalSupertypeArgs(
        from child: SymbolID,
        childArgs: [TypeArg],
        to parent: SymbolID
    ) -> [TypeArg]? {
        guard child != parent else { return childArgs }
        return liftedNominalSupertypeArgs(
            from: child,
            childArgs: childArgs,
            to: parent,
            includeEnclosingParameters: false
        )
    }

    private func liftedNominalSupertypeArgs(
        from child: SymbolID,
        childArgs: [TypeArg],
        to parent: SymbolID,
        includeEnclosingParameters: Bool
    ) -> [TypeArg]? {

        // KUU-809: the direct-supertype graph is attacker-controlled when it
        // comes from `.kklib` metadata, so this walk must not consume native
        // call-stack frames per level. The explicit stack below performs the
        // same DFS the recursive version did: `target` is checked before the
        // visited mark, and children are explored left-to-right depth-first
        // (reversed pushes keep the leftmost child on top of the stack).
        var visited: Set<SymbolID> = []
        let substitutedChildArgs = substitutingCovariantStarUpperBounds(childArgs, for: child)
        var stack: [(symbol: SymbolID, args: [TypeArg])] = [(child, substitutedChildArgs)]
        while let (current, currentArgs) = stack.popLast() {
            if current == parent {
                return currentArgs
            }
            guard visited.insert(current).inserted else {
                continue
            }
            for directSupertype in directNominalSupertypes(for: current).reversed() {
                let directArgsTemplate = nominalSupertypeTypeArgs(for: current, supertype: directSupertype)
                let substitutedDirectArgs = directArgsTemplate.map {
                    substituteNominalTypeArg(
                        $0,
                        owner: current,
                        ownerArgs: currentArgs,
                        includeEnclosingParameters: includeEnclosingParameters
                    )
                }
                stack.append((directSupertype, substitutedDirectArgs))
            }
        }
        return nil
    }

    func substitutingCovariantStarUpperBounds(_ args: [TypeArg], for owner: SymbolID) -> [TypeArg] {
        guard args.contains(where: { if case .star = $0 { true } else { false } }) else {
            return args
        }
        let parameters = nominalTypeParameterSymbols(for: owner)
        guard !parameters.isEmpty else { return args }
        let variances = normalizedNominalVariances(for: owner, arity: args.count)
        guard args.indices.contains(where: { index in
            guard case .star = args[index] else { return false }
            return variances[index] == .out
        })
        else {
            return args
        }

        let variables = makeTypeVarBySymbol(parameters)
        var substitution: [TypeVarID: TypeID] = [:]
        var unresolvedStars: [SymbolID: TypeVarID] = [:]
        for (parameter, argument) in zip(parameters, args) {
            guard let variable = variables[parameter] else { continue }
            switch argument {
            case let .invariant(type), let .out(type):
                substitution[variable] = type
            case .in, .star:
                unresolvedStars[parameter] = variable
            }
        }

        var substitutedArgs = args
        let overloadResolver = OverloadResolver()
        for index in args.indices where parameters.indices.contains(index) {
            guard case .star = args[index], variances[index] == .out,
                  let variable = variables[parameters[index]]
            else {
                continue
            }

            let symbolBounds = symbolTable?.typeParameterUpperBounds(for: parameters[index]) ?? []
            let nominalBoundsByParameter = nominalTypeParameterUpperBounds(for: owner) ?? []
            let nominalBounds = nominalBoundsByParameter.indices.contains(index)
                ? nominalBoundsByParameter[index] : []
            let declaredBounds = symbolBounds.isEmpty ? nominalBounds : symbolBounds
            let substitutedBounds = declaredBounds.map {
                substituteTypeParameters(in: $0, substitution: substitution, typeVarBySymbol: variables)
            }
            let readableBounds = substitutedBounds.filter {
                !overloadResolver.containsTypeVariable($0, typeVarBySymbol: unresolvedStars, typeSystem: self)
            }
            guard declaredBounds.isEmpty || !readableBounds.isEmpty else { continue }
            let upperBound = readableBounds.isEmpty ? nullableAnyType : glb(readableBounds)
            substitution[variable] = upperBound
            substitutedArgs[index] = .invariant(upperBound)
        }
        return substitutedArgs
    }

    public func narrowedSubtypeArgs(
        forSubtype subtype: SymbolID,
        givenSupertype supertype: SymbolID,
        supertypeArgs: [TypeArg]
    ) -> [TypeArg]? {
        let subtypeParams = nominalTypeParameterSymbols(for: subtype)
        guard !subtypeParams.isEmpty else { return nil }
        let symbolicArgs: [TypeArg] = subtypeParams.map {
            .invariant(make(.typeParam(TypeParamType(symbol: $0, nullability: .nonNull))))
        }
        guard let symbolicSupertypeArgs = liftedNominalSupertypeArgs(
            from: subtype, childArgs: symbolicArgs, to: supertype
        ), symbolicSupertypeArgs.count == supertypeArgs.count else {
            return nil
        }
        var resolved: [SymbolID: TypeID] = [:]
        for (symbolicArg, concreteArg) in zip(symbolicSupertypeArgs, supertypeArgs) {
            let symbolicType: TypeID?
            switch symbolicArg {
            case let .invariant(t), let .out(t), let .in(t): symbolicType = t
            case .star: symbolicType = nil
            }
            guard let symbolicType,
                  case let .typeParam(tp) = kind(of: symbolicType),
                  subtypeParams.contains(tp.symbol)
            else {
                continue
            }
            let concreteType: TypeID?
            switch concreteArg {
            case let .invariant(t), let .out(t), let .in(t): concreteType = t
            case .star: concreteType = nil
            }
            guard let concreteType else { continue }
            resolved[tp.symbol] = concreteType
        }
        guard !resolved.isEmpty else { return nil }
        return subtypeParams.map { symbol in
            resolved[symbol].map { TypeArg.invariant($0) } ?? .star
        }
    }

    private func substituteNominalTypeArg(
        _ arg: TypeArg,
        owner: SymbolID,
        ownerArgs: [TypeArg],
        includeEnclosingParameters: Bool = false
    ) -> TypeArg {
        switch arg {
        case let .invariant(type):
            .invariant(substituteNominalType(
                type, owner: owner, ownerArgs: ownerArgs,
                includeEnclosingParameters: includeEnclosingParameters
            ))
        case let .out(type):
            .out(substituteNominalType(
                type, owner: owner, ownerArgs: ownerArgs,
                includeEnclosingParameters: includeEnclosingParameters
            ))
        case let .in(type):
            .in(substituteNominalType(
                type, owner: owner, ownerArgs: ownerArgs,
                includeEnclosingParameters: includeEnclosingParameters
            ))
        case .star:
            .star
        }
    }

    public func substituteNominalTypeParameters(
        in type: TypeID,
        owner: SymbolID,
        ownerArgs: [TypeArg]
    ) -> TypeID {
        substituteNominalType(type, owner: owner, ownerArgs: ownerArgs, includeEnclosingParameters: false)
    }

    private func substituteNominalType(
        _ type: TypeID,
        owner: SymbolID,
        ownerArgs: [TypeArg],
        includeEnclosingParameters: Bool
    ) -> TypeID {
        let typeParamSymbols = includeEnclosingParameters
            ? allTypeParameterSymbols(for: owner)
            : nominalTypeParameterSymbols(for: owner)
        guard !typeParamSymbols.isEmpty, !ownerArgs.isEmpty else {
            return type
        }

        let typeVarBySymbol = makeTypeVarBySymbol(typeParamSymbols)
        var substitution: [TypeVarID: TypeID] = [:]
        for (index, symbol) in typeParamSymbols.enumerated() {
            guard index < ownerArgs.count,
                  let variable = typeVarBySymbol[symbol]
            else {
                continue
            }
            switch ownerArgs[index] {
            case let .invariant(inner), let .out(inner), let .in(inner):
                substitution[variable] = inner
            case .star:
                substitution[variable] = capturedTypeForStarProjection(
                    parameter: symbol,
                    ownerTypeParameters: typeParamSymbols
                )
            }
        }

        guard !substitution.isEmpty else {
            return type
        }
        return substituteTypeParameters(
            in: type,
            substitution: substitution,
            typeVarBySymbol: typeVarBySymbol
        )
    }
}

extension TypeSystem {
    func makeSemaSnapshot() -> TypeSystemSemaSnapshot {
        TypeSystemSemaSnapshot(
            nextCaptureIdentity: nextCaptureIdentity,
            types: idToKind.enumerated().map { index, kind in
                TypeSystemSemaSnapshot.TypeEntry(id: TypeID(rawValue: Int32(index)), kind: kind)
            },
            nominalDirectSupertypes: nominalDirectSupertypes,
            nominalTypeParameterVariances: nominalTypeParameterVariancesMap,
            nominalTypeParameterUpperBounds: nominalTypeParameterUpperBoundsMap,
            nominalTypeParameterSymbols: nominalTypeParameterSymbolsMap,
            nominalSupertypeTypeArgs: nominalSupertypeTypeArgsMap,
            comparableInterfaceSymbol: comparableInterfaceSymbol,
            serializableInterfaceSymbol: serializableInterfaceSymbol,
            annotationInterfaceSymbol: annotationInterfaceSymbol,
            closeableInterfaceSymbol: closeableInterfaceSymbol,
            ioCloseableInterfaceSymbol: ioCloseableInterfaceSymbol,
            charSequenceInterfaceSymbol: charSequenceInterfaceSymbol,
            closeableTypeID: closeableTypeID,
            kFunctionInterfaceSymbol: kFunctionInterfaceSymbol,
            kCallableInterfaceSymbol: kCallableInterfaceSymbol,
            functionInterfaceSymbol: functionInterfaceSymbol,
            functionNInterfaceSymbols: functionNInterfaceSymbols,
            suspendFunctionNInterfaceSymbols: suspendFunctionNInterfaceSymbols,
            kClassInterfaceSymbol: kClassInterfaceSymbol,
            numberClassSymbol: numberClassSymbol,
            stringClassSymbol: stringClassSymbol,
            charClassSymbol: charClassSymbol,
            anyClassSymbol: anyClassSymbol,
            arrayClassSymbol: arrayClassSymbol,
            unitClassSymbol: unitClassSymbol
        )
    }

}
