import RuntimeCAtomics

/// Lowest and highest key ever inserted into any `RuntimePointerSet`, kept in
/// atomic words so `runtimeIsRegisteredObjectPointer` can reject the raw
/// payloads that statically-typed unbox calls mostly see (`kk_unbox_int` on a
/// loop counter) without taking the GC lock. The bounds only ever widen —
/// removal and runtime resets leave them — so a stale read can only send a
/// value down the locked membership check, never skip a registered handle.
nonisolated(unsafe) private let runtimePointerSetLowerBound: UnsafeMutablePointer<Int> = {
    let cell = UnsafeMutablePointer<Int>.allocate(capacity: 1)
    cell.initialize(to: Int(bitPattern: UInt.max))
    return cell
}()

nonisolated(unsafe) private let runtimePointerSetUpperBound: UnsafeMutablePointer<Int> = {
    let cell = UnsafeMutablePointer<Int>.allocate(capacity: 1)
    cell.initialize(to: 0)
    return cell
}()

@inline(__always)
func runtimePointerSetMayContain(_ key: UInt) -> Bool {
    key >= UInt(bitPattern: kkrt_atomic_word_load(runtimePointerSetLowerBound))
        && key <= UInt(bitPattern: kkrt_atomic_word_load(runtimePointerSetUpperBound))
}

/// Membership set for runtime object handles, used for `GCState.objectPointers`.
///
/// Every box/unbox, string extraction and collection access consults the
/// handle registry while holding the global GC lock, so `Set<UInt>.contains`
/// (SipHash via `Hasher._hash(seed:_:)` plus `__RawDictionaryStorage.find`) was
/// the single largest cost in the runtime hot path profile (KUU-3018).
///
/// Keys here are heap addresses or tagged handles, never attacker-controlled,
/// so a multiplicative hash with linear probing is sufficient and avoids the
/// randomly-seeded SipHash. The table keeps its load factor at or below one
/// half so successful and failed probes both stay short.
///
/// `0` and `1` are reserved as the empty and tombstone slot markers; real
/// handles can never take those values (null and an unaligned address), but a
/// caller passing them is still answered correctly through dedicated flags.
struct RuntimePointerSet {
    private static let emptySlot: UInt = 0
    private static let tombstoneSlot: UInt = 1
    private static let minimumCapacity = 64

    private var slots: [UInt]
    private var mask: Int
    private var shift: UInt
    private var liveCount = 0
    private var tombstoneCount = 0
    private var containsZero = false
    private var containsOne = false

    init() {
        slots = [UInt](repeating: Self.emptySlot, count: Self.minimumCapacity)
        mask = Self.minimumCapacity - 1
        shift = UInt(UInt.bitWidth - Self.minimumCapacity.trailingZeroBitCount)
    }

    var count: Int {
        liveCount + (containsZero ? 1 : 0) + (containsOne ? 1 : 0)
    }

    @inline(__always)
    private func home(of key: UInt) -> Int {
        Int(truncatingIfNeeded: (key &* 0x9E37_79B9_7F4A_7C15) >> shift)
    }

    @inline(__always)
    func contains(_ key: UInt) -> Bool {
        if key <= Self.tombstoneSlot {
            return key == Self.emptySlot ? containsZero : containsOne
        }
        var index = home(of: key)
        while true {
            let slot = slots[index]
            if slot == key { return true }
            if slot == Self.emptySlot { return false }
            index = (index &+ 1) & mask
        }
    }

    /// Returns `true` when `key` was not already a member.
    @discardableResult
    mutating func insert(_ key: UInt) -> Bool {
        if key <= Self.tombstoneSlot {
            if key == Self.emptySlot {
                defer { containsZero = true }
                return !containsZero
            }
            defer { containsOne = true }
            return !containsOne
        }
        if (liveCount + tombstoneCount + 1) * 2 > slots.count {
            rehash(growing: liveCount * 2 + 2 > slots.count / 2)
        }
        var index = home(of: key)
        var firstTombstone = -1
        while true {
            let slot = slots[index]
            if slot == key { return false }
            if slot == Self.emptySlot { break }
            if slot == Self.tombstoneSlot, firstTombstone < 0 { firstTombstone = index }
            index = (index &+ 1) & mask
        }
        if firstTombstone >= 0 {
            index = firstTombstone
            tombstoneCount -= 1
        }
        slots[index] = key
        liveCount += 1
        // Inserts are serialized by the GC lock, so load-then-store cannot
        // lose a concurrent widening.
        if key < UInt(bitPattern: kkrt_atomic_word_load(runtimePointerSetLowerBound)) {
            kkrt_atomic_word_store(runtimePointerSetLowerBound, Int(bitPattern: key))
        }
        if key > UInt(bitPattern: kkrt_atomic_word_load(runtimePointerSetUpperBound)) {
            kkrt_atomic_word_store(runtimePointerSetUpperBound, Int(bitPattern: key))
        }
        return true
    }

    /// Returns the removed key, or `nil` when it was not a member.
    @discardableResult
    mutating func remove(_ key: UInt) -> UInt? {
        if key <= Self.tombstoneSlot {
            if key == Self.emptySlot {
                guard containsZero else { return nil }
                containsZero = false
            } else {
                guard containsOne else { return nil }
                containsOne = false
            }
            return key
        }
        var index = home(of: key)
        while true {
            let slot = slots[index]
            if slot == key {
                slots[index] = Self.tombstoneSlot
                liveCount -= 1
                tombstoneCount += 1
                return key
            }
            if slot == Self.emptySlot { return nil }
            index = (index &+ 1) & mask
        }
    }

    private mutating func rehash(growing: Bool) {
        let newCapacity = growing ? slots.count * 2 : slots.count
        var newSlots = [UInt](repeating: Self.emptySlot, count: newCapacity)
        let newMask = newCapacity - 1
        let newShift = UInt(UInt.bitWidth - newCapacity.trailingZeroBitCount)
        for key in slots where key > Self.tombstoneSlot {
            var index = Int(truncatingIfNeeded: (key &* 0x9E37_79B9_7F4A_7C15) >> newShift)
            while newSlots[index] != Self.emptySlot {
                index = (index &+ 1) & newMask
            }
            newSlots[index] = key
        }
        slots = newSlots
        mask = newMask
        shift = newShift
        tombstoneCount = 0
    }
}
