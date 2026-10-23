import Foundation

final class RuntimeKPropertyStub {
    let name: Int // intptr_t to a KKString (property name)
    let returnType: Int // intptr_t to a KKString (return type signature)
    let visibility: Int // intptr_t to a KKString (e.g. "PUBLIC", "INTERNAL", etc.)
    let isLateinit: Bool
    let isConst: Bool
    let returnTypeKTypeRaw: Int
    let isMutable: Bool
    /// KUU-2947: a `val/var x by Delegate()` declared inside a function hands
    /// getValue/setValue a KProperty0-shaped stub (KMutableProperty0 for `var`)
    /// whose accessor members throw UnsupportedOperationException instead of
    /// reading storage that does not exist — matching the JVM's
    /// PropertyReference0Impl behavior for local delegated properties.
    let isLocalDelegated: Bool

    init(
        name: Int,
        returnType: Int,
        visibility: Int = 0,
        isLateinit: Bool = false,
        isConst: Bool = false,
        returnTypeKTypeRaw: Int = 0,
        isMutable: Bool = false,
        isLocalDelegated: Bool = false
    ) {
        self.name = name
        self.returnType = returnType
        self.visibility = visibility
        self.isLateinit = isLateinit
        self.isConst = isConst
        self.returnTypeKTypeRaw = returnTypeKTypeRaw
        self.isMutable = isMutable
        self.isLocalDelegated = isLocalDelegated
    }
}

@_cdecl("__kk_kproperty_stub_create_cached_typed")
public func kk_kproperty_stub_create_cached_typed(
    _ nameRaw: Int,
    _ returnTypeRaw: Int,
    _ identityRaw: Int,
    _ returnTypeKTypeRaw: Int,
    _ arity: Int,
    _ isMutable: Int
) -> Int {
    guard let identity = runtimeStringFromRaw(identityRaw) else {
        return kk_kproperty_stub_create(nameRaw, returnTypeRaw)
    }
    let typeID: Int64
    switch (arity, isMutable != 0) {
    case (0, false): typeID = kProperty0RuntimeTypeID
    case (0, true): typeID = kMutableProperty0RuntimeTypeID
    case (1, false): typeID = kProperty1RuntimeTypeID
    case (1, true): typeID = kMutableProperty1RuntimeTypeID
    default: typeID = kPropertyRuntimeTypeID
    }
    return runtimeStorage.withDelegatedPropertyStubLock {
        if let cached = runtimeStorage.withMetadataLock({ $0.delegatedPropertyStubCache[identity] }) {
            return cached
        }

        registerReflectionRuntimeTypeMetadata()
        let created = registerRuntimeObject(
            RuntimeKPropertyStub(
                name: nameRaw,
                returnType: returnTypeRaw,
                returnTypeKTypeRaw: returnTypeKTypeRaw,
                isMutable: isMutable != 0
            ),
            typeID: typeID
        )
        runtimeRegisterKCallableItableIfNeeded(rawValue: created, typeID: typeID)
        return runtimeStorage.withMetadataLock { state in
            state.delegatedPropertyStubCache[identity] = created
            return created
        }
    }
}
private func runtimeTagCallableRef(
    _ callable: Int,
    name: Int,
    returnType: Int,
    arity: Int,
    kind: RuntimeCallableRefKind,
    isSuspend: Bool = false,
    modifierFlags: Int = 0
) -> Int {
    runtimeStorage.withDelegateLock { state in
        state.callableRefMetadataByValue[callable] = RuntimeCallableRefMetadata(
            nameRaw: name,
            returnTypeRaw: returnType,
            arity: arity,
            kind: kind,
            isSuspend: isSuspend,
            modifierFlags: modifierFlags
        )
    }
    runtimeRegisterKCallableItableIfNeeded(
        rawValue: callable,
        typeID: kind == .function ? kFunctionRuntimeTypeID : kPropertyRuntimeTypeID
    )
    return callable
}

/// `flags` packs KFunction modifier bits: bit0=suspend, bit1=inline,
/// bit2=operator, bit3=infix, bit4=external. Legacy callers passing a bare
/// 0/1 suspend flag are compatible with the packed layout (KUU-1357).
@_cdecl("kk_callable_ref_tag_kfunction")
public func kk_callable_ref_tag_kfunction(_ callable: Int, _ name: Int, _ returnType: Int, _ arity: Int, _ flags: Int) -> Int {
    runtimeTagCallableRef(
        callable, name: name, returnType: returnType, arity: arity, kind: .function,
        isSuspend: (flags & RuntimeKFunctionFlags.suspend) != 0,
        modifierFlags: flags & ~RuntimeKFunctionFlags.suspend
    )
}

@_cdecl("kk_callable_ref_tag_kproperty")
public func kk_callable_ref_tag_kproperty(_ callable: Int, _ name: Int, _ returnType: Int, _ arity: Int) -> Int {
    runtimeTagCallableRef(callable, name: name, returnType: returnType, arity: arity, kind: .property, isSuspend: false)
}

@_cdecl("__kk_kproperty_stub_create")
public func kk_kproperty_stub_create(_ nameStr: Int, _ returnTypeStr: Int) -> Int {
    let stub = RuntimeKPropertyStub(name: nameStr, returnType: returnTypeStr)
    registerReflectionRuntimeTypeMetadata()
    return registerRuntimeObject(stub, typeID: kPropertyRuntimeTypeID)
}

/// Returns one KProperty stub per delegated declaration so getValue, setValue,
/// and provideDelegate observe the same property identity across accesses.
@_cdecl("__kk_kproperty_stub_create_cached")
public func kk_kproperty_stub_create_cached(
    _ nameStr: Int,
    _ returnTypeStr: Int,
    _ identityStr: Int
) -> Int {
    guard let identity = runtimeStringFromRaw(identityStr) else {
        return kk_kproperty_stub_create(nameStr, returnTypeStr)
    }
    return runtimeStorage.withDelegatedPropertyStubLock {
        if let cached = runtimeStorage.withMetadataLock({ $0.delegatedPropertyStubCache[identity] }) {
            return cached
        }

        registerReflectionRuntimeTypeMetadata()
        let created = registerRuntimeObject(
            RuntimeKPropertyStub(name: nameStr, returnType: returnTypeStr),
            typeID: kPropertyRuntimeTypeID
        )
        return runtimeStorage.withMetadataLock { state in
            state.delegatedPropertyStubCache[identity] = created
            return created
        }
    }
}

/// The message the JVM's local-delegated property reference (a
/// `PropertyReference0Impl`/`MutablePropertyReference0Impl`) raises from
/// `get`/`set`/`invoke`/`call`/`callBy`, because there is no real accessor to
/// invoke for a local declaration.
private let kLocalDelegatedCallUnsupportedMessage =
    "call/callBy are not supported for this declaration."

/// itable signature for `get`/`invoke`/`getDelegate` (arity 0): the emitted
/// virtual call passes the receiver plus the appended thrown channel.
private let runtimeLocalDelegatedPropertyGet: @convention(c) (
    Int,
    UnsafeMutablePointer<Int>?
) -> Int = { _, thrown in
    thrown?.pointee = runtimeAllocateUnsupportedOperationException(
        message: kLocalDelegatedCallUnsupportedMessage
    )
    return runtimeNullSentinelInt
}

private let runtimeLocalDelegatedPropertyInvoke: @convention(c) (
    Int,
    UnsafeMutablePointer<Int>?
) -> Int = { _, thrown in
    thrown?.pointee = runtimeAllocateUnsupportedOperationException(
        message: kLocalDelegatedCallUnsupportedMessage
    )
    return runtimeNullSentinelInt
}

/// `getDelegate()` on a local delegated property returns null on the JVM —
/// the property has no bound delegate — rather than throwing.
private let runtimeLocalDelegatedPropertyGetDelegate: @convention(c) (
    Int,
    UnsafeMutablePointer<Int>?
) -> Int = { _, thrown in
    thrown?.pointee = 0
    return runtimeNullSentinelInt
}

private let runtimeLocalDelegatedPropertySet: @convention(c) (
    Int,
    Int,
    UnsafeMutablePointer<Int>?
) -> Int = { _, _, thrown in
    thrown?.pointee = runtimeAllocateUnsupportedOperationException(
        message: kLocalDelegatedCallUnsupportedMessage
    )
    return runtimeNullSentinelInt
}

/// The thrown channel of `invokeCallable`: (environment, arguments, mask,
/// outThrown) -> Int. `KProperty0.Getter`/`KMutableProperty0.Setter` boxes for
/// local delegated properties route `.call()` through it so both `call()` and
/// `invoke()` raise the same UnsupportedOperationException.
private let runtimeLocalDelegatedAccessorCall: @convention(c) (
    Int,
    Int,
    Int,
    UnsafeMutablePointer<Int>?
) -> Int = { _, _, _, thrown in
    thrown?.pointee = runtimeAllocateUnsupportedOperationException(
        message: kLocalDelegatedCallUnsupportedMessage
    )
    return runtimeNullSentinelInt
}

private let runtimeLocalDelegatedAccessorInvoke0: @convention(c) (
    Int,
    UnsafeMutablePointer<Int>?
) -> Int = { _, thrown in
    thrown?.pointee = runtimeAllocateUnsupportedOperationException(
        message: kLocalDelegatedCallUnsupportedMessage
    )
    return runtimeNullSentinelInt
}

private let runtimeLocalDelegatedAccessorInvoke1: @convention(c) (
    Int,
    Int,
    UnsafeMutablePointer<Int>?
) -> Int = { _, _, thrown in
    thrown?.pointee = runtimeAllocateUnsupportedOperationException(
        message: kLocalDelegatedCallUnsupportedMessage
    )
    return runtimeNullSentinelInt
}

/// KProperty0's itable slots (own methods get/getDelegate/invoke in
/// declaration order) and KMutableProperty0's `set` slot — matched to the
/// layout `LayoutSynthesis` computes for the bundled `kotlin.reflect` source.
private enum RuntimeLocalDelegatedItable {
    static let kProperty0InterfaceSlot = 1
    static let kMutableProperty0InterfaceSlot = 2
    static let getMethodSlot = 0
    static let getDelegateMethodSlot = 1
    static let invokeMethodSlot = 2
    static let setMethodSlot = 0
}

func runtimeRegisterLocalDelegatedPropertyItable(rawValue: Int, isMutable: Bool) {
    _ = kk_object_register_itable_iface(
        rawValue, Int(kProperty0RuntimeTypeID), RuntimeLocalDelegatedItable.kProperty0InterfaceSlot
    )
    _ = kk_object_register_itable_method(
        rawValue,
        RuntimeLocalDelegatedItable.kProperty0InterfaceSlot,
        RuntimeLocalDelegatedItable.getMethodSlot,
        unsafeBitCast(runtimeLocalDelegatedPropertyGet, to: Int.self)
    )
    _ = kk_object_register_itable_method(
        rawValue,
        RuntimeLocalDelegatedItable.kProperty0InterfaceSlot,
        RuntimeLocalDelegatedItable.getDelegateMethodSlot,
        unsafeBitCast(runtimeLocalDelegatedPropertyGetDelegate, to: Int.self)
    )
    _ = kk_object_register_itable_method(
        rawValue,
        RuntimeLocalDelegatedItable.kProperty0InterfaceSlot,
        RuntimeLocalDelegatedItable.invokeMethodSlot,
        unsafeBitCast(runtimeLocalDelegatedPropertyInvoke, to: Int.self)
    )
    guard isMutable else { return }
    _ = kk_object_register_itable_iface(
        rawValue, Int(kMutableProperty0RuntimeTypeID), RuntimeLocalDelegatedItable.kMutableProperty0InterfaceSlot
    )
    _ = kk_object_register_itable_method(
        rawValue,
        RuntimeLocalDelegatedItable.kMutableProperty0InterfaceSlot,
        RuntimeLocalDelegatedItable.setMethodSlot,
        unsafeBitCast(runtimeLocalDelegatedPropertySet, to: Int.self)
    )
}

/// The `KProperty0.Getter`/`KMutableProperty0.Setter` a local delegated
/// property stub hands out. The JVM returns a real accessor object whose
/// call/invoke raise UnsupportedOperationException, so fabricate a KFunction
/// box whose call path does the same instead of handing back null.
func runtimeLocalDelegatedPropertyAccessor(raw: Int, stub: RuntimeKPropertyStub, isSetter: Bool) -> Int {
    let arity = isSetter ? 1 : 0
    let fnPtr: Int
    if isSetter {
        fnPtr = unsafeBitCast(runtimeLocalDelegatedAccessorInvoke1, to: Int.self)
    } else {
        fnPtr = unsafeBitCast(runtimeLocalDelegatedAccessorInvoke0, to: Int.self)
    }
    let name = extractString(from: UnsafeMutableRawPointer(bitPattern: stub.name)) ?? ""
    let metadata = RuntimeCallableRefMetadata(
        nameRaw: runtimeMakeStringRaw(isSetter ? "<set-\(name)>" : "<get-\(name)>"),
        returnTypeRaw: isSetter ? runtimeMakeStringRaw("Unit") : stub.returnType,
        arity: arity,
        kind: .function,
        isSuspend: false,
        invoker: unsafeBitCast(runtimeLocalDelegatedAccessorCall, to: Int.self),
        property: raw
    )
    let context = RuntimePropertyAccessorContext(metadata: metadata)
    let contextRaw = registerRuntimeObject(context)
    let box = RuntimeFunctionValueBox(fnPtr: fnPtr, closureRaw: contextRaw, arity: arity)
    registerReflectionRuntimeTypeMetadata()
    let accessor = registerRuntimeObject(box, typeID: kFunctionRuntimeTypeID)
    context.metadata = metadata
    runtimeStorage.withDelegateLock { $0.callableRefMetadataByValue[accessor] = metadata }
    return accessor
}

/// Local delegated properties hand their getValue/setValue a KProperty0
/// (KMutableProperty0 for `var`) stub whose accessor members throw
/// UnsupportedOperationException, matching the JVM's
/// PropertyReference0Impl/MutablePropertyReference0Impl.
@_cdecl("__kk_kproperty_stub_create_local")
public func kk_kproperty_stub_create_local(
    _ nameStr: Int,
    _ returnTypeStr: Int,
    _ identityStr: Int,
    _ isMutable: Int
) -> Int {
    let isMutableFlag = isMutable != 0
    guard let identity = runtimeStringFromRaw(identityStr) else {
        registerReflectionRuntimeTypeMetadata()
        let stub = RuntimeKPropertyStub(
            name: nameStr, returnType: returnTypeStr, isLocalDelegated: true
        )
        let raw = registerRuntimeObject(
            stub,
            typeID: isMutableFlag ? kMutableProperty0RuntimeTypeID : kProperty0RuntimeTypeID
        )
        runtimeRegisterLocalDelegatedPropertyItable(rawValue: raw, isMutable: isMutableFlag)
        return raw
    }
    // Keep the identity space disjoint from `__kk_kproperty_stub_create_cached`:
    // a member/top-level stub answering the same identity is a different
    // reflection kind (plain KProperty) and must not be handed out here.
    let cacheKey = "local:\(identity)"
    return runtimeStorage.withDelegatedPropertyStubLock {
        if let cached = runtimeStorage.withMetadataLock({ $0.delegatedPropertyStubCache[cacheKey] }) {
            return cached
        }

        registerReflectionRuntimeTypeMetadata()
        let stub = RuntimeKPropertyStub(
            name: nameStr, returnType: returnTypeStr, isLocalDelegated: true
        )
        let created = registerRuntimeObject(
            stub,
            typeID: isMutableFlag ? kMutableProperty0RuntimeTypeID : kProperty0RuntimeTypeID
        )
        runtimeRegisterLocalDelegatedPropertyItable(rawValue: created, isMutable: isMutableFlag)
        return runtimeStorage.withMetadataLock { state in
            state.delegatedPropertyStubCache[cacheKey] = created
            return created
        }
    }
}

// (a) RF-DEAD-002: 配線予定 → MIGRATION-PROP-001 / STDLIB-REFLECT-062 (KProperty 完全メタデータ実装)
// __kk_kproperty_stub_{create_full,is_const,is_lateinit,visibility} は全て同タスクに紐付く。
@_cdecl("__kk_kproperty_stub_create_full")
public func kk_kproperty_stub_create_full(
    _ nameStr: Int,
    _ returnTypeStr: Int,
    _ visibilityStr: Int,
    _ isLateinit: Int,
    _ isConst: Int
) -> Int {
    let stub = RuntimeKPropertyStub(
        name: nameStr,
        returnType: returnTypeStr,
        visibility: visibilityStr,
        isLateinit: isLateinit != 0,
        isConst: isConst != 0
    )
    registerReflectionRuntimeTypeMetadata()
    return registerRuntimeObject(stub, typeID: kPropertyRuntimeTypeID)
}

@_cdecl("__kk_kproperty_stub_visibility")
public func kk_kproperty_stub_visibility(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle),
          runtimeStorage.withGCLock({ state in state.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let stub = tryCast(ptr, to: RuntimeKPropertyStub.self)
    else {
        return runtimeNullSentinelInt
    }
    if stub.visibility == 0 {
        if defaultKPropertyVisibilityPublicString == 0 {
            defaultKPropertyVisibilityPublicString = kk_kproperty_stub_make_string("PUBLIC")
        }
        return defaultKPropertyVisibilityPublicString
    }
    return stub.visibility
}

@_cdecl("__kk_kproperty_stub_is_lateinit")
public func kk_kproperty_stub_is_lateinit(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle),
          runtimeStorage.withGCLock({ state in state.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let stub = tryCast(ptr, to: RuntimeKPropertyStub.self)
    else {
        return 0
    }
    return stub.isLateinit ? 1 : 0
}

@_cdecl("__kk_kproperty_stub_is_const")
public func kk_kproperty_stub_is_const(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle),
          runtimeStorage.withGCLock({ state in state.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let stub = tryCast(ptr, to: RuntimeKPropertyStub.self)
    else {
        return 0
    }
    return stub.isConst ? 1 : 0
}


/// Initialized lazily on first use to avoid allocating a new string on every call.
private nonisolated(unsafe) var defaultKPropertyVisibilityPublicString: Int = 0

private func kk_kproperty_stub_make_string(_ s: String) -> Int {
    let utf8 = Array(s.utf8)
    guard !utf8.isEmpty else { return runtimeNullSentinelInt }
    return utf8.withUnsafeBufferPointer { buffer in
        Int(bitPattern: kk_string_from_utf8(buffer.baseAddress!, Int32(buffer.count)))
    }
}
