import Foundation

let runtimeStringNominalTypeID: Int64 = {
    let stringTypeID = runtimeStableNominalTypeID(fqName: "kotlin.String")
    runtimeRegisterTypeEdge(
        childTypeID: stringTypeID,
        parentTypeID: runtimeStableNominalTypeID(fqName: "kotlin.CharSequence")
    )
    runtimeRegisterTypeEdge(
        childTypeID: stringTypeID,
        parentTypeID: runtimeStableNominalTypeID(fqName: "kotlin.Comparable")
    )
    return stringTypeID
}()

private struct RuntimePrimitiveNominalTypeIDs {
    let byte, short, int, long, float, double: Int64
    let uint, ulong, ubyte, ushort, char, boolean: Int64

    static let shared = RuntimePrimitiveNominalTypeIDs(
        byte: runtimeStableNominalTypeID(fqName: "kotlin.Byte"),
        short: runtimeStableNominalTypeID(fqName: "kotlin.Short"),
        int: runtimeStableNominalTypeID(fqName: "kotlin.Int"),
        long: runtimeStableNominalTypeID(fqName: "kotlin.Long"),
        float: runtimeStableNominalTypeID(fqName: "kotlin.Float"),
        double: runtimeStableNominalTypeID(fqName: "kotlin.Double"),
        uint: runtimeStableNominalTypeID(fqName: "kotlin.UInt"),
        ulong: runtimeStableNominalTypeID(fqName: "kotlin.ULong"),
        ubyte: runtimeStableNominalTypeID(fqName: "kotlin.UByte"),
        ushort: runtimeStableNominalTypeID(fqName: "kotlin.UShort"),
        char: runtimeStableNominalTypeID(fqName: "kotlin.Char"),
        boolean: runtimeStableNominalTypeID(fqName: "kotlin.Boolean")
    )

    func registerEdgesOnce() {
        runtimeStorage.withMetadataLock { state in
            if state.primitiveTypeEdgesRegistered {
                return
            }
            let comparable = runtimeStableNominalTypeID(fqName: "kotlin.Comparable")
            let number = runtimeStableNominalTypeID(fqName: "kotlin.Number")
            state.typeParents[number, default: []].insert(
                runtimeStableNominalTypeID(fqName: "java.io.Serializable")
            )
            for id in [byte, short, int, long, float, double] {
                state.typeParents[id, default: []].insert(number)
                state.typeParents[id, default: []].insert(comparable)
            }
            for id in [uint, ulong, ubyte, ushort, char, boolean] {
                state.typeParents[id, default: []].insert(comparable)
            }
            state.primitiveTypeEdgesRegistered = true
        }
    }
}

func runtimePrimitiveNominalTypeID(forTypeTokenBase base: Int64) -> Int64? {
    let ids = RuntimePrimitiveNominalTypeIDs.shared
    let typeID: Int64? = switch base {
    case RuntimeTypeTokenEncoding.byteBase: ids.byte
    case RuntimeTypeTokenEncoding.shortBase: ids.short
    case RuntimeTypeTokenEncoding.intBase: ids.int
    case RuntimeTypeTokenEncoding.longBase: ids.long
    case RuntimeTypeTokenEncoding.floatBase: ids.float
    case RuntimeTypeTokenEncoding.doubleBase: ids.double
    case RuntimeTypeTokenEncoding.uintBase: ids.uint
    case RuntimeTypeTokenEncoding.ulongBase: ids.ulong
    case RuntimeTypeTokenEncoding.ubyteBase: ids.ubyte
    case RuntimeTypeTokenEncoding.ushortBase: ids.ushort
    case RuntimeTypeTokenEncoding.charBase: ids.char
    case RuntimeTypeTokenEncoding.booleanBase: ids.boolean
    default: nil
    }
    guard let typeID else { return nil }
    ids.registerEdgesOnce()
    return typeID
}

/// Precondition (enforced by `kk_op_is`, this function's only caller): `ptr`
/// must not already be a tagged value-class box (`runtimeObjectTypeID(rawValue:)
/// != nil`). This function does not re-check that itself, so a value class
/// boxed through the same primitive box types would otherwise be misreported
/// as its underlying primitive's Number/Comparable identity instead of its
/// own nominal one. Kept `private` so that precondition can't be violated
/// from another call site.
private func runtimePrimitiveBoxNominalTypeID(_ ptr: UnsafeMutableRawPointer) -> Int64? {
    // `tryCast` force-unwraps `ptr` as a live Swift object via
    // `Unmanaged.fromOpaque`; only call it once the GC registry confirms
    // this is actually a tracked allocation, matching every other cast site
    // in this function's callers (e.g. the throwable check below).
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    let ids = RuntimePrimitiveNominalTypeIDs.shared
    if let intBox = tryCast(ptr, to: RuntimeIntBox.self), intBox.enumClassID == nil {
        ids.registerEdgesOnce()
        switch intBox.primitiveTypeBase {
        case RuntimeTypeTokenEncoding.byteBase: return ids.byte
        case RuntimeTypeTokenEncoding.shortBase: return ids.short
        case RuntimeTypeTokenEncoding.uintBase: return ids.uint
        case RuntimeTypeTokenEncoding.ubyteBase: return ids.ubyte
        case RuntimeTypeTokenEncoding.ushortBase: return ids.ushort
        default: return ids.int
        }
    }
    if tryCast(ptr, to: RuntimeLongBox.self) != nil {
        ids.registerEdgesOnce()
        return ids.long
    }
    if tryCast(ptr, to: RuntimeULongBox.self) != nil {
        ids.registerEdgesOnce()
        return ids.ulong
    }
    if tryCast(ptr, to: RuntimeFloatBox.self) != nil {
        ids.registerEdgesOnce()
        return ids.float
    }
    if tryCast(ptr, to: RuntimeDoubleBox.self) != nil {
        ids.registerEdgesOnce()
        return ids.double
    }
    if tryCast(ptr, to: RuntimeCharBox.self) != nil {
        ids.registerEdgesOnce()
        return ids.char
    }
    if tryCast(ptr, to: RuntimeBoolBox.self) != nil {
        ids.registerEdgesOnce()
        return ids.boolean
    }
    return nil
}

private let runtimeBigDecimalNominalTypeID = runtimeStableNominalTypeID(fqName: "java.math.BigDecimal")

func registerBigDecimalTypeEdgesOnce() {
    runtimeStorage.withMetadataLock { state in
        if state.bigDecimalTypeEdgesRegistered {
            return
        }
        let number = runtimeStableNominalTypeID(fqName: "kotlin.Number")
        let comparable = runtimeStableNominalTypeID(fqName: "kotlin.Comparable")
        let serializable = runtimeStableNominalTypeID(fqName: "java.io.Serializable")
        state.typeParents[runtimeBigDecimalNominalTypeID, default: []].insert(number)
        state.typeParents[runtimeBigDecimalNominalTypeID, default: []].insert(comparable)
        state.typeParents[number, default: []].insert(serializable)
        state.bigDecimalTypeEdgesRegistered = true
    }
}

func runtimeIsStringBoxPointer(_ ptr: UnsafeMutableRawPointer) -> Bool {
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return false
    }
    return tryCast(ptr, to: RuntimeStringBox.self) != nil
}

private func runtimeFunctionTypeMatches(
    targetArity: Int,
    targetIsSuspend: Bool,
    actualArity: Int,
    actualIsSuspend: Bool
) -> Bool {
    if targetIsSuspend {
        return actualIsSuspend && targetArity == actualArity
    }
    let loweredFunctionArity = actualArity + (actualIsSuspend ? 1 : 0)
    return targetArity == loweredFunctionArity
}

private func runtimeNominalTypeImplementsFunction(
    _ sourceTypeID: Int64,
    arity: Int,
    isSuspend: Bool
) -> Bool {
    let targetFQName = isSuspend
        ? "kotlin.coroutines.SuspendFunction\(arity)"
        : "kotlin.Function.Function\(arity)"
    if runtimeIsAssignable(
        sourceTypeID: sourceTypeID,
        targetTypeID: runtimeStableNominalTypeID(fqName: targetFQName)
    ) {
        return true
    }
    guard !isSuspend, arity > 0 else { return false }
    return runtimeIsAssignable(
        sourceTypeID: sourceTypeID,
        targetTypeID: runtimeStableNominalTypeID(fqName: "kotlin.coroutines.SuspendFunction\(arity - 1)")
    )
}

@_cdecl("kk_op_is")
public func kk_op_is(_ value: Int, _ typeToken: Int) -> Int {
    let token = Int64(truncatingIfNeeded: typeToken)
    let base = token & RuntimeTypeTokenEncoding.baseMask
    let isNullableTarget = (token & RuntimeTypeTokenEncoding.nullableBit) != 0
    let payload = (token >> RuntimeTypeTokenEncoding.payloadShift) & RuntimeTypeTokenEncoding.payloadMask

    if value == runtimeNullSentinelInt {
        if isNullableTarget || base == RuntimeTypeTokenEncoding.nullBase {
            return 1
        }
        return 0
    }

    switch base {
    case RuntimeTypeTokenEncoding.anyBase:
        return 1

    case RuntimeTypeTokenEncoding.stringBase:
        guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
            return 0
        }
        return runtimeIsStringBoxPointer(ptr) ? 1 : 0

    case RuntimeTypeTokenEncoding.intBase,
         RuntimeTypeTokenEncoding.uintBase,
         RuntimeTypeTokenEncoding.ubyteBase,
         RuntimeTypeTokenEncoding.ushortBase,
         RuntimeTypeTokenEncoding.byteBase,
         RuntimeTypeTokenEncoding.shortBase:
        // NOTE: an unboxed (non-object-pointer) value here is treated as a
        // match. That's unsound in general — Int/UInt/UByte/UShort share no
        // value-range heuristic that distinguishes them from Long/Double/
        // Float/Char once unboxed (all reinterpret the same 64-bit word) — but
        // some existing callers (e.g. Sequence element storage) still hand
        // kk_op_is genuinely unboxed primitives, so tightening this to a
        // mismatch regresses them. The `is`/`as`/`as?` call sites themselves
        // are fixed to always box their operand before reaching here (see
        // ABILoweringPass's typeCheckValueCallees); see also the follow-up
        // tracking sequenceOf's missing element boxing.
        guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
            return 1
        }
        let isObjectPointer = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if !isObjectPointer {
            return 1
        }
        if runtimeObjectTypeID(rawValue: value) != nil {
            return 0
        }
        guard let box = tryCast(ptr, to: RuntimeIntBox.self), box.enumClassID == nil else {
            return 0
        }
        return box.primitiveTypeBase == base ? 1 : 0

    case RuntimeTypeTokenEncoding.functionBase:
        let (arity, isSuspend) = RuntimeTypeTokenEncoding.functionPayloadParts(payload)
        let (samInterfaceTypeID, taggedFunctionType) = runtimeStorage.withDelegateLock { state -> (Int64?, (Int, Bool)?) in
            if let adapter = state.callableAdapterIdentityByValue[value],
               adapter.samInterfaceTypeID != 0
            {
                return (adapter.samInterfaceTypeID, nil)
            }
            if let payload = state.functionTypePayloadByValue[value] {
                let (arity, isSuspend) = RuntimeTypeTokenEncoding.functionPayloadParts(Int64(payload))
                return (nil, (arity, isSuspend))
            }
            if let metadata = state.callableRefMetadataByValue[value], metadata.kind == .function {
                return (nil, (metadata.arity, metadata.isSuspend))
            }
            if let adapter = state.callableAdapterIdentityByValue[value] {
                return (nil, (adapter.arity, adapter.isSuspend))
            }
            return (nil, nil)
        }
        if let samInterfaceTypeID {
            return runtimeNominalTypeImplementsFunction(
                samInterfaceTypeID, arity: arity, isSuspend: isSuspend
            ) ? 1 : 0
        }
        if let (actualArity, actualIsSuspend) = taggedFunctionType {
            return runtimeFunctionTypeMatches(
                targetArity: arity,
                targetIsSuspend: isSuspend,
                actualArity: actualArity,
                actualIsSuspend: actualIsSuspend
            ) ? 1 : 0
        }
        guard let ptr = UnsafeMutableRawPointer(bitPattern: value),
              runtimeStorage.withGCLock({ state in
                  state.objectPointers.contains(UInt(bitPattern: ptr))
              })
        else {
            return 0
        }
        if let fnBox = tryCast(ptr, to: RuntimeFunctionValueBox.self) {
            return runtimeFunctionTypeMatches(
                targetArity: arity,
                targetIsSuspend: isSuspend,
                actualArity: fnBox.arity,
                actualIsSuspend: fnBox.suspendEntryPoint != 0
            ) ? 1 : 0
        }
        if let kfnBox = tryCast(ptr, to: RuntimeKFunctionBox.self) {
            return runtimeFunctionTypeMatches(
                targetArity: arity,
                targetIsSuspend: isSuspend,
                actualArity: kfnBox.arity,
                actualIsSuspend: false
            ) ? 1 : 0
        }
        if let sourceTypeID = runtimeObjectTypeID(rawValue: value) {
            return runtimeNominalTypeImplementsFunction(
                sourceTypeID, arity: arity, isSuspend: isSuspend
            ) ? 1 : 0
        }
        return 0

    case RuntimeTypeTokenEncoding.longBase:
        guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
            return 1
        }
        let isObjPtr = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if !isObjPtr { return 1 }
        if runtimeObjectTypeID(rawValue: value) != nil {
            return 0
        }
        return tryCast(ptr, to: RuntimeLongBox.self) == nil ? 0 : 1

    case RuntimeTypeTokenEncoding.ulongBase:
        guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
            return 1
        }
        let isObjPtr = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if !isObjPtr { return 1 }
        return tryCast(ptr, to: RuntimeULongBox.self) == nil ? 0 : 1

    case RuntimeTypeTokenEncoding.doubleBase:
        guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
            return 1
        }
        let isObjPtr = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if !isObjPtr { return 1 }
        if runtimeObjectTypeID(rawValue: value) != nil {
            return 0
        }
        return tryCast(ptr, to: RuntimeDoubleBox.self) == nil ? 0 : 1

    case RuntimeTypeTokenEncoding.floatBase:
        guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
            return 1
        }
        let isObjPtr = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if !isObjPtr { return 1 }
        if runtimeObjectTypeID(rawValue: value) != nil {
            return 0
        }
        return tryCast(ptr, to: RuntimeFloatBox.self) == nil ? 0 : 1

    case RuntimeTypeTokenEncoding.charBase:
        guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
            return 1
        }
        let isObjPtr = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if !isObjPtr { return 1 }
        if runtimeObjectTypeID(rawValue: value) != nil {
            return 0
        }
        return tryCast(ptr, to: RuntimeCharBox.self) == nil ? 0 : 1

    case RuntimeTypeTokenEncoding.booleanBase:
        guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
            return (value == 0 || value == 1) ? 1 : 0
        }
        let isObjectPointer = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if !isObjectPointer {
            return (value == 0 || value == 1) ? 1 : 0
        }
        if runtimeObjectTypeID(rawValue: value) != nil {
            return 0
        }
        return tryCast(ptr, to: RuntimeBoolBox.self) == nil ? 0 : 1

    case RuntimeTypeTokenEncoding.nullBase:
        return 0

    case RuntimeTypeTokenEncoding.unitBase:
        return runtimeIsUnitValue(value) ? 1 : 0

    case RuntimeTypeTokenEncoding.nominalBase:
        if payload == runtimeStableNominalTypeID(fqName: "kotlin.coroutines.Continuation"),
           runtimeContinuationState(from: value) != nil
        {
            return 1
        }
        let isFunctionReference = runtimeStorage.withDelegateLock { state in
            state.callableRefMetadataByValue[value]?.kind == .function
        }
        if isFunctionReference {
            registerReflectionRuntimeTypeMetadata()
            if runtimeIsAssignable(sourceTypeID: kFunctionRuntimeTypeID, targetTypeID: payload)
                || runtimeIsKFunctionArityTypeID(payload)
            {
                return 1
            }
        }
        if runtimeArrayHasType(rawValue: value, typeID: payload) {
            return 1
        }
        if let sourceTypeID = runtimeObjectTypeID(rawValue: value) {
            registerSortedCollectionTypeEdgesOnce()
            if runtimeIsAssignable(sourceTypeID: sourceTypeID, targetTypeID: payload)
                || runtimeIsJvmErasedListAssignable(
                    rawValue: value,
                    sourceTypeID: sourceTypeID,
                    targetTypeID: payload
                )
                || runtimeIsJvmErasedSetAssignable(
                    rawValue: value,
                    sourceTypeID: sourceTypeID,
                    targetTypeID: payload
                )
                || runtimeIsJvmErasedMapAssignable(
                    rawValue: value,
                    sourceTypeID: sourceTypeID,
                    targetTypeID: payload
                )
            {
                return 1
            }
            if runtimeIsKFunctionArityTypeID(payload) {
                registerReflectionRuntimeTypeMetadata()
                return runtimeIsAssignable(
                    sourceTypeID: sourceTypeID,
                    targetTypeID: kFunctionRuntimeTypeID
                ) ? 1 : 0
            }
            return 0
        }
        guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
            return 0
        }
        if runtimeIsStringBoxPointer(ptr) {
            return runtimeIsAssignable(
                sourceTypeID: runtimeStringNominalTypeID,
                targetTypeID: payload
            ) ? 1 : 0
        }
        if let primitiveTypeID = runtimePrimitiveBoxNominalTypeID(ptr) {
            return runtimeIsAssignable(
                sourceTypeID: primitiveTypeID,
                targetTypeID: payload
            ) ? 1 : 0
        }
        if let rangeBox = runtimeRangeBox(from: value) {
            registerRangeTypeEdgesOnce()
            return runtimeIsAssignable(
                sourceTypeID: runtimeRangeBoxNominalTypeID(rangeBox.kind),
                targetTypeID: payload
            ) ? 1 : 0
        }
        let isFloatingRangeBox = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
                ? tryCast(ptr, to: RuntimeDoubleRangeBox.self) != nil
                    || tryCast(ptr, to: RuntimeFloatRangeBox.self) != nil
                : false
        }
        if isFloatingRangeBox {
            registerRangeTypeEdgesOnce()
            return runtimeIsAssignable(
                sourceTypeID: runtimeStableNominalTypeID(
                    fqName: "kotlin.ranges.ClosedFloatingPointRange"
                ),
                targetTypeID: payload
            ) ? 1 : 0
        }
        // Range iterator handles (`(1..5).iterator()`) are likewise registered
        // without object type metadata. They are typed `kotlin.collections.Iterator`
        // only: the element-specialized XIterator classes can't be honored
        // because `nextInt()`/`nextChar()` member calls on an XIterator receiver
        // lower to vtable/itable dispatch that an unregistered box cannot
        // answer, so claiming them here would turn `is IntIterator` into a
        // reachable dispatch trap. `kotlin.collections.Iterator` answers the
        // interface checks (`is Iterator`, `as Iterator`) like kotlinc while
        // `is IntIterator`/`is MutableIterator` stay false.
        if runtimeRangeIteratorBox(from: value) != nil {
            return runtimeIsAssignable(
                sourceTypeID: runtimeStableNominalTypeID(
                    fqName: "kotlin.collections.Iterator"
                ),
                targetTypeID: payload
            ) ? 1 : 0
        }
        if isDispatcherTag(value) {
            registerCoroutineDispatcherTypeEdgesOnce()
            let tagSourceTypeID = runtimeStableNominalTypeID(
                fqName: (value == RuntimeDispatcherTag.mainDispatcher
                         || value == RuntimeDispatcherTag.mainImmediateDispatcher)
                    ? "kotlinx.coroutines.MainCoroutineDispatcher"
                    : "kotlinx.coroutines.CoroutineDispatcher"
            )
            return runtimeIsAssignable(
                sourceTypeID: tagSourceTypeID,
                targetTypeID: payload
            ) ? 1 : 0
        }
        if let jobFamilyTypeID = runtimeJobFamilyNominalTypeID(rawValue: value) {
            registerJobFamilyTypeEdgesOnce()
            return runtimeIsAssignable(
                sourceTypeID: jobFamilyTypeID,
                targetTypeID: payload
            ) ? 1 : 0
        }
        if let deepRecursiveTypeID = runtimeDeepRecursiveNominalTypeID(rawValue: value) {
            return runtimeIsAssignable(
                sourceTypeID: deepRecursiveTypeID,
                targetTypeID: payload
            ) ? 1 : 0
        }
        if let channelFamilyTypeID = runtimeChannelFamilyNominalTypeID(rawValue: value) {
            registerChannelFamilyTypeEdgesOnce()
            return runtimeIsAssignable(
                sourceTypeID: channelFamilyTypeID,
                targetTypeID: payload
            ) ? 1 : 0
        }
        if let bigNumberBox = runtimeStorage.withGCLock({ state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
                ? tryCast(ptr, to: RuntimeBigNumberBox.self)
                : nil
        }), bigNumberBox.kind == .decimal {
            registerBigDecimalTypeEdgesOnce()
            return runtimeIsAssignable(
                sourceTypeID: runtimeBigDecimalNominalTypeID,
                targetTypeID: payload
            ) ? 1 : 0
        }
        let throwable = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
                ? tryCast(ptr, to: RuntimeThrowableBox.self)
                : nil
        }
        guard let throwable else {
            return 0
        }
        // Every built-in exception class now allocates a RuntimeThrowableBox
        // subclass with a correctly populated exceptionHierarchyFQNames (see
        // RuntimeAssertions.swift), so this hierarchy check
        // is authoritative: a real mismatch must not be treated as a match, or
        // `catch (e: T)` would incorrectly catch any unrelated sibling exception.
        if runtimeThrowableMatchesNominalTypeID(throwable, targetTypeID: payload) {
            return 1
        }
        return throwable.exceptionHierarchyIsBaseThrowable ? 1 : 0

    default:
        return 0
    }
}

private func runtimeSuspendCastAcceptsLoweredShape(value: Int, typeToken: Int) -> Bool {
    let token = Int64(truncatingIfNeeded: typeToken)
    guard token & RuntimeTypeTokenEncoding.baseMask == RuntimeTypeTokenEncoding.functionBase else {
        return false
    }
    let payload = (token >> RuntimeTypeTokenEncoding.payloadShift) & RuntimeTypeTokenEncoding.payloadMask
    let (arity, isSuspend) = RuntimeTypeTokenEncoding.functionPayloadParts(payload)
    guard isSuspend, arity < 0xFF else {
        return false
    }
    let loweredToken = (token & ~(RuntimeTypeTokenEncoding.payloadMask << RuntimeTypeTokenEncoding.payloadShift))
        | (Int64(arity + 1) << RuntimeTypeTokenEncoding.payloadShift)
    return kk_op_is(value, Int(truncatingIfNeeded: loweredToken)) != 0
}

@_cdecl("kk_op_cast")
public func kk_op_cast(_ value: Int, _ typeToken: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    return runtimeThrowingBridge(outThrown) {
        if kk_op_is(value, typeToken) != 0 {
            return value
        }
        if runtimeSuspendCastAcceptsLoweredShape(value: value, typeToken: typeToken) {
            return value
        }
        if value == runtimeNullSentinelInt {
            let token = Int64(truncatingIfNeeded: typeToken)
            let base = token & RuntimeTypeTokenEncoding.baseMask
            let isNullableTarget = (token & RuntimeTypeTokenEncoding.nullableBit) != 0
            if !isNullableTarget, base != RuntimeTypeTokenEncoding.nullBase {
                let targetName: String = {
                    if base == RuntimeTypeTokenEncoding.nominalBase,
                       let metadata = runtimeKClassMetadataRegistry.lookup(typeToken: typeToken)
                    {
                        return metadata.qualifiedName
                    }
                    let targetNameRaw = __kk_type_token_qualified_name(typeToken, 0)
                    return runtimeStringFromRaw(targetNameRaw) ?? "Unknown"
                }()
                outThrown?.pointee = runtimeAllocateNullPointerException(
                    message: "null cannot be cast to non-null type \(targetName)"
                )
                return 0
            }
        }
        outThrown?.pointee = runtimeAllocateClassCastException(
            message: runtimeClassCastExceptionMessage(value: value, targetTypeToken: typeToken)
        )
        return 0
    }
}

private func runtimeClassCastExceptionMessage(value: Int, targetTypeToken: Int) -> String {
    let sourceKClassRaw = __kk_kclass_of(value, Int(RuntimeTypeTokenEncoding.anyBase), 0)
    let sourceName = runtimeKClassBox(from: sourceKClassRaw).map {
        runtimeClassCastTypeName(typeToken: $0.typeToken, nameHint: $0.nameHint)
    } ?? "kotlin.Any"
    let targetName = runtimeClassCastTypeName(typeToken: targetTypeToken)
    return "class \(sourceName) cannot be cast to class \(targetName)"
}

private func runtimeClassCastTypeName(typeToken: Int, nameHint: Int = 0) -> String {
    let normalizedToken = Int(
        truncatingIfNeeded: Int64(truncatingIfNeeded: typeToken)
            & ~RuntimeTypeTokenEncoding.nullableBit
    )
    if let metadata = runtimeKClassMetadataRegistry.lookup(typeToken: normalizedToken),
       metadata.isLocal,
       let classCastName = runtimeKClassMetadataRegistry.classCastName(typeToken: normalizedToken),
       !classCastName.isEmpty {
        return classCastName
    }
    if let metadata = runtimeKClassMetadataRegistry.lookup(typeToken: normalizedToken),
       !metadata.qualifiedName.isEmpty {
        return metadata.qualifiedName
    }
    if let arrayName = runtimeArrayKClassQualifiedName(typeToken: normalizedToken) {
        return arrayName
    }
    if let rangeName = runtimeRangeClassQualifiedName(typeToken: normalizedToken) {
        return rangeName
    }
    let qualifiedNameRaw = __kk_type_token_qualified_name(normalizedToken, nameHint)
    if qualifiedNameRaw != 0,
       qualifiedNameRaw != runtimeNullSentinelInt,
       let qualifiedName = extractString(from: UnsafeMutableRawPointer(bitPattern: qualifiedNameRaw)),
       !qualifiedName.isEmpty
    {
        if qualifiedName == "Unknown"
            || qualifiedName.contains("__localdecl_")
            || qualifiedName.contains("__ObjectLiteral_"),
           let classCastName = runtimeKClassMetadataRegistry.classCastName(typeToken: normalizedToken),
           !classCastName.isEmpty {
            return classCastName
        }
        return qualifiedName
    }
    if nameHint != 0,
       nameHint != runtimeNullSentinelInt,
       let name = extractString(from: UnsafeMutableRawPointer(bitPattern: nameHint)),
       !name.isEmpty
    {
        return name
    }
    return "kotlin.Any"
}

@_cdecl("kk_op_cast_erased_return")
public func kk_op_cast_erased_return(
    _ value: Int,
    _ typeToken: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    return runtimeThrowingBridge(outThrown) {
        if kk_op_is(value, typeToken) != 0 {
            return value
        }
        if value == runtimeNullSentinelInt {
            outThrown?.pointee = runtimeAllocateClassCastException(message: "ClassCastException")
            return 0
        }
        return kk_op_cast(value, typeToken, outThrown)
    }
}

@_cdecl("kk_op_safe_cast")
public func kk_op_safe_cast(_ value: Int, _ typeToken: Int) -> Int {
    kk_op_is(value, typeToken) != 0 ? value : runtimeNullSentinelInt
}

@_cdecl("kk_array_op_cast")
public func kk_array_op_cast(
    _ value: Int,
    _ typeToken: Int,
    _ componentType: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    return runtimeThrowingBridge(outThrown) {
        guard kk_op_is(value, typeToken) != 0 else {
            return kk_op_cast(value, typeToken, outThrown)
        }
        guard value == runtimeNullSentinelInt
                || runtimeArrayHasAssignableComponent(rawValue: value, targetComponent: componentType)
        else {
            outThrown?.pointee = runtimeAllocateClassCastException(
                message: runtimeClassCastExceptionMessage(value: value, targetTypeToken: typeToken)
            )
            return 0
        }
        return value
    }
}

@_cdecl("kk_array_op_safe_cast")
public func kk_array_op_safe_cast(_ value: Int, _ typeToken: Int, _ componentType: Int) -> Int {
    guard kk_op_is(value, typeToken) != 0,
          value == runtimeNullSentinelInt
            || runtimeArrayHasAssignableComponent(rawValue: value, targetComponent: componentType)
    else {
        return runtimeNullSentinelInt
    }
    return value
}

@_cdecl("kk_op_contains")
public func kk_op_contains(_ container: Int, _ element: Int) -> Int {
    if let range = runtimeRangeBox(from: container) {
        return runtimeRangeContains(range, element)
    }
    if let list = runtimeListBox(from: container) {
        return list.values.contains(where: { list.elementsEqual($0.legacyRawValue, element) }) ? 1 : 0
    }
    if let set = runtimeSetBox(from: container) {
        return set.contains(rawValue: element) ? 1 : 0
    }
    // Array check — `RuntimeObjectBox` subclasses `RuntimeArrayBox`, so plain
    // `runtimeArrayBox` would also match class instances (whose storage holds
    // fields, not elements) and wrongly answer `false` for `x in obj`.
    if let array = runtimeArrayBoxExcludingObjects(from: container) {
        return array.values.contains(where: { runtimeLookupValuesEqual($0.legacyRawValue, element) }) ? 1 : 0
    }
    return runtimeSourceInterfaceCall1(
        container,
        element,
        interfaceTypeID: runtimeStableNominalTypeID(fqName: "kotlin.collections.Collection"),
        methodSlot: 1,
        context: "Collection.contains dispatch"
    ) ?? 0
}
