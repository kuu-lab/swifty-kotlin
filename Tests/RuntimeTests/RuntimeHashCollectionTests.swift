@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeHashCollectionTests {
    @Test
    func runtimeSetIndexUsesKotlinEqualityAndPreservesInsertionOrder() {
        let first = registerRuntimeObject(RuntimeStringBox("same"))
        let equivalent = registerRuntimeObject(RuntimeStringBox("same"))
        let set = RuntimeSetBox(elements: [first])

        #expect(set.contains(rawValue: equivalent))
        #expect(!set.insert(rawValue: equivalent))
        #expect(set.insert(rawValue: 7))
        #expect(set.elements == [first, 7])

        #expect(set.remove(rawValue: equivalent))
        #expect(set.elements == [7])
    }

    @Test
    func runtimeMapIndexUsesKotlinEqualityAndPreservesInsertionOrder() {
        let first = registerRuntimeObject(RuntimeStringBox("same"))
        let equivalent = registerRuntimeObject(RuntimeStringBox("same"))
        let map = RuntimeMapBox(keys: [first], values: [10])

        #expect(map.index(ofRawKey: equivalent) == 0)
        #expect(map.put(key: equivalent, value: 20) == 10)
        #expect(map.keys == [first])
        #expect(map.values == [20])

        #expect(map.put(key: 7, value: 70) == nil)
        #expect(map.keys == [first, 7])
        #expect(map.values == [20, 70])
        #expect(map.remove(key: equivalent) == 20)
        #expect(map.keys == [7])
        #expect(map.values == [70])
    }

    @Test
    func runtimeMapDoesNotUseCanonicalEquivalenceForStringKeys() {
        let composed = registerRuntimeObject(RuntimeStringBox("é"))
        let decomposed = registerRuntimeObject(RuntimeStringBox("e\u{301}"))
        let map = RuntimeMapBox(keys: [composed], values: [1])

        #expect(!runtimeValuesEqual(composed, decomposed))
        #expect(map.index(ofRawKey: decomposed) == nil)
    }

    @Test
    func equalCollectionsHaveEqualRuntimeHashes() {
        let firstKey = registerRuntimeObject(RuntimeStringBox("first"))
        let secondKey = registerRuntimeObject(RuntimeStringBox("second"))
        let equivalentFirstKey = registerRuntimeObject(RuntimeStringBox("first"))
        let equivalentSecondKey = registerRuntimeObject(RuntimeStringBox("second"))

        let firstList = registerRuntimeObject(RuntimeListBox(elements: [firstKey, secondKey]))
        let secondList = registerRuntimeObject(RuntimeListBox(elements: [equivalentFirstKey, equivalentSecondKey]))
        #expect(runtimeValuesEqual(firstList, secondList))
        #expect(runtimeValueHash(firstList) == runtimeValueHash(secondList))

        let firstSet = registerRuntimeObject(RuntimeSetBox(elements: [firstKey, secondKey]))
        let secondSet = registerRuntimeObject(RuntimeSetBox(elements: [equivalentSecondKey, equivalentFirstKey]))
        #expect(runtimeValuesEqual(firstSet, secondSet))
        #expect(runtimeValueHash(firstSet) == runtimeValueHash(secondSet))

        let firstMap = registerRuntimeObject(RuntimeMapBox(keys: [firstKey, secondKey], values: [1, 2]))
        let secondMap = registerRuntimeObject(RuntimeMapBox(keys: [equivalentSecondKey, equivalentFirstKey], values: [2, 1]))
        #expect(runtimeValuesEqual(firstMap, secondMap))
        #expect(runtimeValueHash(firstMap) == runtimeValueHash(secondMap))
    }

    @Test
    func indexedCollectionsHandleLargeInputs() {
        let count = 100_000
        let set = RuntimeSetBox(elements: [])
        let map = RuntimeMapBox(keys: [], values: [])

        for value in 0 ..< count {
            _ = set.insert(rawValue: value)
            _ = map.put(key: value, value: value * 3)
        }

        #expect(set.count == count)
        #expect(map.count == count)

        var checksum = 0
        var value = 0
        while value < count {
            #expect(set.contains(rawValue: value))
            guard let index = map.index(ofRawKey: value), let mapped = map.rawValue(at: index) else {
                Issue.record("Indexed map lookup failed for \(value)")
                return
            }
            checksum += mapped
            value += 997
        }

        var expectedChecksum = 0
        value = 0
        while value < count {
            expectedChecksum += value * 3
            value += 997
        }
        #expect(checksum == expectedChecksum)
    }

    @Test
    func runtimeSetAndMapOperateLinearlyWithCollidingStrings() {
        // Generate strings with identical Kotlin 32-bit hashCode:
        // "Aa" and "BB" both have hashCode = 2112.
        // Combining 12 pairs produces 2^12 = 4096 distinct strings with identical Kotlin hashCode.
        let pairA = "Aa"
        let pairB = "BB"
        let depth = 12
        let count = 1 << depth // 4096

        var collidingStrings: [String] = []
        collidingStrings.reserveCapacity(count)
        for i in 0 ..< count {
            var s = ""
            for bit in 0 ..< depth {
                s += ((i >> bit) & 1 == 0) ? pairA : pairB
            }
            collidingStrings.append(s)
        }

        let stringHandles = collidingStrings.map { registerRuntimeObject(RuntimeStringBox($0)) }

        // 1. Verify public hashCode compatibility: all 4096 strings must produce the identical 32-bit Kotlin hashCode.
        let expectedPublicHash = kk_any_hashCode(stringHandles[0], 0)
        for handle in stringHandles {
            #expect(kk_any_hashCode(handle, 0) == expectedPublicHash)
            #expect(runtimeValueHash(handle) == expectedPublicHash)
        }

        // 2. Measure insertion into RuntimeSetBox and RuntimeMapBox.
        // If internal placement relied on the public 32-bit hash, all 4096 keys would map
        // to a single bucket, degrading to O(N^2) total string comparisons.
        // With internal placement feeding UTF-16 code units directly to Swift's randomized Hasher (KUU-812),
        // all operations complete in linear time O(N).
        let set = RuntimeSetBox(elements: [])
        let map = RuntimeMapBox(keys: [], values: [])

        let startTime = ContinuousClock.now
        for (i, handle) in stringHandles.enumerated() {
            #expect(set.insert(rawValue: handle))
            #expect(map.put(key: handle, value: i) == nil)
        }
        let elapsed = ContinuousClock.now - startTime

        #expect(set.count == count)
        #expect(map.count == count)

        // Lookup verification
        for (i, handle) in stringHandles.enumerated() {
            #expect(set.contains(rawValue: handle))
            guard let idx = map.index(ofRawKey: handle) else {
                Issue.record("Failed to find key in map for index \(i)")
                return
            }
            #expect(map.rawValue(at: idx) == i)
        }

        // 4096 inserts in O(N) takes under 0.2s on modern hardware; O(N^2) with full string checks would take multiple seconds.
        #expect(elapsed < .seconds(2))
    }

    @Test
    func runtimeElementKeyMaintainsHashAndEqualityContract() {
        func elementHash(_ value: Int) -> Int {
            var hasher = Hasher()
            RuntimeElementKey(value: value).hash(into: &hasher)
            return hasher.finalize()
        }

        // 1. Equal strings have equal internal hash
        let s1 = registerRuntimeObject(RuntimeStringBox("hello"))
        let s2 = registerRuntimeObject(RuntimeStringBox("hello"))
        #expect(RuntimeElementKey(value: s1) == RuntimeElementKey(value: s2))
        #expect(elementHash(s1) == elementHash(s2))

        // 2. Boxed vs unboxed primitives have equal internal hash when runtimeValuesEqual considers them equal
        let intBox = registerRuntimeObject(RuntimeIntBox(42))
        let rawInt = 42
        #expect(runtimeValuesEqual(intBox, rawInt))
        #expect(RuntimeElementKey(value: intBox) == RuntimeElementKey(value: rawInt))
        #expect(elementHash(intBox) == elementHash(rawInt))

        // Enum boxes cross call sites both as `RuntimeIntBox` carrying
        // `enumClassID` and as raw unboxed ordinals; runtimeValuesEqual
        // unboxes them, so a classID-dependent hash would send equal keys to
        // different buckets (regex_option_options_property).
        let enumBox = registerRuntimeObject(RuntimeIntBox(3, enumEntryName: "UNIX_LINES", enumClassID: 0x5EED))
        #expect(runtimeValuesEqual(enumBox, 3))
        #expect(RuntimeElementKey(value: enumBox) == RuntimeElementKey(value: 3))
        #expect(elementHash(enumBox) == elementHash(3))

        let doubleBox = registerRuntimeObject(RuntimeDoubleBox(3.14))
        let rawDouble = Int(bitPattern: UInt(truncatingIfNeeded: Double(3.14).bitPattern))
        #expect(runtimeValuesEqual(doubleBox, rawDouble))
        #expect(RuntimeElementKey(value: doubleBox) == RuntimeElementKey(value: rawDouble))
        #expect(elementHash(doubleBox) == elementHash(rawDouble))

        // 3. Sets with different insertion orders have equal internal hash
        let set1 = registerRuntimeObject(RuntimeSetBox(elements: [s1, intBox]))
        let set2 = registerRuntimeObject(RuntimeSetBox(elements: [intBox, s2]))
        #expect(runtimeValuesEqual(set1, set2))
        #expect(RuntimeElementKey(value: set1) == RuntimeElementKey(value: set2))
        #expect(elementHash(set1) == elementHash(set2))

        // 4. Maps with different entry insertion orders have equal internal hash
        let map1 = registerRuntimeObject(RuntimeMapBox(keys: [s1, intBox], values: [1, 2]))
        let map2 = registerRuntimeObject(RuntimeMapBox(keys: [intBox, s2], values: [2, 1]))
        #expect(runtimeValuesEqual(map1, map2))
        #expect(RuntimeElementKey(value: map1) == RuntimeElementKey(value: map2))
        #expect(elementHash(map1) == elementHash(map2))

        // 5. Lists with equal elements have equal internal hash
        let list1 = registerRuntimeObject(RuntimeListBox(elements: [s1, intBox]))
        let list2 = registerRuntimeObject(RuntimeListBox(elements: [s2, intBox]))
        #expect(runtimeValuesEqual(list1, list2))
        #expect(RuntimeElementKey(value: list1) == RuntimeElementKey(value: list2))
        #expect(elementHash(list1) == elementHash(list2))

        // 6. Tagged Pairs have equal internal hash
        let pair1 = registerRuntimeObject(RuntimePairBox(first: s1, second: intBox))
        runtimeRegisterObjectType(rawValue: pair1, classID: runtimePairNominalTypeID)
        let pair2 = registerRuntimeObject(RuntimePairBox(first: s2, second: intBox))
        runtimeRegisterObjectType(rawValue: pair2, classID: runtimePairNominalTypeID)
        #expect(runtimeValuesEqual(pair1, pair2))
        #expect(RuntimeElementKey(value: pair1) == RuntimeElementKey(value: pair2))
        #expect(elementHash(pair1) == elementHash(pair2))
    }
}
