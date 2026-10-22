#if canImport(Testing)
@testable import Runtime
import Testing

/// KUU-3018: `RuntimePointerSet` replaces `Set<UInt>` for `GCState.objectPointers`.
/// These tests compare it against `Set<UInt>` as an oracle through growth,
/// tombstone reuse and the reserved slot-marker keys (0 and 1).
@Suite
struct RuntimePointerSetTests {
    @Test
    func insertContainsRemoveMatchSetSemantics() {
        var set = RuntimePointerSet()
        #expect(!set.contains(0x1000))
        let r1 = set.insert(0x1000)
        #expect(r1)
        let r2 = set.insert(0x1000)
        #expect(!r2)
        #expect(set.contains(0x1000))
        #expect(set.count == 1)
        let r3 = set.remove(0x1000)
        #expect(r3 == 0x1000)
        let r4 = set.remove(0x1000)
        #expect(r4 == nil)
        #expect(!set.contains(0x1000))
        #expect(set.count == 0)
    }

    @Test
    func reservedMarkerKeysAreRealMembers() {
        var set = RuntimePointerSet()
        #expect(!set.contains(0))
        #expect(!set.contains(1))
        let r5 = set.insert(0)
        #expect(r5)
        let r6 = set.insert(1)
        #expect(r6)
        let r7 = set.insert(0)
        #expect(!r7)
        #expect(set.contains(0))
        #expect(set.contains(1))
        #expect(set.count == 2)
        let r8 = set.remove(0)
        #expect(r8 == 0)
        #expect(!set.contains(0))
        #expect(set.contains(1))
        let r9 = set.remove(0)
        #expect(r9 == nil)
    }

    @Test
    func growthAndChurnAgreeWithSetOracle() {
        var set = RuntimePointerSet()
        var oracle = Set<UInt>()
        var state: UInt64 = 0x1234_5678_9ABC_DEF0
        func next() -> UInt {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            // Aligned, pointer-like keys including a few colliding low-range values.
            return UInt(truncatingIfNeeded: (state >> 20) & 0xFFFF) << 4
        }
        for step in 0 ..< 60000 {
            let key = next()
            switch step % 3 {
            case 0, 1:
                let inserted = set.insert(key)
                #expect(inserted == oracle.insert(key).inserted)
            default:
                let removed = set.remove(key)
                #expect((removed != nil) == (oracle.remove(key) != nil))
            }
            if step % 997 == 0 {
                for probe in 0 ..< 64 {
                    let candidate = UInt(probe) << 4
                    #expect(set.contains(candidate) == oracle.contains(candidate))
                }
            }
        }
        #expect(set.count == oracle.count)
        for key in oracle {
            #expect(set.contains(key))
        }
    }

    @Test
    func tombstoneChurnDoesNotDegradeLookups() {
        var set = RuntimePointerSet()
        for round in 0 ..< 2000 {
            let key = UInt(0x10000 + round * 16)
            set.insert(key)
            #expect(set.contains(key))
            set.remove(key)
        }
        #expect(set.count == 0)
        #expect(!set.contains(0xDEAD_BEE0))
    }
}
#endif
