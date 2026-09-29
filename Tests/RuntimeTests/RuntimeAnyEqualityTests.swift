#if canImport(Testing)
@testable import Runtime
import Testing

private let runtimeAnyEqualityOverride: @convention(c) (
    Int,
    Int,
    UnsafeMutablePointer<Int>?
) -> Int = { lhs, rhs, outThrown in
    outThrown?.pointee = 0
    return kk_array_get(lhs, 0, nil) == kk_array_get(rhs, 0, nil) ? 1 : 0
}

private let runtimeAnyHashCodeOverride: @convention(c) (
    Int,
    UnsafeMutablePointer<Int>?
) -> Int = { receiver, outThrown in
    outThrown?.pointee = 0
    return kk_array_get(receiver, 0, nil)
}

@Suite
struct RuntimeAnyEqualityTests {
    private func boolValue(_ raw: Int) -> Bool {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: raw),
              let box = tryCast(pointer, to: RuntimeBoolBox.self)
        else {
            return false
        }
        return box.value
    }

    @Test
    func testUnregisteredRuntimeObjectUsesReferenceIdentity() {
        let classID = 0x51_11
        let first = kk_object_new(1, classID)
        let second = kk_object_new(1, classID)
        _ = kk_array_set(first, 0, 7, nil)
        _ = kk_array_set(second, 0, 7, nil)

        #expect(boolValue(kk_any_equals(first, 0, first, 0)))
        #expect(!boolValue(kk_any_equals(first, 0, second, 0)))
    }

    @Test
    func testRegisteredDataClassKeepsStructuralEquality() {
        let classID = 0x51_12
        _ = kk_runtime_register_data_class(classID)
        let first = kk_object_new(1, classID)
        let second = kk_object_new(1, classID)
        _ = kk_array_set(first, 0, 7, nil)
        _ = kk_array_set(second, 0, 7, nil)

        #expect(boolValue(kk_any_equals(first, 0, second, 0)))

        _ = kk_array_set(second, 0, 8, nil)
        #expect(!boolValue(kk_any_equals(first, 0, second, 0)))
    }

    @Test
    func testRegisteredEqualsOverrideWinsAfterTypeErasure() {
        let classID = 0x51_13
        let first = kk_object_new(2, classID)
        let second = kk_object_new(2, classID)
        _ = kk_array_set(first, 0, 7, nil)
        _ = kk_array_set(first, 1, 1, nil)
        _ = kk_array_set(second, 0, 7, nil)
        _ = kk_array_set(second, 1, 2, nil)
        _ = kk_object_register_equals_override(
            first,
            unsafeBitCast(runtimeAnyEqualityOverride, to: Int.self)
        )

        #expect(boolValue(kk_any_equals(first, 0, second, 0)))
        #expect(kk_structural_eq(first, second) == 1)
    }

    // Tuples allocated for Kotlin's `Pair`/`Triple` carry a nominal type ID, so
    // they compare and hash by their components even when they reach the
    // runtime through `Any` (set membership, map keys) rather than the Kotlin
    // `equals` written in `Tuples.kt`.
    @Test
    func testTaggedPairAndTripleCompareAndHashStructurally() {
        let first = kk_pair_new(1, 2)
        let second = kk_pair_new(1, 2)
        let different = kk_pair_new(1, 3)

        #expect(boolValue(kk_any_equals(first, 0, second, 0)))
        #expect(!boolValue(kk_any_equals(first, 0, different, 0)))
        #expect(kk_any_hashCode(first, 0) == kk_any_hashCode(second, 0))

        let triple = kk_triple_new(1, 2, 3)
        let sameTriple = kk_triple_new(1, 2, 3)
        let otherTriple = kk_triple_new(1, 2, 4)

        #expect(boolValue(kk_any_equals(triple, 0, sameTriple, 0)))
        #expect(!boolValue(kk_any_equals(triple, 0, otherTriple, 0)))
        #expect(kk_any_hashCode(triple, 0) == kk_any_hashCode(sameTriple, 0))

        #expect(!boolValue(kk_any_equals(first, 0, triple, 0)))
    }

    // Pairs the runtime allocates for its own plumbing (comparator pairs and
    // the like) stay untagged and keep reference identity, so they never look
    // like a Kotlin `Pair` to `is`/`==`.
    @Test
    func testUntaggedRuntimePairKeepsReferenceIdentity() {
        let first = registerRuntimeObject(RuntimePairBox(first: 1, second: 2))
        let second = registerRuntimeObject(RuntimePairBox(first: 1, second: 2))

        #expect(boolValue(kk_any_equals(first, 0, first, 0)))
        #expect(!boolValue(kk_any_equals(first, 0, second, 0)))
    }

    // Hashed collections and list searches go through runtimeValuesEqual /
    // runtimeElementKeyHash, which must follow Any.equals/hashCode: plain
    // classes by identity, data classes structurally.
    @Test
    func testCollectionKeysUseIdentityForPlainClassesAndStructureForDataClasses() {
        let plainID = 0x51_14
        let first = kk_object_new(1, plainID)
        let second = kk_object_new(1, plainID)
        _ = kk_array_set(first, 0, 7, nil)
        _ = kk_array_set(second, 0, 7, nil)
        #expect(!runtimeValuesEqual(first, second))
        #expect(runtimeValuesEqual(first, first))
        #expect(RuntimeElementKey(value: first) != RuntimeElementKey(value: second))

        let dataID = 0x51_15
        _ = kk_runtime_register_data_class(dataID)
        let dataFirst = kk_object_new(1, dataID)
        let dataSecond = kk_object_new(1, dataID)
        _ = kk_array_set(dataFirst, 0, 7, nil)
        _ = kk_array_set(dataSecond, 0, 7, nil)
        #expect(runtimeValuesEqual(dataFirst, dataSecond))
        #expect(RuntimeElementKey(value: dataFirst) == RuntimeElementKey(value: dataSecond))
    }

    @Test
    func testCollectionKeysHonorRegisteredEqualsAndHashCodeOverrides() {
        let classID = 0x51_16
        let first = kk_object_new(2, classID)
        let second = kk_object_new(2, classID)
        _ = kk_array_set(first, 0, 7, nil)
        _ = kk_array_set(first, 1, 1, nil)
        _ = kk_array_set(second, 0, 7, nil)
        _ = kk_array_set(second, 1, 2, nil)
        for object in [first, second] {
            _ = kk_object_register_equals_override(
                object,
                unsafeBitCast(runtimeAnyEqualityOverride, to: Int.self)
            )
            _ = kk_object_register_hashcode_override(
                object,
                unsafeBitCast(runtimeAnyHashCodeOverride, to: Int.self)
            )
        }

        #expect(runtimeValuesEqual(first, second))
        let firstKey = RuntimeElementKey(value: first)
        let secondKey = RuntimeElementKey(value: second)
        #expect(firstKey == secondKey)
        #expect(firstKey.hashValue == secondKey.hashValue)
        #expect(Set([firstKey, secondKey]).count == 1)
    }

    @Test
    func testCharScalarKeyDoesNotMatchIntOrLongOfSameCode() {
        let charKey = RuntimeElementKey(runtimeValue: RuntimeValue(charScalar: 97))
        #expect(charKey == RuntimeElementKey(value: kk_box_char(97)))
        #expect(charKey == RuntimeElementKey(runtimeValue: RuntimeValue(charScalar: 97)))
        #expect(charKey != RuntimeElementKey(value: kk_box_int(97)))
        #expect(charKey != RuntimeElementKey(value: kk_box_long(97)))
        #expect(Set([charKey, RuntimeElementKey(value: kk_box_int(97))]).count == 2)
    }
}
#endif
