import Foundation

/// `objectPointers` also contains borrowed singleton and flow handles for
/// historical ABI reasons. Those handles have their own lifecycle and must not
/// be passed to `Unmanaged.release()` here.
private func runtimeTakeObjectForRelease(_ rawValue: Int) -> UnsafeMutableRawPointer? {
    guard rawValue != 0,
          rawValue != runtimeNullSentinelInt,
          let pointer = UnsafeMutableRawPointer(bitPattern: rawValue)
    else {
        return nil
    }

    let removed = runtimeStorage.withGCLock { state -> Bool in
        let key = UInt(bitPattern: pointer)
        guard state.objectPointers.contains(key),
              !state.borrowedObjectPointers.contains(key),
              state.unitBoxPointer != key
        else {
            return false
        }

        // A pinned or StableRef target still has an external root. Refusing
        // the explicit release keeps those root contracts intact; the owner
        // can retry after unpin/dispose has completed.
        guard state.pinnedObjectCounts[key] == nil, state.stableRefCounts[key] == nil else {
            return false
        }
        if state.identityPrimitiveBoxHandles.remove(key) != nil {
            state.identityPrimitiveBoxCache = state.identityPrimitiveBoxCache.filter { $0.value != rawValue }
            state.enumIdentityBoxCache = state.enumIdentityBoxCache.filter { $0.value != rawValue }
        }
        state.retainedAtomicReferenceHandles.remove(key)
        state.retainedObjectHeapFields.removeValue(forKey: key)
        state.tracedObjectReferences.removeValue(forKey: key)
        state.tracedResultGenerations.removeValue(forKey: key)
        return state.objectPointers.remove(key) != nil
    }
    guard removed else {
        return nil
    }

    return pointer
}

/// The registry entry is removed before ARC is released, so concurrent handle
/// resolution cannot observe a freed object. The operation is idempotent: a
/// stale or already-released handle returns `false` and performs no release.
/// Managed `kk_alloc` objects are intentionally outside this path; they belong
/// to `heapObjects` and are reclaimed by mark-and-sweep.
@discardableResult
func runtimeReleaseObject(_ rawValue: Int) -> Bool {
    guard let pointer = runtimeTakeObjectForRelease(rawValue) else {
        return false
    }

    let key = UInt(bitPattern: pointer)
    let foreignResources = runtimeForeignResourcesTakeForReleasedOwner(rawValue)
    defer { withExtendedLifetime(foreignResources) {} }
    removeRuntimeObjectMetadata(forObjectKey: key)
    runtimeForgetFrozenObject(rawValue)
    // Primitive box handles are tagged (kk_box_* / registerTaggedPrimitiveBox):
    // the registry key is the tagged bits, but ARC release needs the base object.
    let basePointer = runtimePrimitiveBoxBasePointer(from: rawValue) ?? pointer
    Unmanaged<AnyObject>.fromOpaque(basePointer).release()
    return true
}

/// Returns `1` when the retained allocation was released and `0` when the
/// handle was null, stale, borrowed, pinned, or already released.
public func kk_object_release(_ objectRaw: Int) -> Int {
    runtimeReleaseObject(objectRaw) ? 1 : 0
}
