// KUU-1728: bridge retained C11 reference cells to the existing managed heap.
// This is not box mark/sweep: objectPointers retains its existing owner model.
// Call only with the collector lock held. Reference-cell mutations use that
// same lock, and matching uses the already-locked registry (no recursive lock).
func collectRetainedAtomicPayloadRootsLocked(
    state: GCState,
    into worklist: inout [UnsafeMutableRawPointer]
) {
    func appendManagedPayload(_ raw: Int) {
        guard state.heapObjects[UInt(bitPattern: raw)] != nil,
              let pointer = UnsafeMutableRawPointer(bitPattern: raw)
        else {
            return
        }
        worklist.append(pointer)
    }

    for handle in state.retainedAtomicReferenceHandles {
        guard state.objectPointers.contains(handle),
              let pointer = UnsafeMutableRawPointer(bitPattern: handle)
        else {
            continue
        }
        let object = Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
        if let reference = object as? AtomicRefBox {
            appendManagedPayload(reference.load())
        } else if let array = object as? AtomicRefArrayBox {
            for index in 0 ..< array.size() {
                appendManagedPayload(array.load(at: index))
            }
        }
    }
}
