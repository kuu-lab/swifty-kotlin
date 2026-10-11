import Foundation
import RuntimeABI

/// Stable nominal type ID of `kotlin.String`, with String's interface
/// supertype edges registered on first use (BUG-153). Strings never reach
/// `kk_object_new`, so this is the only place those edges get installed.
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

/// Stable nominal type IDs for boxed primitive Kotlin types (pure hashes of
/// their fqNames, safe to cache once). Their `kotlin.Number`/
/// `kotlin.Comparable` supertype edges are registered separately by
/// `registerEdgesOnce()` below -- see that method's doc comment for why this
/// can't reuse `runtimeStringNominalTypeID`'s "register inside a `static
/// let` closure" pattern.
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

    /// Registers every ID above against `kotlin.Number`/`kotlin.Comparable`
    /// (Kotlin's unsigned types and Char/Boolean implement Comparable but
    /// are not Number subtypes), exactly once -- mirroring
    /// `registerReflectionRuntimeTypeMetadata`'s `reflectionTypeEdgesRegistered`
    /// flag (RuntimeReflectionTypeMetadata.swift), including its
    /// resettability: `kk_runtime_reset_metadata` clears
    /// `primitiveTypeEdgesRegistered` alongside `typeParents`, so a metadata
    /// reset (e.g. RuntimeTests' per-test isolation) re-registers on the next
    /// call instead of leaving these edges permanently missing after the
    /// one-time `static let` closure that installed them has already run.
    /// Cheap on the hot path: one lock acquisition and a flag read once the
    /// edges are installed (the caller's own `runtimeIsAssignable` takes a
    /// second, separate acquisition for its BFS).
    func registerEdgesOnce() {
        runtimeStorage.withMetadataLock { state in
            if state.primitiveTypeEdgesRegistered {
                return
            }
            let comparable = runtimeStableNominalTypeID(fqName: "kotlin.Comparable")
            let number = runtimeStableNominalTypeID(fqName: "kotlin.Number")
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

/// The nominal type ID of the boxed primitive `ptr` represents (Int, Double,
/// UInt, Char, ...), or `nil` when `ptr` is not a registered primitive box.
/// An enum-ordinal `RuntimeIntBox` (`enumClassID != nil`) is excluded: its
/// nominal identity is its enum class, not `kotlin.Int`.
///
/// `RuntimeIntBox` also backs Byte/Short and the small unsigned types;
/// `primitiveTypeBase` preserves their distinct Kotlin identities.
///
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
    // Registration only runs once a box actually matches below, so an `is`
    // check on an untagged non-primitive object (a throwable, list, map, ...)
    // never pays for it.
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

/// True when `ptr` is a live runtime object pointer holding a `RuntimeStringBox`.
func runtimeIsStringBoxPointer(_ ptr: UnsafeMutableRawPointer) -> Bool {
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return false
    }
    return tryCast(ptr, to: RuntimeStringBox.self) != nil
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
        //
        guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
            return 1
        }
        let isObjectPointer = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if !isObjectPointer {
            return 1
        }
        // A box tagged with a nominal type ID (kk_tag_value_class_box) represents
        // a boxed value class, which is a distinct type from its underlying
        // primitive even though it shares the same physical box.
        if runtimeObjectTypeID(rawValue: value) != nil {
            return 0
        }
        guard let box = tryCast(ptr, to: RuntimeIntBox.self), box.enumClassID == nil else {
            return 0
        }
        return box.primitiveTypeBase == base ? 1 : 0

    case RuntimeTypeTokenEncoding.functionBase:
        // KUU-1084: function-type tokens encode the FunctionN arity in the
        // low payload byte; a value matches when it is a function value of
        // the same arity (the suspend bit does not change `is` semantics).
        let (arity, _) = RuntimeTypeTokenEncoding.functionPayloadParts(payload)
        let rawArity = runtimeStorage.withDelegateLock { state -> Int? in
            if let registeredArity = state.functionArityByPointer[value] {
                return registeredArity
            }
            if let metadata = state.callableRefMetadataByValue[value], metadata.kind == .function {
                return metadata.arity
            }
            return nil
        }
        if let rawArity {
            return rawArity == arity ? 1 : 0
        }
        guard let ptr = UnsafeMutableRawPointer(bitPattern: value),
              runtimeStorage.withGCLock({ state in
                  state.objectPointers.contains(UInt(bitPattern: ptr))
              })
        else {
            return 0
        }
        if let fnBox = tryCast(ptr, to: RuntimeFunctionValueBox.self) {
            return fnBox.arity == arity ? 1 : 0
        }
        // Callable references (`::foo`) also satisfy function-type checks at
        // their declared arity.
        if let kfnBox = tryCast(ptr, to: RuntimeKFunctionBox.self) {
            return kfnBox.arity == arity ? 1 : 0
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
        // Direct Unit values remain integer 0; Any-erased Unit values use the
        // runtime box so they remain distinguishable from other raw values.
        return runtimeIsUnitValue(value) ? 1 : 0

    case RuntimeTypeTokenEncoding.nominalBase:
        // Raw callable references and adapted closure boxes retain reflection
        // identity in callable metadata rather than an object allocation tag.
        let isFunctionReference = runtimeStorage.withDelegateLock { state in
            state.callableRefMetadataByValue[value]?.kind == .function
        }
        if isFunctionReference {
            registerReflectionRuntimeTypeMetadata()
            if runtimeIsAssignable(sourceTypeID: kFunctionRuntimeTypeID, targetTypeID: payload) {
                return 1
            }
        }
        if runtimeArrayHasType(rawValue: value, typeID: payload) {
            return 1
        }
        if let sourceTypeID = runtimeObjectTypeID(rawValue: value) {
            registerSortedCollectionTypeEdgesOnce()
            return runtimeIsAssignable(sourceTypeID: sourceTypeID, targetTypeID: payload) ? 1 : 0
        }
        guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
            return 0
        }
        // BUG-153: String values are allocated through the flat-string fast
        // paths (kk_string_from_flat / kk_string_from_utf8 / concatenation /
        // toString()), never through kk_object_new, so they carry no object
        // type ID and can't answer an interface check (`is CharSequence`,
        // `is Comparable<*>`) via the registered supertype graph. Recover
        // String's identity from the box itself instead of tagging every
        // allocation site, then reuse the ordinary assignability walk over
        // kotlin.String's supertype edges.
        if runtimeIsStringBoxPointer(ptr) {
            return runtimeIsAssignable(
                sourceTypeID: runtimeStringNominalTypeID,
                targetTypeID: payload
            ) ? 1 : 0
        }
        // A Double/Float/Long/Int/... held in an Any slot boxes through the
        // same primitive box types as `is Int`/`is Double` above, but (like
        // String) carries no object type ID, so it needs the same recovery
        // to answer an interface check (`is Number`, `is Comparable<*>`).
        if let primitiveTypeID = runtimePrimitiveBoxNominalTypeID(ptr) {
            return runtimeIsAssignable(
                sourceTypeID: primitiveTypeID,
                targetTypeID: payload
            ) ? 1 : 0
        }
        // Range handles carry no object type ID either: they are allocated by
        // `__kk_*_rangeTo`/`downTo`/`until` factories, not kk_object_new.
        // Recover the nominal identity from the range kind, mirroring the
        // primitive-box recovery above.
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
        // KUU-1386: coroutine job-family handles (launch/async tasks, Job()/
        // SupervisorJob() handles, ChildHandle boxes) are raw runtime objects
        // with no object type ID — recover the kotlinx nominal they answer
        // `is`/`as`/`as?` as (AbstractCoroutine/DeferredCoroutine/JobImpl/...).
        if let jobFamilyTypeID = runtimeJobFamilyNominalTypeID(rawValue: value) {
            registerJobFamilyTypeEdgesOnce()
            return runtimeIsAssignable(
                sourceTypeID: jobFamilyTypeID,
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
        // RuntimeAssertions.swift / RuntimeTypes.swift), so this hierarchy check
        // is authoritative: a real mismatch must not be treated as a match, or
        // `catch (e: T)` would incorrectly catch any unrelated sibling exception.
        if runtimeThrowableMatchesNominalTypeID(throwable, targetTypeID: payload) {
            return 1
        }
        // A base RuntimeThrowableBox has no Kotlin-level type information. Keep
        // the historical broad catch fallback for those internal throwables,
        // while typed subclasses must obey their explicit hierarchy above.
        return throwable.exceptionHierarchyFQNames == ["kotlin.Throwable"] ? 1 : 0

    default:
        return 0
    }
}

@_cdecl("kk_op_cast")
public func kk_op_cast(_ value: Int, _ typeToken: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if kk_op_is(value, typeToken) != 0 {
        return value
    }
    // Kotlin/JVM reports a null-to-non-null cast as NullPointerException,
    // while a non-null value with the wrong runtime type is ClassCastException.
    // Keep the distinction before allocating the generic cast failure.
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
    outThrown?.pointee = runtimeAllocateClassCastException(message: "ClassCastException")
    return 0
}

@_cdecl("kk_op_safe_cast")
public func kk_op_safe_cast(_ value: Int, _ typeToken: Int) -> Int {
    kk_op_is(value, typeToken) != 0 ? value : runtimeNullSentinelInt
}

@_cdecl("kk_op_contains")
public func kk_op_contains(_ container: Int, _ element: Int) -> Int {
    // Range check first
    if let range = runtimeRangeBox(from: container) {
        return runtimeRangeContains(range, element)
    }
    // List check
    if let list = runtimeListBox(from: container) {
        return list.values.contains(where: { runtimeValuesEqual($0.legacyRawValue, element) }) ? 1 : 0
    }
    // Set check
    if let set = runtimeSetBox(from: container) {
        return set.contains(rawValue: element) ? 1 : 0
    }
    // Array check — `RuntimeObjectBox` subclasses `RuntimeArrayBox`, so plain
    // `runtimeArrayBox` would also match class instances (whose storage holds
    // fields, not elements) and wrongly answer `false` for `x in obj`.
    if let array = runtimeArrayBoxExcludingObjects(from: container) {
        return array.values.contains(where: { runtimeValuesEqual($0.legacyRawValue, element) }) ? 1 : 0
    }
    // Source-defined collections (e.g. `class C : List<Int> by delegate`)
    // are not native boxes; dispatch through the object's Collection itable.
    return runtimeSourceInterfaceCall1(
        container,
        element,
        interfaceTypeID: runtimeStableNominalTypeID(fqName: "kotlin.collections.Collection"),
        methodSlot: 1,
        context: "Collection.contains dispatch"
    ) ?? 0
}
