import Foundation

private let runtimeNotNullUninitializedPayload =
    "IllegalStateException: Property delegate must be assigned before being accessed."

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
    arity: Int,
    kind: RuntimeCallableRefKind,
    isSuspend: Bool = false
) -> Int {
    runtimeStorage.withDelegateLock { state in
        state.callableRefMetadataByValue[callable] = RuntimeCallableRefMetadata(
            nameRaw: name,
            arity: arity,
            kind: kind,
            isSuspend: isSuspend
        )
    }
    return callable
}

@_cdecl("kk_callable_ref_tag_kfunction")
public func kk_callable_ref_tag_kfunction(_ callable: Int, _ name: Int, _ arity: Int, _ isSuspend: Int) -> Int {
    runtimeTagCallableRef(callable, name: name, arity: arity, kind: .function, isSuspend: isSuspend != 0)
}

@_cdecl("kk_callable_ref_tag_kproperty")
public func kk_callable_ref_tag_kproperty(_ callable: Int, _ name: Int, _ arity: Int) -> Int {
    runtimeTagCallableRef(callable, name: name, arity: arity, kind: .property, isSuspend: false)
}

@_cdecl("kk_callable_ref_name")
public func kk_callable_ref_name(_ tagged: Int) -> Int {
    runtimeStorage.withDelegateLock { state in
        state.callableRefMetadataByValue[tagged]?.nameRaw ?? runtimeNullSentinelInt
    }
}

// STDLIB-REFLECT-063: KFunction reflection helpers for callable refs.

@_cdecl("kk_callable_ref_arity")
public func kk_callable_ref_arity(_ tagged: Int) -> Int {
    runtimeStorage.withDelegateLock { state in
        state.callableRefMetadataByValue[tagged]?.arity ?? 0
    }
}

@_cdecl("kk_callable_ref_is_suspend")
public func kk_callable_ref_is_suspend(_ tagged: Int) -> Int {
    runtimeStorage.withDelegateLock { state in
        state.callableRefMetadataByValue[tagged]?.isSuspend == true ? 1 : 0
    }
}

@_cdecl("kk_callable_ref_parameters")
public func kk_callable_ref_parameters(_ tagged: Int) -> Int {
    let arity = runtimeStorage.withDelegateLock { state in
        state.callableRefMetadataByValue[tagged]?.arity ?? 0
    }
    // Return a runtime List of placeholder ints (one element per parameter).
    let placeholders = Array(repeating: 0, count: max(0, arity))
    return registerRuntimeObject(RuntimeListBox(elements: placeholders))
}


@_cdecl("__kk_kproperty_stub_create")
public func kk_kproperty_stub_create(_ nameStr: Int, _ returnTypeStr: Int) -> Int {
    let stub = RuntimeKPropertyStub(name: nameStr, returnType: returnTypeStr)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(stub).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
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
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(stub).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

@_cdecl("__kk_kproperty_stub_name")
public func kk_kproperty_stub_name(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle),
          runtimeStorage.withGCLock({ state in state.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let stub = tryCast(ptr, to: RuntimeKPropertyStub.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid KProperty handle in kk_kproperty_stub_name")
    }
    return stub.name
}

@_cdecl("__kk_kproperty_stub_return_type")
public func kk_kproperty_stub_return_type(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle),
          runtimeStorage.withGCLock({ state in state.objectPointers.contains(UInt(bitPattern: ptr)) }),
          let stub = tryCast(ptr, to: RuntimeKPropertyStub.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid KProperty handle in kk_kproperty_stub_return_type")
    }
    return stub.returnType
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

// MARK: - Lazy Delegate (P5-80)

@_cdecl("kk_lazy_create")
public func kk_lazy_create(_ initFnPtr: Int, _ mode: Int) -> Int {
    let safetyMode = LazyThreadSafetyMode(rawValue: mode) ?? .synchronized
    let box = RuntimeLazyBox(initializerFnPtr: initFnPtr, mode: safetyMode)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

@_cdecl("kk_lazy_of")
public func kk_lazy_of(_ value: Int) -> Int {
    registerRuntimeObject(RuntimeLazyBox(initializedValue: value))
}

@_cdecl("kk_lazy_get_value")
public func kk_lazy_get_value(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    let isObj = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObj, let box = tryCast(ptr, to: RuntimeLazyBox.self) else {
        return 0
    }
    return box.getValue()
}

@_cdecl("kk_lazy_is_initialized")
public func kk_lazy_is_initialized(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    let isObj = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObj, let box = tryCast(ptr, to: RuntimeLazyBox.self) else {
        return 0
    }
    return box.isInitialized ? 1 : 0
}

// MARK: - Observable Delegate (P5-80)

@_cdecl("kk_observable_create")
public func kk_observable_create(_ initialValue: Int, _ callbackFnPtr: Int) -> Int {
    let box = RuntimeObservableBox(initialValue: initialValue, callbackFnPtr: callbackFnPtr)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

@_cdecl("kk_observable_get_value")
public func kk_observable_get_value(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    let isObj = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObj, let box = tryCast(ptr, to: RuntimeObservableBox.self) else {
        return 0
    }
    return box.currentValue
}

/// Invokes the callback **after** the value is changed (matching `kotlinc` semantics).
@_cdecl("kk_observable_set_value")
public func kk_observable_set_value(_ handle: Int, _ newValue: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    let isObj = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObj, let box = tryCast(ptr, to: RuntimeObservableBox.self) else {
        return 0
    }
    let oldValue = box.currentValue
    box.currentValue = newValue
    // Invoke callback: (property, oldValue, newValue) -> void
    // property arg is 0 (KProperty stub) to match Kotlin's 3-param lambda signature.
    if box.callbackFnPtr != 0 {
        let callback = unsafeBitCast(box.callbackFnPtr, to: KKDelegateObserverEntryPoint.self)
        var thrown = 0
        _ = callback(0, oldValue, newValue, &thrown)
        if thrown != 0 {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: observable callback threw")
        }
    }
    return newValue
}

// MARK: - Vetoable Delegate (P5-80)

@_cdecl("kk_vetoable_create")
public func kk_vetoable_create(_ initialValue: Int, _ callbackFnPtr: Int) -> Int {
    let box = RuntimeVetoableBox(initialValue: initialValue, callbackFnPtr: callbackFnPtr)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

@_cdecl("kk_vetoable_get_value")
public func kk_vetoable_get_value(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    let isObj = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObj, let box = tryCast(ptr, to: RuntimeVetoableBox.self) else {
        return 0
    }
    return box.currentValue
}

/// Invokes the callback **before** the value is changed; non-zero -> accept, zero -> veto.
@_cdecl("kk_vetoable_set_value")
public func kk_vetoable_set_value(_ handle: Int, _ newValue: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return 0
    }
    let isObj = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObj, let box = tryCast(ptr, to: RuntimeVetoableBox.self) else {
        return 0
    }
    let oldValue = box.currentValue
    // Invoke callback: (property, oldValue, newValue) -> intptr_t (boolean)
    // property arg is 0 (KProperty stub) to match Kotlin's 3-param lambda signature.
    if box.callbackFnPtr != 0 {
        let callback = unsafeBitCast(box.callbackFnPtr, to: KKDelegateObserverEntryPoint.self)
        var thrown = 0
        let accepted = callback(0, oldValue, newValue, &thrown)
        if thrown != 0 {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: vetoable callback threw")
        }
        if accepted != 0 {
            box.currentValue = newValue
        }
    } else {
        box.currentValue = newValue
    }
    return box.currentValue
}

// MARK: - NotNull Delegate (STDLIB-340)

@_cdecl("kk_notNull_create")
public func kk_notNull_create() -> Int {
    let box = RuntimeNotNullBox()
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

/// STDLIB-PROP-ABI-001: reads-before-assignment terminates with an IllegalStateException message.
/// The compiler currently lowers notNull delegate gets as non-throwing calls (one argument),
/// so we use fatalError to ensure the process exits with a non-zero status and a
/// helpful diagnostic on stderr.
@_cdecl("kk_notNull_get_value")
public func kk_notNull_get_value(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        runtimeStructuredPanic(runtimeNotNullUninitializedPayload)
    }
    let isObj = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObj, let box = tryCast(ptr, to: RuntimeNotNullBox.self) else {
        runtimeStructuredPanic(runtimeNotNullUninitializedPayload)
    }
    guard let value = box.currentValue else {
        runtimeStructuredPanic(runtimeNotNullUninitializedPayload)
    }
    return value
}

@_cdecl("kk_notNull_set_value")
public func kk_notNull_set_value(_ handle: Int, _ newValue: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_notNull_set_value called with null handle")
    }
    let isObj = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObj, let box = tryCast(ptr, to: RuntimeNotNullBox.self) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_notNull_set_value called with invalid handle")
    }
    box.currentValue = newValue
    return newValue
}
