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
}
