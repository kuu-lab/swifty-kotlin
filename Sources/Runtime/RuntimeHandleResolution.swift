
func resolveRuntimeHandle<T: AnyObject>(_ rawValue: Int, as _: T.Type) -> T? {
    resolveRuntimeObjectHandle(rawValue) as? T
}

/// Explicit release removes membership under the same lock, so the retain must
/// happen before unlocking. Casting and dropping the returned reference happen
/// outside the lock: object deinitializers may re-enter the runtime.
func resolveRuntimeObjectHandle(_ rawValue: Int) -> AnyObject? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    return runtimeStorage.withGCLock { state in
        guard state.objectPointers.contains(UInt(bitPattern: ptr)) else {
            return nil
        }
        let normalized = runtimePrimitiveBoxBasePointer(from: rawValue) ?? ptr
        return Unmanaged<AnyObject>.fromOpaque(normalized).retain().takeRetainedValue()
    }
}
