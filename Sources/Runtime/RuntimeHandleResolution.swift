
/// Resolve a raw integer handle to a registered runtime object of the given type.
/// Returns nil if the handle is zero/null, not a registered object pointer, or
/// points to an object of a different type.
///
/// This is the canonical shape for `runtime*Box(from:)` lookups across the
/// Runtime module — most box resolvers can delegate to this helper directly.
/// Exceptions (e.g. `runtimeThreadLocalBox` querying a different storage set,
/// or `runtimePlainArrayBox` requiring an exact-type match) inline a custom
/// version.
func resolveRuntimeHandle<T: AnyObject>(_ rawValue: Int, as _: T.Type) -> T? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: T.self)
}

/// Resolve a raw integer handle to the registered runtime object it points to,
/// taking the GC lock once for the `objectPointers` membership check.
///
/// A dispatcher testing one handle against several box types can cast the
/// result with `as?`/`is` repeatedly without re-locking — equivalent to one
/// `resolveRuntimeHandle` per type but with a single lock acquisition.
func resolveRuntimeObjectHandle(_ rawValue: Int) -> AnyObject? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    let normalized = runtimePrimitiveBoxBasePointer(from: rawValue) ?? ptr
    return Unmanaged<AnyObject>.fromOpaque(normalized).takeUnretainedValue()
}
