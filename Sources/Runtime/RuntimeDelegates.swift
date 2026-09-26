import Foundation

// MARK: - KProperty Stub (PROP-007, STDLIB-REFLECT-062)

/// Minimal KProperty<*> stub carrying property name and return type.
/// Used as the `property` argument for `provideDelegate`, `getValue`, and `setValue`.
final class RuntimeKPropertyStub {
    let name: Int // intptr_t to a KKString (property name)
    let returnType: Int // intptr_t to a KKString (return type signature)
    // STDLIB-REFLECT-062: extended KProperty fields
    let visibility: Int // intptr_t to a KKString (e.g. "PUBLIC", "INTERNAL", etc.)
    let isLateinit: Bool
    let isConst: Bool

    init(
        name: Int,
        returnType: Int,
        visibility: Int = 0,
        isLateinit: Bool = false,
        isConst: Bool = false
    ) {
        self.name = name
        self.returnType = returnType
        self.visibility = visibility
        self.isLateinit = isLateinit
        self.isConst = isConst
    }
}
private func runtimeTagCallableRef(
    _ callable: Int,
    name: Int,
    returnType: Int,
    arity: Int,
    kind: RuntimeCallableRefKind,
    isSuspend: Bool = false
) -> Int {
    runtimeStorage.withDelegateLock { state in
        state.callableRefMetadataByValue[callable] = RuntimeCallableRefMetadata(
            nameRaw: name,
            returnTypeRaw: returnType,
            arity: arity,
            kind: kind,
            isSuspend: isSuspend
        )
    }
    runtimeRegisterKCallableItableIfNeeded(
        rawValue: callable,
        typeID: kind == .function ? kFunctionRuntimeTypeID : kPropertyRuntimeTypeID
    )
    return callable
}

@_cdecl("kk_callable_ref_tag_kfunction")
public func kk_callable_ref_tag_kfunction(_ callable: Int, _ name: Int, _ returnType: Int, _ arity: Int, _ isSuspend: Int) -> Int {
    runtimeTagCallableRef(callable, name: name, returnType: returnType, arity: arity, kind: .function, isSuspend: isSuspend != 0)
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

// (a) RF-DEAD-002: 配線予定 → MIGRATION-PROP-001 / STDLIB-REFLECT-062 (KProperty 完全メタデータ実装)
// __kk_kproperty_stub_{create_full,is_const,is_lateinit,visibility} は全て同タスクに紐付く。
// STDLIB-REFLECT-062: extended create with full KProperty metadata
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

// STDLIB-REFLECT-062: visibility accessor
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

// STDLIB-REFLECT-062: isLateinit accessor
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

// STDLIB-REFLECT-062: isConst accessor
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


/// Cached KKString handle for the default "PUBLIC" visibility value.
/// Initialized lazily on first use to avoid allocating a new string on every call.
private nonisolated(unsafe) var defaultKPropertyVisibilityPublicString: Int = 0

/// Build a KKString from a Swift String literal (used for default enum-like values).
private func kk_kproperty_stub_make_string(_ s: String) -> Int {
    let utf8 = Array(s.utf8)
    guard !utf8.isEmpty else { return runtimeNullSentinelInt }
    return utf8.withUnsafeBufferPointer { buffer in
        Int(bitPattern: kk_string_from_utf8(buffer.baseAddress!, Int32(buffer.count)))
    }
}
