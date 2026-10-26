import Foundation

/// ID-independent references used by declaration-level Sema snapshots
/// (KUU-3019, step 1 of "serialize and restore per-declaration Sema results").
///
/// `SymbolID`, `TypeID` and `ExprID` are encounter-order integers, so a stored
/// snapshot can never refer to them directly. A snapshot instead stores
/// names (`SnapshotSymbol`), structure (`SnapshotType`) and body-relative positions, and
/// the codec resolves those back against whichever compilation is loading it.
public indirect enum SnapshotSymbol: Codable, Hashable, Sendable {
    /// A symbol reachable by name from any compilation. `key` is the canonical
    /// key shared with `KIRFunctionFingerprint`; `fqName` is kept separately so
    /// the loader can narrow candidates with `SymbolTable.lookupAll`.
    case global(key: String, fqName: [String])
    /// A symbol declared inside the snapshotted declaration, numbered by
    /// definition order among that declaration's local symbols.
    case local(Int)
    /// A lambda parameter. These have no symbol-table entry: the type checker
    /// derives their ID from the lambda's `ExprID` (`-1_000_000 - expr * 256 -
    /// slot`), so the snapshot stores the lambda's body-relative position and
    /// the parameter slot instead.
    case lambdaParameter(lambdaIndex: Int, slot: Int)
}

public indirect enum SnapshotTypeArg: Codable, Hashable, Sendable {
    case invariant(SnapshotType)
    case out(SnapshotType)
    case `in`(SnapshotType)
    case star
}

public indirect enum SnapshotType: Codable, Hashable, Sendable {
    case error
    case unit
    case nullableUnit
    case platformUnit
    case nothing(Nullability)
    case any(Nullability)
    case stringStruct(Nullability)
    case primitive(PrimitiveType, Nullability)
    case classType(SnapshotSymbol, args: [SnapshotTypeArg], enclosingArgs: [SnapshotTypeArg], Nullability)
    case typeParam(SnapshotSymbol, Nullability)
    case function(
        contextReceivers: [SnapshotType], receiver: SnapshotType?, params: [SnapshotType], returnType: SnapshotType,
        isSuspend: Bool, isCallableReference: Bool, nullability: Nullability, throwsTypes: [SnapshotType]
    )
    case intersection([SnapshotType])
    case kClass(SnapshotType, Nullability)
}

public struct SnapshotIndexPair: Codable, Hashable, Sendable {
    public let from: Int
    public let to: Int
}

public struct SnapshotCallBinding: Codable, Hashable, Sendable {
    public let chosenCallee: SnapshotSymbol
    public let substitutedTypeArguments: [SnapshotType]
    /// Sorted by `from`; JSON dictionaries with integer keys are neither
    /// ordered nor portable.
    public let parameterMapping: [SnapshotIndexPair]
    /// Sorted by `from`; these source arguments supply context parameters.
    public let contextParameterArgumentMapping: [SnapshotIndexPair]
    public let defaultArgumentOwner: SnapshotSymbol?
    public let dispatchReceiverSymbol: SnapshotSymbol?
    public let isCallableReferenceAdapter: Bool
    public let boundContextParameterTypes: [SnapshotType]

    private enum CodingKeys: String, CodingKey {
        case chosenCallee
        case substitutedTypeArguments
        case parameterMapping
        case contextParameterArgumentMapping
        case defaultArgumentOwner
        case dispatchReceiverSymbol
        case isCallableReferenceAdapter
        case boundContextParameterTypes
    }

    public init(
        chosenCallee: SnapshotSymbol,
        substitutedTypeArguments: [SnapshotType],
        parameterMapping: [SnapshotIndexPair],
        contextParameterArgumentMapping: [SnapshotIndexPair] = [],
        defaultArgumentOwner: SnapshotSymbol?,
        dispatchReceiverSymbol: SnapshotSymbol?,
        isCallableReferenceAdapter: Bool,
        boundContextParameterTypes: [SnapshotType]
    ) {
        self.chosenCallee = chosenCallee
        self.substitutedTypeArguments = substitutedTypeArguments
        self.parameterMapping = parameterMapping
        self.contextParameterArgumentMapping = contextParameterArgumentMapping
        self.defaultArgumentOwner = defaultArgumentOwner
        self.dispatchReceiverSymbol = dispatchReceiverSymbol
        self.isCallableReferenceAdapter = isCallableReferenceAdapter
        self.boundContextParameterTypes = boundContextParameterTypes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        chosenCallee = try container.decode(SnapshotSymbol.self, forKey: .chosenCallee)
        substitutedTypeArguments = try container.decode([SnapshotType].self, forKey: .substitutedTypeArguments)
        parameterMapping = try container.decode([SnapshotIndexPair].self, forKey: .parameterMapping)
        contextParameterArgumentMapping = try container.decodeIfPresent(
            [SnapshotIndexPair].self,
            forKey: .contextParameterArgumentMapping
        ) ?? []
        defaultArgumentOwner = try container.decodeIfPresent(SnapshotSymbol.self, forKey: .defaultArgumentOwner)
        dispatchReceiverSymbol = try container.decodeIfPresent(SnapshotSymbol.self, forKey: .dispatchReceiverSymbol)
        isCallableReferenceAdapter = try container.decode(Bool.self, forKey: .isCallableReferenceAdapter)
        boundContextParameterTypes = try container.decode([SnapshotType].self, forKey: .boundContextParameterTypes)
    }
}

/// Translates between live IDs and ID-independent references for one
/// compilation. `encode` returns nil for anything it cannot represent
/// faithfully; callers must then treat the declaration as uncacheable rather
/// than store a lossy snapshot.
/// How a codec maps expressions of the snapshotted declaration to body-relative
/// positions and back; supplied by `FunctionBodySemaScope`.
struct SnapshotExprMapping {
    var relativeIndex: (ExprID) -> Int?
    var expr: (Int) -> ExprID?
    var isLambda: (ExprID) -> Bool

    static var none: SnapshotExprMapping {
        SnapshotExprMapping(relativeIndex: { _ in nil }, expr: { _ in nil }, isLambda: { _ in false })
    }
}

final class SemaSnapshotCodec {
    /// First ID of the synthetic lambda-parameter family (see `SnapshotSymbol.lambdaParameter`).
    private static let lambdaParameterBase: Int64 = -1_000_000
    private static let lambdaSlotStride: Int64 = 256

    private let exprMapping: SnapshotExprMapping
    private let interner: StringInterner
    private let symbols: SymbolTable
    private let types: TypeSystem
    private let canonicalizer: KIRCanonicalizer
    private let localOrdinals: [SymbolID: Int]
    private let localsByOrdinal: [Int: SymbolID]
    private var typeRefCache: [TypeID: SnapshotType?] = [:]

    /// - Parameter localSymbols: symbols declared inside the snapshotted
    ///   declaration, in a deterministic (definition) order.
    init(
        interner: StringInterner, symbols: SymbolTable, types: TypeSystem, localSymbols: [SymbolID],
        exprMapping: SnapshotExprMapping = .none
    ) {
        self.exprMapping = exprMapping
        self.interner = interner
        self.symbols = symbols
        self.types = types
        canonicalizer = KIRCanonicalizer(arena: KIRArena(), interner: interner, symbols: symbols, types: types)
        var ordinals: [SymbolID: Int] = [:]
        var byOrdinal: [Int: SymbolID] = [:]
        for (ordinal, symbol) in localSymbols.enumerated() {
            ordinals[symbol] = ordinal
            byOrdinal[ordinal] = symbol
        }
        localOrdinals = ordinals
        localsByOrdinal = byOrdinal
    }

    // MARK: - Symbols

    func encode(symbol id: SymbolID) -> SnapshotSymbol? {
        if let ordinal = localOrdinals[id] { return .local(ordinal) }
        guard let symbol = symbols.symbol(id) else { return encodeLambdaParameter(id) }
        let ref = SnapshotSymbol.global(
            key: canonicalizer.symbolKey(id),
            fqName: canonicalizer.normalizedFQName(of: symbol)
        )
        // A global reference is only usable if it resolves back to the same
        // symbol; synthetic symbols that share a key with another fail here.
        guard decode(symbol: ref) == id else { return nil }
        return ref
    }

    /// Recognizes a synthetic lambda parameter. Anything else outside the
    /// symbol table stays unrepresentable, so an unknown synthetic family makes
    /// the declaration uncacheable instead of being guessed at.
    private func encodeLambdaParameter(_ id: SymbolID) -> SnapshotSymbol? {
        let distance = Self.lambdaParameterBase - Int64(id.rawValue)
        guard distance >= 0 else { return nil }
        let lambda = ExprID(rawValue: Int32(clamping: distance / Self.lambdaSlotStride))
        let slot = Int(distance % Self.lambdaSlotStride)
        guard exprMapping.isLambda(lambda), let index = exprMapping.relativeIndex(lambda) else { return nil }
        return .lambdaParameter(lambdaIndex: index, slot: slot)
    }

    func decode(symbol ref: SnapshotSymbol) -> SymbolID? {
        switch ref {
        case let .lambdaParameter(index, slot):
            guard let lambda = exprMapping.expr(index) else { return nil }
            return SymbolID(rawValue: Int32(clamping: Self.lambdaParameterBase
                - Int64(lambda.rawValue) * Self.lambdaSlotStride - Int64(slot)))
        case let .local(ordinal):
            return localsByOrdinal[ordinal]
        case let .global(key, fqName):
            // `fqName` is normalized (ID-derived parts dropped), so it cannot be
            // looked up directly; narrow by short name and compare keys.
            guard let shortName = fqName.last else { return nil }
            let name = interner.intern(shortName)
            return canonicalizer.candidates(fqName: fqName.map { interner.intern($0) }, shortName: name)
                .sorted { $0.rawValue < $1.rawValue }
                .first { canonicalizer.symbolKey($0) == key }
        }
    }

    // MARK: - Types

    func encode(type id: TypeID) -> SnapshotType? {
        if let cached = typeRefCache[id] { return cached }
        let ref = computeTypeRef(id)
        typeRefCache[id] = .some(ref)
        return ref
    }

    private func encodeAll(_ ids: [TypeID]) -> [SnapshotType]? {
        var result: [SnapshotType] = []
        for id in ids {
            guard let ref = encode(type: id) else { return nil }
            result.append(ref)
        }
        return result
    }

    private func encode(arg: TypeArg) -> SnapshotTypeArg? {
        switch arg {
        case let .invariant(type): encode(type: type).map(SnapshotTypeArg.invariant)
        case let .out(type): encode(type: type).map(SnapshotTypeArg.out)
        case let .in(type): encode(type: type).map(SnapshotTypeArg.in)
        case .star: SnapshotTypeArg.star
        }
    }

    private func encodeAll(_ args: [TypeArg]) -> [SnapshotTypeArg]? {
        var result: [SnapshotTypeArg] = []
        for arg in args {
            guard let ref = encode(arg: arg) else { return nil }
            result.append(ref)
        }
        return result
    }

    private func computeTypeRef(_ id: TypeID) -> SnapshotType? {
        switch types.kind(of: id) {
        case .error: return .error
        case .unit: return .unit
        case .nullableUnit: return .nullableUnit
        case .platformUnit: return .platformUnit
        case let .nothing(nullability): return .nothing(nullability)
        case let .any(nullability): return .any(nullability)
        case let .stringStruct(nullability): return .stringStruct(nullability)
        case let .primitive(primitive, nullability): return .primitive(primitive, nullability)
        case let .classType(classType):
            guard let symbol = encode(symbol: classType.classSymbol),
                  let args = encodeAll(classType.args),
                  let enclosing = encodeAll(classType.enclosingTypeArgs)
            else { return nil }
            return .classType(symbol, args: args, enclosingArgs: enclosing, classType.nullability)
        case let .typeParam(typeParam):
            // Captured projections carry per-inference identity; not restorable.
            guard typeParam.capture == nil, let symbol = encode(symbol: typeParam.symbol) else { return nil }
            return .typeParam(symbol, typeParam.nullability)
        case let .functionType(functionType):
            guard let context = encodeAll(functionType.contextReceivers),
                  let params = encodeAll(functionType.params),
                  let returnType = encode(type: functionType.returnType),
                  let thrown = encodeAll(functionType.throws)
            else { return nil }
            var receiver: SnapshotType?
            if let receiverType = functionType.receiver {
                guard let encoded = encode(type: receiverType) else { return nil }
                receiver = encoded
            }
            return .function(
                contextReceivers: context, receiver: receiver, params: params, returnType: returnType,
                isSuspend: functionType.isSuspend, isCallableReference: functionType.isCallableReference,
                nullability: functionType.nullability, throwsTypes: thrown
            )
        case let .intersection(parts):
            return encodeAll(parts).map(SnapshotType.intersection)
        case let .kClassType(kClassType):
            return encode(type: kClassType.argument).map { .kClass($0, kClassType.nullability) }
        }
    }

    func decode(type ref: SnapshotType) -> TypeID? {
        guard let kind = decodeKind(ref) else { return nil }
        return types.make(kind)
    }

    private func decodeAll(_ refs: [SnapshotType]) -> [TypeID]? {
        var result: [TypeID] = []
        for ref in refs {
            guard let id = decode(type: ref) else { return nil }
            result.append(id)
        }
        return result
    }

    private func decode(arg ref: SnapshotTypeArg) -> TypeArg? {
        switch ref {
        case let .invariant(type): decode(type: type).map(TypeArg.invariant)
        case let .out(type): decode(type: type).map(TypeArg.out)
        case let .in(type): decode(type: type).map(TypeArg.in)
        case .star: TypeArg.star
        }
    }

    private func decodeAll(_ refs: [SnapshotTypeArg]) -> [TypeArg]? {
        var result: [TypeArg] = []
        for ref in refs {
            guard let arg = decode(arg: ref) else { return nil }
            result.append(arg)
        }
        return result
    }

    private func decodeKind(_ ref: SnapshotType) -> TypeKind? {
        switch ref {
        case .error: return .error
        case .unit: return .unit
        case .nullableUnit: return .nullableUnit
        case .platformUnit: return .platformUnit
        case let .nothing(nullability): return .nothing(nullability)
        case let .any(nullability): return .any(nullability)
        case let .stringStruct(nullability): return .stringStruct(nullability)
        case let .primitive(primitive, nullability): return .primitive(primitive, nullability)
        case let .classType(symbolRef, args, enclosing, nullability):
            guard let symbol = decode(symbol: symbolRef),
                  let decodedArgs = decodeAll(args),
                  let decodedEnclosing = decodeAll(enclosing)
            else { return nil }
            return .classType(ClassType(
                classSymbol: symbol, args: decodedArgs, enclosingTypeArgs: decodedEnclosing, nullability: nullability
            ))
        case let .typeParam(symbolRef, nullability):
            guard let symbol = decode(symbol: symbolRef) else { return nil }
            return .typeParam(TypeParamType(symbol: symbol, nullability: nullability))
        case let .function(context, receiver, params, returnType, isSuspend, isCallableReference, nullability, thrown):
            guard let decodedContext = decodeAll(context),
                  let decodedParams = decodeAll(params),
                  let decodedReturn = decode(type: returnType),
                  let decodedThrown = decodeAll(thrown)
            else { return nil }
            var decodedReceiver: TypeID?
            if let receiver {
                guard let id = decode(type: receiver) else { return nil }
                decodedReceiver = id
            }
            return .functionType(FunctionType(
                contextReceivers: decodedContext, receiver: decodedReceiver, params: decodedParams,
                returnType: decodedReturn, isSuspend: isSuspend, isCallableReference: isCallableReference,
                nullability: nullability, throws: decodedThrown
            ))
        case let .intersection(parts):
            return decodeAll(parts).map(TypeKind.intersection)
        case let .kClass(argument, nullability):
            return decode(type: argument).map { .kClassType(KClassType(argument: $0, nullability: nullability)) }
        }
    }

    // MARK: - Call bindings

    func encode(callBinding binding: CallBinding) -> SnapshotCallBinding? {
        guard let callee = encode(symbol: binding.chosenCallee),
              let typeArguments = encodeAll(binding.substitutedTypeArguments),
              let contextTypes = encodeAll(binding.boundContextParameterTypes)
        else { return nil }
        var owner: SnapshotSymbol?
        if let id = binding.defaultArgumentOwner {
            guard let ref = encode(symbol: id) else { return nil }
            owner = ref
        }
        var dispatch: SnapshotSymbol?
        if let id = binding.dispatchReceiverSymbol {
            guard let ref = encode(symbol: id) else { return nil }
            dispatch = ref
        }
        let mapping = binding.parameterMapping
            .sorted { $0.key < $1.key }
            .map { SnapshotIndexPair(from: $0.key, to: $0.value) }
        let contextMapping = binding.contextParameterArgumentMapping
            .sorted { $0.key < $1.key }
            .map { SnapshotIndexPair(from: $0.key, to: $0.value) }
        return SnapshotCallBinding(
            chosenCallee: callee, substitutedTypeArguments: typeArguments, parameterMapping: mapping,
            contextParameterArgumentMapping: contextMapping,
            defaultArgumentOwner: owner, dispatchReceiverSymbol: dispatch,
            isCallableReferenceAdapter: binding.isCallableReferenceAdapter,
            boundContextParameterTypes: contextTypes
        )
    }

    func decode(callBinding ref: SnapshotCallBinding) -> CallBinding? {
        guard let callee = decode(symbol: ref.chosenCallee),
              let typeArguments = decodeAll(ref.substitutedTypeArguments),
              let contextTypes = decodeAll(ref.boundContextParameterTypes)
        else { return nil }
        var owner: SymbolID?
        if let ownerRef = ref.defaultArgumentOwner {
            guard let id = decode(symbol: ownerRef) else { return nil }
            owner = id
        }
        var dispatch: SymbolID?
        if let dispatchRef = ref.dispatchReceiverSymbol {
            guard let id = decode(symbol: dispatchRef) else { return nil }
            dispatch = id
        }
        var mapping: [Int: Int] = [:]
        for pair in ref.parameterMapping { mapping[pair.from] = pair.to }
        var contextMapping: [Int: Int] = [:]
        for pair in ref.contextParameterArgumentMapping { contextMapping[pair.from] = pair.to }
        return CallBinding(
            chosenCallee: callee, substitutedTypeArguments: typeArguments, parameterMapping: mapping,
            contextParameterArgumentMapping: contextMapping,
            defaultArgumentOwner: owner, dispatchReceiverSymbol: dispatch,
            isCallableReferenceAdapter: ref.isCallableReferenceAdapter, boundContextParameterTypes: contextTypes
        )
    }
}
