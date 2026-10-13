private let charSequenceIteratorTypeID = runtimeStableNominalTypeID(
    fqName: "kotlin.text.CharSequenceCharIterator"
)
private let charIteratorTypeID = runtimeStableNominalTypeID(
    fqName: "kotlin.collections.CharIterator"
)

/// Source-backed `CharIterator` returns its concrete Char representation at
/// the iterator ABI boundary. Preserve that type when a generic runtime bridge
/// materializes the iterator as `RuntimeValue`.
func runtimeSourceIteratorValue(_ rawValue: Int, iteratorRaw: Int) -> RuntimeValue {
    let isCharSequenceIterator: Bool = if let iteratorTypeID = runtimeObjectTypeID(rawValue: iteratorRaw) {
        iteratorTypeID == charSequenceIteratorTypeID
            || runtimeIsAssignable(sourceTypeID: iteratorTypeID, targetTypeID: charIteratorTypeID)
    } else {
        false
    }
    if isCharSequenceIterator {
        return RuntimeValue(charScalar: kk_unbox_char(rawValue))
    }
    return RuntimeValue(raw: rawValue)
}

/// Preserves the representation of values crossing a generic collection ABI.
/// Primitive `Char` values are boxed at this boundary so a later generic
/// consumer can recover the character instead of treating its UTF-16 scalar as
/// an `Int`.
@inline(__always)
func runtimeValueFromCollectionABI(_ rawValue: Int) -> RuntimeValue {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: rawValue),
          runtimeStorage.withGCLock({ state in
              state.objectPointers.contains(UInt(bitPattern: pointer))
          }),
          let charBox = tryCast(pointer, to: RuntimeCharBox.self)
    else {
        return RuntimeValue(raw: rawValue)
    }
    return RuntimeValue(charScalar: charBox.value)
}

/// Converts a tagged value to the legacy raw ABI representation used by
/// collection iterator/accessor entry points. `Char` is the one primitive whose
/// type identity must survive this conversion for generic collection consumers.
@inline(__always)
func runtimeCollectionABIValue(_ value: RuntimeValue) -> Int {
    if value.tag == RuntimeValue.charTag {
        return kk_box_char(value.payload0)
    }
    return value.legacyRawValue
}

func runtimeIterableElements(from rawValue: Int) -> [Int]? {
    runtimeIterableValues(from: rawValue)?.map(\.legacyRawValue)
}

func runtimeListIteratorBox(from rawValue: Int) -> RuntimeListIteratorBox? {
    resolveRuntimeHandle(rawValue, as: RuntimeListIteratorBox.self)
}

func runtimeIndexingIterableBox(from rawValue: Int) -> RuntimeIndexingIterableBox? {
    resolveRuntimeHandle(rawValue, as: RuntimeIndexingIterableBox.self)
}

func runtimeMapIteratorBox(from rawValue: Int) -> RuntimeMapIteratorBox? {
    resolveRuntimeHandle(rawValue, as: RuntimeMapIteratorBox.self)
}

func runtimeMutableMapIteratorBox(from rawValue: Int) -> RuntimeMutableMapIteratorBox? {
    resolveRuntimeHandle(rawValue, as: RuntimeMutableMapIteratorBox.self)
}


func runtimeMapArrayPair(
    keysRaw: Int,
    valuesRaw: Int
) -> (keys: [Int], values: [Int])? {
    guard let keysArray = runtimeArrayBox(from: keysRaw),
          let valuesArray = runtimeArrayBox(from: valuesRaw)
    else {
        return nil
    }
    return (keysArray.elements, valuesArray.elements)
}

func registerRuntimeObject(_ box: AnyObject) -> Int {
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    let raw = Int(bitPattern: opaque)
    registerRuntimeCollectionBoxIdentity(raw: raw, box: box)
    maybeRegisterCollectionIterableItable(raw: raw, box: box)
    if box is RuntimeStringBox {
        runtimeRegisterCharSequenceItable(raw)
    }
    return raw
}

func registerRuntimeObject(_ box: AnyObject, typeID: Int64) -> Int {
    let raw = registerRuntimeObject(box)
    runtimeRegisterObjectType(rawValue: raw, classID: typeID)
    runtimeRegisterKCallableItableIfNeeded(rawValue: raw, typeID: typeID)
    return raw
}

func runtimeRegisterViewOrEmpty<Source: AnyObject, View: AnyObject>(
    from rawValue: Int,
    resolve: (Int) -> Source?,
    makeEmpty: () -> View,
    makeView: (Source) -> View,
    typeID: Int64
) -> Int {
    let box = resolve(rawValue).map(makeView) ?? makeEmpty()
    return registerRuntimeObject(box, typeID: typeID)
}

/// Registers a primitive-domain box (`RuntimeIntBox` & friends) under its
/// tagged handle — the same representation `kk_box_*` emits — so the object's
/// raw address never enters `objectPointers`. A raw scalar that numerically
/// equals such an address can then no longer satisfy the `kk_box_*`
/// pass-through probe as an "already-registered object" (KUU-857). The
/// `typeID` is keyed by the returned tagged handle — every
/// `runtimeObjectTypeID` call site passes the stored handle verbatim.
func registerTaggedRuntimeObject(_ box: AnyObject, typeID: Int64) -> Int {
    let handle = runtimeStorage.withGCLock { state in
        registerTaggedPrimitiveBox(box, inLockedState: &state)
    }
    runtimeRegisterObjectType(rawValue: handle, classID: typeID)
    return handle
}

private let runtimeIteratorInterfaceTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.collections.Iterator")
private let runtimeListIteratorInterfaceTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.collections.ListIterator")
private let runtimeMutableIteratorInterfaceTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.collections.MutableIterator")
private let runtimeMutableListIteratorInterfaceTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.collections.MutableListIterator")
private let runtimeIterableInterfaceTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.collections.Iterable")
private let runtimeMutableIterableInterfaceTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.collections.MutableIterable")
private let runtimeSequenceInterfaceTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.sequences.Sequence")

/// Register the `kotlin.collections.Iterator` itable on a raw object handle.
func registerIteratorItable(
    raw: Int,
    hasNext: @convention(c) @escaping (Int, UnsafeMutablePointer<Int>?) -> Int,
    next: @convention(c) @escaping (Int, UnsafeMutablePointer<Int>?) -> Int,
    remove: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int)? = nil,
    mutableIterator: Bool = false
) {
    _ = kk_object_register_itable_iface(raw, Int(runtimeIteratorInterfaceTypeID), 0)
    let hasNextPtr = unsafeBitCast(hasNext, to: Int.self)
    _ = kk_object_register_itable_method(raw, 0, 0, hasNextPtr)
    let nextPtr = unsafeBitCast(next, to: Int.self)
    _ = kk_object_register_itable_method(raw, 0, 1, nextPtr)
    if let remove {
        let removePtr = unsafeBitCast(remove, to: Int.self)
        _ = kk_object_register_itable_method(raw, 0, 2, removePtr)
        if mutableIterator {
            // MutableIterator declares remove as its direct method at slot 0.
            _ = kk_object_register_itable_iface(raw, Int(runtimeMutableIteratorInterfaceTypeID), 1)
            _ = kk_object_register_itable_method(raw, 1, 0, removePtr)
        }
    }
}

/// Register the six `ListIterator` methods on a runtime-backed list iterator.
/// KSP-1064: `next`/`hasNext` are now declared directly on `ListIterator`
/// (rather than purely inherited from `Iterator`), so member calls through a
/// `ListIterator`/`MutableListIterator`-typed receiver resolve them as
/// `ListIterator`'s own vtable slots 0/1 — the same layout that assigns
/// `hasPrevious`/`previous`/`nextIndex`/`previousIndex` to slots 2 through 5.
/// Both slot ranges must be registered under this same itable (ifaceSlot 1),
/// even though slots 0/1 duplicate the `Iterator` itable already registered
/// at ifaceSlot 0 for the plain `Iterator<T>` receiver case.
func registerListIteratorItable(raw: Int) {
    _ = kk_object_register_itable_iface(raw, Int(runtimeListIteratorInterfaceTypeID), 1)
    let nextPtr = unsafeBitCast(runtimeListIteratorNextThunk, to: Int.self)
    _ = kk_object_register_itable_method(raw, 1, 0, nextPtr)
    let hasNextPtr = unsafeBitCast(runtimeListIteratorHasNextThunk, to: Int.self)
    _ = kk_object_register_itable_method(raw, 1, 1, hasNextPtr)
    let hasPreviousPtr = unsafeBitCast(runtimeListIteratorHasPreviousThunk, to: Int.self)
    _ = kk_object_register_itable_method(raw, 1, 2, hasPreviousPtr)
    let previousPtr = unsafeBitCast(runtimeListIteratorPreviousThunk, to: Int.self)
    _ = kk_object_register_itable_method(raw, 1, 3, previousPtr)
    let nextIndexPtr = unsafeBitCast(runtimeListIteratorNextIndexThunk, to: Int.self)
    _ = kk_object_register_itable_method(raw, 1, 4, nextIndexPtr)
    let previousIndexPtr = unsafeBitCast(runtimeListIteratorPreviousIndexThunk, to: Int.self)
    _ = kk_object_register_itable_method(raw, 1, 5, previousIndexPtr)
}

/// Register the `MutableListIterator.set`/`.add` methods on a runtime-backed
/// mutable list iterator. A separate function (rather than folding this into
/// `registerListIteratorItable` or the `RuntimeListIteratorBox` overload of
/// `registerRuntimeObject` above) so it can be called only where the box
/// actually carries `setAction`/`addAction` (`kk_list_iterator`'s
/// `List`/`MutableList` branch and `kk_list_iterator_at`), without touching
/// either of those two call/registration sites. Slot 3 is free: 0=Iterator,
/// 1=ListIterator, and MutableIterator additionally claims 1 by default on
/// this same object (a pre-existing, separately-tracked itable slot
/// collision) — 2 and 3 are the first indices neither one uses.
func registerMutableListIteratorItable(raw: Int) {
    _ = kk_object_register_itable_iface(raw, Int(runtimeMutableListIteratorInterfaceTypeID), 3)
    let setPtr = unsafeBitCast(runtimeListIteratorSetThunk, to: Int.self)
    _ = kk_object_register_itable_method(raw, 3, 0, setPtr)
    let addPtr = unsafeBitCast(runtimeListIteratorAddThunk, to: Int.self)
    _ = kk_object_register_itable_method(raw, 3, 1, addPtr)
}

private let runtimeListIteratorSetThunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { raw, elem, outThrown in
    outThrown?.pointee = 0
    return runtimeListIteratorSet(raw, elem, outThrown)
}

private let runtimeListIteratorAddThunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { raw, elem, outThrown in
    outThrown?.pointee = 0
    return runtimeListIteratorAdd(raw, elem, outThrown)
}

private let runtimeListIteratorHasPreviousThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, outThrown in
    outThrown?.pointee = 0
    return kk_list_iterator_hasPrevious(raw)
}

private let runtimeListIteratorPreviousThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, outThrown in
    outThrown?.pointee = 0
    guard let iter = runtimeListIteratorBox(from: raw), listIteratorCanGoBack(iter) else {
        runtimeSetThrown(outThrown, runtimeAllocateNoSuchElementException(message: "List iterator has no previous element."))
        return 0
    }
    return kk_list_iterator_previous(raw)
}

private let runtimeListIteratorNextIndexThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, outThrown in
    outThrown?.pointee = 0
    return kk_list_iterator_nextIndex(raw)
}

private let runtimeListIteratorPreviousIndexThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, outThrown in
    outThrown?.pointee = 0
    return kk_list_iterator_previousIndex(raw)
}

/// Register the `kotlin.collections.MutableIterator` itable on a raw object handle.
private func registerMutableIteratorItable(
    raw: Int,
    remove: @convention(c) @escaping (Int, UnsafeMutablePointer<Int>?) -> Int,
    ifaceSlot: Int = 1
) {
    _ = kk_object_register_itable_iface(raw, Int(runtimeMutableIteratorInterfaceTypeID), ifaceSlot)
    let removePtr = unsafeBitCast(remove, to: Int.self)
    _ = kk_object_register_itable_method(raw, ifaceSlot, 0, removePtr)
}

/// Register the `kotlin.collections.Iterable` itable on a raw object handle.
private func registerIterableItable(raw: Int, ifaceSlot: Int = 0) {
    _ = kk_object_register_itable_iface(raw, Int(runtimeIterableInterfaceTypeID), ifaceSlot)
    let iteratorPtr = unsafeBitCast(runtimeIterableIteratorThunk, to: Int.self)
    _ = kk_object_register_itable_method(raw, ifaceSlot, 0, iteratorPtr)
}

/// Register the `kotlin.collections.MutableIterable` itable on a raw object handle.
private func registerMutableIterableItable(raw: Int, ifaceSlot: Int = 2) {
    _ = kk_object_register_itable_iface(raw, Int(runtimeMutableIterableInterfaceTypeID), ifaceSlot)
    let iteratorPtr = unsafeBitCast(runtimeIterableIteratorThunk, to: Int.self)
    _ = kk_object_register_itable_method(raw, ifaceSlot, 0, iteratorPtr)
}

/// Register the `kotlin.sequences.Sequence` itable on a raw object handle.
private func registerSequenceItable(raw: Int, ifaceSlot: Int = 1) {
    _ = kk_object_register_itable_iface(raw, Int(runtimeSequenceInterfaceTypeID), ifaceSlot)
    let iteratorPtr = unsafeBitCast(runtimeIterableIteratorThunk, to: Int.self)
    _ = kk_object_register_itable_method(raw, ifaceSlot, 0, iteratorPtr)
}

private let runtimeIterableIteratorThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { iterableRaw, outThrown in
    outThrown?.pointee = 0
    return kk_list_iterator(iterableRaw)
}

private func maybeRegisterCollectionIterableItable(raw: Int, box: AnyObject) {
    // Runtime-backed collection boxes may be passed as `Iterable<T>` from
    // source-implemented `Sequence` wrappers (e.g. a `List` returned by a
    // `flatMap` lambda typed as `Iterable`). Register `Iterable.iterator()`
    // so interface dispatch works on those boxes.
    //
    // Some source-implemented `Sequence` HOF overloads are resolved to the
    // `Sequence` variant even when the lambda returns a `List`/`Set`/array
    // (which is `Iterable` but not actually `Sequence`); registering the
    // `Sequence` itable lets the generated `Sequence.iterator()` dispatch
    // reach the same runtime-backed iterator. `is` checks still consult the
    // nominal class hierarchy, so this does not make `List`/`Set` report as
    // `Sequence`.
    if box is RuntimeArrayDequeBox {
        runtimeRegisterObjectType(rawValue: raw, classID: arrayDequeRuntimeTypeID)
        registerIterableItable(raw: raw, ifaceSlot: 0)
        registerSequenceItable(raw: raw, ifaceSlot: 1)
        registerMutableIterableItable(raw: raw, ifaceSlot: 2)
    } else if box is RuntimeListBox {
        runtimeRegisterObjectType(rawValue: raw, classID: listRuntimeTypeID)
        registerIterableItable(raw: raw, ifaceSlot: 0)
        registerSequenceItable(raw: raw, ifaceSlot: 1)
        registerMutableIterableItable(raw: raw, ifaceSlot: 2)
    } else if box is RuntimeSetBox {
        runtimeRegisterObjectType(rawValue: raw, classID: setRuntimeTypeID)
        registerIterableItable(raw: raw, ifaceSlot: 0)
        registerSequenceItable(raw: raw, ifaceSlot: 1)
        registerMutableIterableItable(raw: raw, ifaceSlot: 2)
    } else if type(of: box) == RuntimeArrayBox.self {
        registerIterableItable(raw: raw, ifaceSlot: 0)
        registerSequenceItable(raw: raw, ifaceSlot: 1)
    }
}

// MARK: - Iterator box itable registration

// Runtime-backed iterator boxes are returned by `iterator()` calls resolved
// through the synthetic collection fallback (e.g. `List.iterator()`). When a
// source-implemented `Sequence`/`Iterator` wrapper stores such an iterator as
// an `Iterator<T>` interface value, subsequent `hasNext()`/`next()` calls use
// itable dispatch and need the box to advertise those methods.

let runtimeListIteratorHasNextThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { iterRaw, outThrown in
    outThrown?.pointee = 0
    return kk_list_iterator_hasNext(iterRaw)
}

let runtimeListIteratorNextThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { iterRaw, outThrown in
    return kk_list_iterator_next(iterRaw, outThrown)
}

private let runtimeListIteratorRemoveThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { iterRaw, outThrown in
    outThrown?.pointee = 0
    return runtimeListIteratorRemove(iterRaw, outThrown)
}

private func registerRuntimeListIteratorItables(raw: Int, box: RuntimeListIteratorBox) {
    registerIteratorItable(raw: raw, hasNext: runtimeListIteratorHasNextThunk, next: runtimeListIteratorNextThunk)
    if box.removeAction != nil {
        // KSP-1064: `registerListIteratorItable` below always claims ifaceSlot 1
        // for this same object's `ListIterator` itable. `MutableIterator`'s
        // default ifaceSlot (1) would collide with it — both tables would then
        // share method slot 0, so a `MutableListIterator.next()` call (now
        // itable-dispatched since ListIterator declares `next`/`hasNext`
        // itself) landed on `MutableIterator.remove` instead. Slot 2 is unused
        // on this object (0=Iterator, 1=ListIterator).
        registerMutableIteratorItable(raw: raw, remove: runtimeListIteratorRemoveThunk, ifaceSlot: 2)
    }
}

private let runtimeRangeIteratorHasNextThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { iterRaw, outThrown in
    outThrown?.pointee = 0
    return kk_range_hasNext(iterRaw)
}

private let runtimeRangeIteratorNextThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { iterRaw, outThrown in
    kk_iterator_next(iterRaw, outThrown)
}

private let runtimeMapIteratorHasNextThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { iterRaw, outThrown in
    outThrown?.pointee = 0
    return kk_map_iterator_hasNext(iterRaw)
}

private let runtimeMapIteratorNextThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { iterRaw, outThrown in
    return kk_map_iterator_next(iterRaw, outThrown)
}

private let runtimeMutableMapIteratorHasNextThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { iterRaw, outThrown in
    outThrown?.pointee = 0
    return kk_mutable_map_iterator_hasNext(iterRaw)
}

private let runtimeMutableMapIteratorNextThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { iterRaw, outThrown in
    return kk_mutable_map_iterator_next(iterRaw, outThrown)
}

private let runtimeMutableMapIteratorRemoveThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { iterRaw, outThrown in
    kk_mutable_map_iterator_remove(iterRaw, outThrown)
}

private let runtimeIndexingIterableIteratorThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, outThrown in
    outThrown?.pointee = 0
    return kk_indexing_iterable_iterator(raw)
}

private let runtimeSequenceIteratorHasNextThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, outThrown in
    kk_sequence_iterator_hasNext(raw, outThrown)
}

private let runtimeSequenceIteratorNextThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, outThrown in
    kk_sequence_iterator_next(raw, outThrown)
}

private let runtimeGenericIteratorHasNextThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, outThrown in
    kk_iterator_hasNext(raw, outThrown)
}

private let runtimeGenericIteratorNextThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, outThrown in
    kk_iterator_next(raw, outThrown)
}

private func registerRuntimeCollectionBoxIdentity(raw: Int, box: AnyObject) {
    let typeID: Int64
    switch box {
    case is RuntimeMapBox:
        typeID = mapRuntimeTypeID
    case let iterator as RuntimeListIteratorBox:
        typeID = iterator.removeAction == nil ? runtimeIteratorInterfaceTypeID : runtimeMutableIteratorInterfaceTypeID
        registerRuntimeListIteratorItables(raw: raw, box: iterator)
    case is RuntimeRangeIteratorBox:
        typeID = runtimeIteratorInterfaceTypeID
        registerIteratorItable(raw: raw, hasNext: runtimeRangeIteratorHasNextThunk, next: runtimeRangeIteratorNextThunk)
    case is RuntimeMapIteratorBox:
        typeID = runtimeIteratorInterfaceTypeID
        registerIteratorItable(raw: raw, hasNext: runtimeMapIteratorHasNextThunk, next: runtimeMapIteratorNextThunk)
    case is RuntimeMutableMapIteratorBox:
        typeID = runtimeMutableIteratorInterfaceTypeID
        registerIteratorItable(
            raw: raw,
            hasNext: runtimeMutableMapIteratorHasNextThunk,
            next: runtimeMutableMapIteratorNextThunk,
            remove: runtimeMutableMapIteratorRemoveThunk,
            mutableIterator: true
        )
    case is RuntimeSequenceIteratorBox:
        typeID = runtimeIteratorInterfaceTypeID
        registerIteratorItable(raw: raw, hasNext: runtimeSequenceIteratorHasNextThunk, next: runtimeSequenceIteratorNextThunk)
    case is RuntimeIndexingIteratorBox, is RuntimeIteratorBuilderBox, is RuntimeBufferedLineIteratorBox:
        typeID = runtimeIteratorInterfaceTypeID
        registerIteratorItable(raw: raw, hasNext: runtimeGenericIteratorHasNextThunk, next: runtimeGenericIteratorNextThunk)
    case is RuntimeSequenceBox:
        typeID = runtimeSequenceInterfaceTypeID
        registerRuntimeSequenceItable(raw: raw)
    case is RuntimeIndexingIterableBox:
        typeID = runtimeIterableInterfaceTypeID
        _ = kk_object_register_itable_iface(raw, Int(runtimeIterableInterfaceTypeID), 0)
        _ = kk_object_register_itable_method(raw, 0, 0, unsafeBitCast(runtimeIndexingIterableIteratorThunk, to: Int.self))
    default:
        return
    }
    runtimeRegisterObjectType(rawValue: raw, classID: typeID)
    if typeID == runtimeMutableIteratorInterfaceTypeID {
        runtimeRegisterTypeEdge(childTypeID: typeID, parentTypeID: runtimeIteratorInterfaceTypeID)
    }
}
