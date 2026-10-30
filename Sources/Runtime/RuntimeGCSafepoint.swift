import Foundation

/// Coordinates threads that have explicitly entered the managed mutator
/// protocol. A mutator must publish its roots before polling and must not
/// access managed memory while parked. Unregistered threads are not stopped.
final class RuntimeGCSafepointCoordinator: @unchecked Sendable {
    private struct Mutator {
        var depth: Int
        var parked: Bool
        var suspendedAt: [Int] = []
    }

    private let condition = NSCondition()
    private var mutators: [ObjectIdentifier: Mutator] = [:]
    private var collector: ObjectIdentifier?
    private var collectionDepth = 0

    func enter() {
        let id = ObjectIdentifier(Thread.current)
        condition.lock()
        defer { condition.unlock() }
        waitForOtherCollector(id)
        if mutators[id] != nil {
            mutators[id]?.depth += 1
            mutators[id]?.parked = false
        } else {
            mutators[id] = Mutator(depth: 1, parked: false)
        }
    }

    func leave() {
        let id = ObjectIdentifier(Thread.current)
        condition.lock()
        defer { condition.unlock() }
        guard let mutator = mutators[id], mutator.depth > 0 else {
            preconditionFailure("GC mutator leave requires a matching enter")
        }
        guard mutator.suspendedAt.last != mutator.depth else {
            preconditionFailure("GC mutator leave requires its blocking region to end")
        }
        if mutator.depth == 1 {
            mutators.removeValue(forKey: id)
            condition.broadcast()
        } else {
            mutators[id]?.depth -= 1
            if mutators[id]?.suspendedAt.last == mutators[id]?.depth {
                // Return from a managed callback into an outer blocking call.
                mutators[id]?.parked = true
                condition.broadcast()
            } else {
                waitForOtherCollector(id)
            }
        }
    }

    func poll() {
        let id = ObjectIdentifier(Thread.current)
        condition.lock()
        defer { condition.unlock() }
        guard let mutator = mutators[id], !mutator.parked else {
            preconditionFailure("GC safepoint requires an active mutator")
        }
        waitForOtherCollector(id)
    }

    func beginBlocking() {
        guard beginBlockingIfEnrolled() else {
            preconditionFailure("GC blocking region requires an active mutator")
        }
    }

    @discardableResult
    func beginBlockingIfEnrolled() -> Bool {
        let id = ObjectIdentifier(Thread.current)
        condition.lock()
        defer { condition.unlock() }
        guard let mutator = mutators[id] else { return false }
        guard !mutator.parked else {
            preconditionFailure("GC blocking region requires an active mutator")
        }
        mutators[id]?.suspendedAt.append(mutator.depth)
        mutators[id]?.parked = true
        condition.broadcast()
        return true
    }

    func endBlocking() {
        let id = ObjectIdentifier(Thread.current)
        condition.lock()
        defer { condition.unlock() }
        guard let mutator = mutators[id], mutator.suspendedAt.last == mutator.depth else {
            preconditionFailure("GC blocking region end requires a matching begin")
        }
        waitForOtherCollector(id)
        mutators[id]?.suspendedAt.removeLast()
    }

    var collectionRequested: Bool {
        condition.lock()
        defer { condition.unlock() }
        return collector != nil
    }

    func beginCollection() {
        let id = ObjectIdentifier(Thread.current)
        condition.lock()
        defer { condition.unlock() }
        if collector == id {
            collectionDepth += 1
            return
        }
        let wasBlocking = mutators[id].map { $0.suspendedAt.last == $0.depth } ?? false
        // A registered collector waiting for another collector must itself be
        // considered parked, otherwise both collectors can wait forever.
        waitForOtherCollector(id)
        if wasBlocking {
            mutators[id]?.parked = true
        }
        collector = id
        collectionDepth = 1
        condition.broadcast()
        while mutators.contains(where: { $0.key != id && !$0.value.parked }) {
            condition.wait()
        }
    }

    func endCollection() {
        let id = ObjectIdentifier(Thread.current)
        condition.lock()
        defer { condition.unlock() }
        guard collector == id, collectionDepth > 0 else {
            preconditionFailure("GC collection end requires the collector thread")
        }
        collectionDepth -= 1
        if collectionDepth == 0 {
            collector = nil
            condition.broadcast()
        }
    }

    // The condition lock is held by every caller of this method.
    private func waitForOtherCollector(_ id: ObjectIdentifier) {
        while let owner = collector, owner != id {
            if mutators[id] != nil {
                mutators[id]?.parked = true
                condition.broadcast()
            }
            condition.wait()
        }
        if mutators[id] != nil {
            mutators[id]?.parked = false
        }
    }
}

let runtimeGCSafepoints = RuntimeGCSafepointCoordinator()

// These hooks are not yet emitted by the compiler. The collector coordinates
// only enrolled threads; it is not safe to sweep arbitrary runtime objects yet.
// DEAD-CDECL-TEST-HOOK: GC-FRAME - Runtime tests exercise mutator registration.
@_cdecl("__kk_gc_mutator_enter")
public func __kk_gc_mutator_enter() {
    runtimeGCSafepoints.enter()
}

// DEAD-CDECL-TEST-HOOK: GC-FRAME - Runtime tests exercise mutator registration.
@_cdecl("__kk_gc_mutator_leave")
public func __kk_gc_mutator_leave() {
    runtimeGCSafepoints.leave()
}

// DEAD-CDECL-TEST-HOOK: GC-FRAME - Runtime tests exercise safepoint polling.
@_cdecl("__kk_gc_safepoint")
public func __kk_gc_safepoint() {
    runtimeGCSafepoints.poll()
}

// The caller must publish all roots and release locks needed by the collector
// before blocking, and protect native-produced values before resuming.
// DEAD-CDECL-TEST-HOOK: GC-FRAME - Runtime tests exercise blocking transitions.
@_cdecl("__kk_gc_mutator_blocking_begin")
public func __kk_gc_mutator_blocking_begin() {
    runtimeGCSafepoints.beginBlocking()
}

// DEAD-CDECL-TEST-HOOK: GC-FRAME - Runtime tests exercise blocking transitions.
@_cdecl("__kk_gc_mutator_blocking_end")
public func __kk_gc_mutator_blocking_end() {
    runtimeGCSafepoints.endBlocking()
}
