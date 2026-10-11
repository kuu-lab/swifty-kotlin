import Foundation

/// ARC-owned SDK resource attached to a managed Kotlin wrapper. The lease is
/// an edge from its Kotlin owner, not a global Kotlin root. Destroy retired
/// leases after releasing the GC lock: SDK deinits can dispose pinned callbacks.
final class RuntimeForeignResourceLease: @unchecked Sendable {
    let value: AnyObject
    var owner: UInt?
    var dependentRoots: [UInt]
    var attachmentRoots: [UInt] = []
    var attachments: [AnyObject] = []
    init(value: AnyObject, dependentRoots: [UInt] = []) {
        self.value = value
        self.dependentRoots = dependentRoots
    }
}

func runtimeForeignResourceCreate(_ value: AnyObject, roots: [UInt] = []) -> Int {
    runtimeStorage.withGCLock { state in
        let token = state.nextForeignResourceToken
        precondition(token < Int.max)
        state.nextForeignResourceToken += 1
        state.foreignResources[token] = RuntimeForeignResourceLease(value: value, dependentRoots: roots)
        return token
    }
}

func runtimeForeignResource<T: AnyObject>(_ token: Int, as type: T.Type) -> T? {
    runtimeStorage.withGCLock { $0.foreignResources[token]?.value as? T }
}

func runtimeForeignResourceAttach(_ token: Int, owner: Int) -> Bool {
    runtimeStorage.withGCLock { state in
        let key = UInt(bitPattern: owner)
        guard state.heapObjects[key] != nil || state.objectPointers.contains(key), let lease = state.foreignResources[token],
              lease.owner == nil || lease.owner == key else { return false }
        lease.owner = key
        return true
    }
}

func runtimeForeignResourceForOwner<T: AnyObject>(_ owner: Int, as type: T.Type) -> T? {
    runtimeStorage.withGCLock { state in
        state.foreignResources.values.first { $0.owner == UInt(bitPattern: owner) }?.value as? T
    }
}

/// Used by an SDK block while queued/executing. The native block owns this
/// lease and therefore bounds the pin. No permanent StableRef or Cleaner root.
final class RuntimeForeignCallbackPin: @unchecked Sendable {
    private let root: Int
    init(root: Int) {
        self.root = root
        runtimeStorage.withGCLock { $0.pinnedObjectCounts[UInt(bitPattern: root), default: 0] += 1 }
    }
    deinit {
        runtimeStorage.withGCLock { state in
            let key = UInt(bitPattern: root)
            if let count = state.pinnedObjectCounts[key], count > 1 {
                state.pinnedObjectCounts[key] = count - 1
            } else { state.pinnedObjectCounts.removeValue(forKey: key) }
        }
    }
}

/// Retained RuntimeObjectBox instances have an explicit release lifecycle in
/// the current runtime. Tie SDK resources to that lifecycle too; do not pretend
/// those classes are kk_alloc-managed or independently auto-finalized.
func runtimeForeignResourcesTakeForReleasedOwner(_ owner: Int) -> [RuntimeForeignResourceLease] {
    runtimeStorage.withGCLock { state in
        let key = UInt(bitPattern: owner)
        let tokens = state.foreignResources.compactMap { $0.value.owner == key ? $0.key : nil }
        return tokens.compactMap { state.foreignResources.removeValue(forKey: $0) }
    }
}

/// Creation-to-constructor rollback. Release native resources outside the GC lock.
/// A token already attached to a live wrapper is deliberately retained.
func runtimeForeignResourceDiscardUnattached(_ token: Int) {
    let retired = runtimeStorage.withGCLock { state -> RuntimeForeignResourceLease? in
        guard state.foreignResources[token]?.owner == nil else { return nil }
        return state.foreignResources.removeValue(forKey: token)
    }
    withExtendedLifetime(retired) {}
}
