import Foundation

final class RuntimeKPropertyStub {
    let name: Int // intptr_t to a KKString (property name)
    let returnType: Int // intptr_t to a KKString (return type signature)
    let visibility: Int // intptr_t to a KKString (e.g. "PUBLIC", "INTERNAL", etc.)
    let isLateinit: Bool
    let isConst: Bool
    let returnTypeKTypeRaw: Int
    let isMutable: Bool

    init(
        name: Int,
        returnType: Int,
        visibility: Int = 0,
        isLateinit: Bool = false,
        isConst: Bool = false,
        returnTypeKTypeRaw: Int = 0,
        isMutable: Bool = false
    ) {
        self.name = name
        self.returnType = returnType
        self.visibility = visibility
        self.isLateinit = isLateinit
        self.isConst = isConst
        self.returnTypeKTypeRaw = returnTypeKTypeRaw
        self.isMutable = isMutable
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
