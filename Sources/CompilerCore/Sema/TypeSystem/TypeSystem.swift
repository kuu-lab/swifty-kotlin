public final class TypeSystem {
    private var nextCaptureIdentity = 0

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

    /// Preserves informative upper bounds when a star projection crosses a
    /// nominal substitution. Trivial or dependent bounds fall back to `Any?`.
    func capturedTypeForStarProjection(parameter: SymbolID, ownerTypeParameters: [SymbolID]) -> TypeID {
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
        return makeCapturedType(parameter: parameter, lower: nothingType, upper: upperBound)
    }
    private var kindToID: [TypeKind: TypeID] = [:]
    private var idToKind: [TypeKind] = []
    private var nominalDirectSupertypes: [SymbolID: [SymbolID]] = [:]
    private var nominalTypeParameterVariancesMap: [SymbolID: [TypeVariance]] = [:]
    private var nominalTypeParameterUpperBoundsMap: [SymbolID: [[TypeID]]] = [:]
    private var nominalTypeParameterSymbolsMap: [SymbolID: [SymbolID]] = [:]
    /// Reverse lookup from a nominal's type-parameter symbol to its owning
    /// nominal and position. Imported metadata keys bounds on the owner, so
    /// star-projection bounds queries resolve them through this map.
    private var nominalTypeParameterOwnerMap: [SymbolID: (owner: SymbolID, index: Int)] = [:]
    private var nominalSupertypeTypeArgsMap: [SymbolID: [SymbolID: [TypeArg]]] = [:]
    // Break recursive argument joins such as A : Producer<A>, B : Producer<B>.
    var activeNominalLUBInputs: Set<Set<TypeID>> = []
    static let maxNominalLUBDepth = 16

    public internal(set) var comparableInterfaceSymbol: SymbolID?

    public internal(set) var annotationInterfaceSymbol: SymbolID?

    public internal(set) var closeableInterfaceSymbol: SymbolID?

    /// The symbol ID of the source-backed `kotlin.io.Closeable` interface.
    /// Used to register synthetic IO nominals as subtypes of `Closeable` (which itself
    /// extends `AutoCloseable`) so that user code can assign a stream/reader to a
    /// `Closeable`-typed variable while `.use {}` lowering resolves `close()` from
    /// the root `AutoCloseable` interface.
    public internal(set) var ioCloseableInterfaceSymbol: SymbolID?

    public internal(set) var charSequenceInterfaceSymbol: SymbolID?

    /// Cached TypeID for source-backed `kotlin.AutoCloseable` (non-null).
    /// Avoids repeated `make(...)` allocations on the hot path in `isCloseableReceiver`.
    public internal(set) var closeableTypeID: TypeID?

    /// The symbol ID of the synthetic `kotlin.reflect.KFunction` interface (STDLIB-REFLECT-063).
    /// Used in subtyping to allow function types to be assigned to KFunction<R> variables.
    public internal(set) var kFunctionInterfaceSymbol: SymbolID?
    public internal(set) var kCallableInterfaceSymbol: SymbolID?

    /// The symbol of the bundled `kotlin.Function<R>` interface.
    /// Function types are subtypes of this source-backed common function interface.
    public internal(set) var functionInterfaceSymbol: SymbolID?

    /// The symbols of the synthetic `kotlin.Function.FunctionN` interfaces,
    /// keyed by arity. Populated by `registerSyntheticFunctionInterface` so
    /// subtyping can treat a function type as a subtype of the matching-arity
    /// `FunctionN` nominal and vice versa (KUU-1084).
    public internal(set) var functionNInterfaceSymbols: [Int: SymbolID] = [:]

    /// The symbols of the synthetic `kotlin.coroutines.SuspendFunctionN`
    /// interfaces, keyed by arity. These keep suspend function types distinct
    /// from regular `FunctionN` types while exposing their suspend `invoke`.
    public internal(set) var suspendFunctionNInterfaceSymbols: [Int: SymbolID] = [:]

    public internal(set) var kClassInterfaceSymbol: SymbolID?

    /// The symbol ID of the synthetic `kotlin.Number` abstract class, set during header registration.
    /// Used in subtyping to allow numeric primitives (Int, Long, …) to satisfy `Number` upper bounds.
    public internal(set) var numberClassSymbol: SymbolID?

    /// The symbol ID of the synthetic `kotlin.String` `.class`-kind symbol registered by
    /// `HeaderHelpers.ensureClassSymbol` purely to host member declarations (CharSequence
    /// conformance, byte-array constructors). Scope-based lookup for `String::class` finds
    /// this symbol before ever reaching the builtin-name fallback, so `classRefTargetType`
    /// resolves to `.classType(ClassType(classSymbol: stringClassSymbol))` — a disguised
    /// nominal type distinct from the canonical `stringType` (`.stringStruct`) that an
    /// ordinary `is String` check resolves to. `isSubtype` normalizes the disguise back to
    /// `stringType` so the two representations compare as equal.
    public internal(set) var stringClassSymbol: SymbolID?

    /// The symbol ID of the synthetic `kotlin.Char` `.class`-kind symbol (hosts companion
    /// helpers). Same disguise-vs-canonical-`charType` situation as `stringClassSymbol`.
    public internal(set) var charClassSymbol: SymbolID?

    /// The symbol ID of the synthetic `kotlin.Any` `.class`-kind symbol (hosts toString/
    /// hashCode/equals member declarations). Same disguise-vs-canonical-`anyType` situation
    /// as `stringClassSymbol`.
    public internal(set) var anyClassSymbol: SymbolID?

    /// The source-backed `kotlin.Unit` object symbol used to resolve members on
    /// the builtin Unit value representation.
    public internal(set) var unitClassSymbol: SymbolID?


    /// Symbol table reference for SAM (fun interface) subtyping. Set during DataFlowSemaPhase.
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

    /// Copy-on-write snapshot taken at the module barrier. Nominal metadata
    /// is frozen while independent scalar bodies run; new worker TypeIDs never
    /// escape without canonicalization on the module thread.
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
        worker.comparableInterfaceSymbol = comparableInterfaceSymbol
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
        worker.unitClassSymbol = unitClassSymbol
        worker.symbolTable = symbolTable
        return worker
    }

    var internedTypeCount: Int { idToKind.count }

    func workerTypeKinds(since count: Int) -> [TypeKind] {
        Array(idToKind.dropFirst(count))
    }

    /// The worker snapshot prefix is identical to the module prefix. Replay
    /// only its appended kinds, mapping references to preceding local kinds.
    /// Calling this at each declaration's source position preserves ID order.
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
        kindToID = [
            .error: errorType,
            .unit: unitType,
            .nothing(.nonNull): nothingType,
            .nothing(.nullable): nullableNothingType,
            .any(.nonNull): anyType,
            .any(.nullable): nullableAnyType,
            .primitive(.boolean, .nonNull): booleanType,
            .primitive(.char, .nonNull): charType,
            .primitive(.int, .nonNull): intType,
            .primitive(.long, .nonNull): longType,
            .primitive(.float, .nonNull): floatType,
            .primitive(.double, .nonNull): doubleType,
            .stringStruct(.nonNull): stringType,
            .primitive(.uint, .nonNull): uintType,
            .primitive(.ulong, .nonNull): ulongType,
            .primitive(.ubyte, .nonNull): ubyteType,
            .primitive(.ushort, .nonNull): ushortType,
            .primitive(.byte, .nonNull): byteType,
            .primitive(.short, .nonNull): shortType,
        ]
    }

    /// Returns `true` when the type is definitely non-nullable, either because
    /// it is inherently non-null or because it is an intersection containing `Any`.
    /// `T & Any` is Kotlin's "definitely non-nullable" type – even when T's upper
    /// bound is nullable, the intersection guarantees non-nullability.
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
            // `Nothing? & T` holds only `null` — it is not definitely
            // non-null even though `T`'s marker says non-null (KUU-2693).
            !parts.contains { kind(of: $0) == .nothing(.nullable) }
                // T & Any is definitely non-null; any part being non-null suffices
                && parts.contains { isDefinitelyNonNull($0) }
        }
    }

    /// Nullability of an intersection type.
    /// An intersection that contains `Any` (non-null) is definitely non-nullable.
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
            // `Nothing? & T` is a null-holding type — its only value is
            // `null` in the `x == null` narrowing that produces it (KUU-2693).
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
                // Drop the null conjunct so the parameter's identity
                // survives joins: `Nothing? & T` → `T` (KUU-2693).
                if parts.contains(where: { kind(of: $0) == .nothing(.nullable) }) {
                    let rest = parts.filter { kind(of: $0) != .nothing(.nullable) }
                    if rest.isEmpty { return nothingType }
                    return makeNonNullable(rest.count == 1 ? rest[0] : make(.intersection(rest)))
                }
                if parts.contains(where: { isDefinitelyNonNull($0) }) {
                    return type
                }
                // Add Any to make it definitely non-null
                return make(.intersection(parts + [anyType]))
            }
            // `.nullable` drops the `Any` non-null conjunct and re-applies
            // nullability to what remains — `T & Any` becomes `T?`, matching
            // Kotlin's nullable view of a definitely-non-null parameter.
            // A `Nothing?` conjunct absorbs the result: `Nothing? & T?` can
            // only hold `null` (KUU-2693).
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

    /// The definitely-non-null view of `type`: `T & Any` for a type
    /// parameter (Kotlin's `T & Any` refinement used by `x != null` and
    /// `x ?: ...` smart casts), otherwise the plain non-null marker. A bare
    /// `T` stays null-capable through its implicit `Any?` bound (KUU-2693).
    public func definitelyNonNullForm(of type: TypeID) -> TypeID {
        if case .typeParam = kind(of: type) {
            return make(.intersection([makeNonNullable(type), anyType]))
        }
        return makeNonNullable(type)
    }

    public func make(_ kind: TypeKind) -> TypeID {
        // Keep Nothing as a two-state type; Nothing! is normalized to Nothing?.
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
        nominalDirectSupertypes[symbol] = unique
    }

    public func directNominalSupertypes(for symbol: SymbolID) -> [SymbolID] {
        ensureImportedNominalMetadataLoaded(for: symbol)
        return nominalDirectSupertypes[symbol] ?? []
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

    /// Owning nominal and declaration-site index of a type-parameter symbol,
    /// when it was registered through `setNominalTypeParameterSymbols`.
    public func nominalTypeParameterOwner(for symbol: SymbolID) -> (owner: SymbolID, index: Int)? {
        nominalTypeParameterOwnerMap[symbol]
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

    /// Type parameters captured from an `inner` class's enclosing class chain.
    /// A static nested class forms a boundary, so its enclosing generic owners
    /// are not included.
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

    /// Lifts a class type while retaining captured enclosing arguments for a
    /// direct receiver-owner match. Inherited supertypes continue to use the
    /// nominal inheritance map, whose arguments are expressed in the owner's
    /// own type parameters.
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

    /// Returns whether a type contains a type parameter directly or through the upper bounds of its type parameters.
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

    /// Replaces readable covariant star projections with their effective upper
    /// bounds. Non-covariant projections stay unchanged, and bounds that depend
    /// on unresolved projected parameters do not narrow the result.
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
                // An in-projection supplies only a lower bound, so it cannot
                // narrow another parameter's readable upper bound.
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

    /// Infers `subtype`'s own type arguments for a smart cast from a known
    /// supertype instantiation, when `subtype` was checked for with no
    /// explicit type arguments (`this is List`, not `this is List<Int>`).
    ///
    /// Kotlin's smart cast for this pattern is only sound because `subtype`'s
    /// declared path to `supertype` passes each of `supertype`'s type
    /// arguments straight through as one of `subtype`'s own bare type
    /// parameters (e.g. `List<out E> : Collection<E>`, `Collection<E> :
    /// Iterable<E>`, so a value known to be `Iterable<T>` that is also a
    /// `List` must be a `List<T>`, never `List<*>`). This is checked
    /// structurally: `subtype` is symbolically applied to its own type
    /// parameters and lifted to `supertype` via `liftedNominalSupertypeArgs`;
    /// any resulting position that isn't a bare reference back to one of
    /// `subtype`'s own parameters (e.g. a declared path like `Foo<X> :
    /// Bar<List<X>>`, which doesn't determine `X` from `Bar`'s argument
    /// alone) is left unresolved (`.star`), matching today's conservative
    /// behavior for that parameter.
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
