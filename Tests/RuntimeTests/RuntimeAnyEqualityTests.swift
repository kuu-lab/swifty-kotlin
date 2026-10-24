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

private let runtimeObjectsNullEqualityOverride: @convention(c) (
    Int, Int, UnsafeMutablePointer<Int>?
) -> Int = { _, rhs, outThrown in
    outThrown?.pointee = 0
    return rhs == runtimeNullSentinelInt ? 1 : 0
}

private let runtimeObjectsThrowingEqualityOverride: @convention(c) (
    Int, Int, UnsafeMutablePointer<Int>?
) -> Int = { lhs, _, outThrown in
    outThrown?.pointee = kk_array_get(lhs, 0, nil)
    return 0
}

private let runtimeAnyEntryValueGetter: @convention(c) (
    Int,
    UnsafeMutablePointer<Int>?
) -> Int = { receiver, outThrown in
    outThrown?.pointee = 0
    return kk_array_get(receiver, 1, nil)
}

private let runtimeAnyEntryHashOverride: @convention(c) (
    Int, UnsafeMutablePointer<Int>?
) -> Int = { receiver, outThrown in
    outThrown?.pointee = 0
    return kk_array_get(receiver, 0, nil) ^ kk_array_get(receiver, 1, nil)
}

private let runtimeAnyEntryIdentityHashOverride: @convention(c) (
    Int, UnsafeMutablePointer<Int>?
) -> Int = { receiver, outThrown in
    outThrown?.pointee = 0
    return Int(Int32(truncatingIfNeeded: kk_native_identityHashCode(kk_array_get(receiver, 0, nil)))
        ^ Int32(truncatingIfNeeded: kk_native_identityHashCode(kk_array_get(receiver, 1, nil))))
}

private let runtimeAnyEntryEqualsOverride: @convention(c) (
    Int, Int, UnsafeMutablePointer<Int>?
) -> Int = { receiver, other, outThrown in
    outThrown?.pointee = 0
    guard let entry = runtimeMapEntryValues(rawValue: other) else { return 0 }
    return kk_array_get(receiver, 0, nil) == entry.key
        && kk_array_get(receiver, 1, nil) == entry.value ? 1 : 0
}

private let runtimeCallableReferenceTarget: KKFunctionEntryPoint1 = { value, outThrown in
    outThrown?.pointee = 0
    return value
}

private let runtimeCallableReferenceOtherTarget: KKFunctionEntryPoint1 = { _, outThrown in
    outThrown?.pointee = 0
    return 0
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
    func testObjectsEqualsPreservesOverrideNullAndThrownChannel() {
        let receiver = kk_object_new(1, 0x51_25)
        let other = kk_object_new(0, 0x51_25)
        _ = kk_object_register_equals_override(
            receiver, unsafeBitCast(runtimeObjectsNullEqualityOverride, to: Int.self)
        )
        var thrown = 123
        #expect(boolValue(__kk_objects_equals(receiver, runtimeNullSentinelInt, &thrown)))
        #expect(thrown == 0)
        #expect(!boolValue(__kk_objects_equals(receiver, other, &thrown)))
        #expect(thrown == 0)

        let exception = kk_illegal_state_exception_new()
        _ = kk_array_set(receiver, 0, exception, nil)
        _ = kk_object_register_equals_override(
            receiver, unsafeBitCast(runtimeObjectsThrowingEqualityOverride, to: Int.self)
        )
        #expect(!boolValue(__kk_objects_equals(receiver, other, &thrown)))
        #expect(thrown == exception)
    }

    @Test
    func testObjectsEqualsCanonicalBoxedFloatingValues() {
        let floatNaN = kk_box_float(0x7fc0_0001)
        let otherFloatNaN = kk_box_float(0x7fc0_0002)
        let doubleNaN = kk_box_double_nonnull(0x7ff8_0000_0000_0001)
        let otherDoubleNaN = kk_box_double_nonnull(0x7ff8_0000_0000_0002)
        var thrown = 123
        #expect(boolValue(__kk_objects_equals(floatNaN, otherFloatNaN, &thrown)))
        #expect(thrown == 0)
        #expect(boolValue(__kk_objects_equals(doubleNaN, otherDoubleNaN, &thrown)))
        #expect(!boolValue(__kk_objects_equals(floatNaN, doubleNaN, &thrown)))
        #expect(boolValue(kk_any_equals(floatNaN, 0, otherFloatNaN, 0)))
        #expect(boolValue(kk_any_equals(doubleNaN, 0, otherDoubleNaN, 0)))
        #expect(boolValue(kk_any_member_equals(doubleNaN, otherDoubleNaN)))
        #expect(!boolValue(__kk_objects_equals(kk_box_float(0x8000_0000), kk_box_float(0), &thrown)))
        #expect(!boolValue(__kk_objects_equals(kk_box_double_nonnull(Int.min), kk_box_double_nonnull(0), &thrown)))
    }

    @Test
    func testAnyEqualsCanonicalizesRawFloatingNaNPayloads() {
        let doubleNaN = Int(bitPattern: UInt(0x7ff8_0000_0000_0001))
        let otherDoubleNaN = Int(bitPattern: UInt(0xfff8_0000_0000_0042))
        let floatNaN = Int(Int32(bitPattern: 0x7fc0_0001))
        let otherFloatNaN = Int(Int32(bitPattern: 0xffc0_0042))

        #expect(boolValue(kk_any_equals(doubleNaN, 6, otherDoubleNaN, 6)))
        #expect(boolValue(kk_any_equals(floatNaN, 5, otherFloatNaN, 5)))
        #expect(boolValue(kk_any_equals(doubleNaN, 6, kk_box_double_nonnull(otherDoubleNaN), 0)))
        #expect(!boolValue(kk_any_equals(Int.min, 6, 0, 6)))
        #expect(!boolValue(kk_any_equals(0, 6, 0, 1)))
        #expect(!boolValue(kk_any_equals(0, 5, 0, 6)))
        #expect(boolValue(kk_any_equals(runtimeNullSentinelInt, 6, runtimeNullSentinelInt, 6)))
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
    func callableReferenceEqualityUsesTargetAndCaptures() {
        func reference(target: Int, captures: [Int] = [], isProperty: Bool = false) -> Int {
            var thrown = 0
            let value = isProperty
                ? kk_object_new(1, 0x51_44)
                : kk_function_create_1(target, 0, &thrown)
            if isProperty {
                _ = kk_callable_ref_tag_kproperty(
                    value,
                    runtimeMakeStringRaw("p"),
                    runtimeMakeStringRaw("kotlin.Int"),
                    0
                )
            } else {
                _ = kk_callable_ref_tag_kfunction(
                    value,
                    runtimeMakeStringRaw("f"),
                    runtimeMakeStringRaw("kotlin.Int"),
                    1,
                    0
                )
            }
            let capturesRaw = captures.isEmpty
                ? runtimeNullSentinelInt
                : registerRuntimeObject(RuntimeListBox(elements: captures))
            __kk_callable_ref_set_identity(value, target, capturesRaw)
            return value
        }

        let target = unsafeBitCast(runtimeCallableReferenceTarget, to: Int.self)
        let otherTarget = unsafeBitCast(runtimeCallableReferenceOtherTarget, to: Int.self)
        let first = reference(target: target)
        let same = reference(target: target)
        let other = reference(target: otherTarget)
        let captured = reference(target: target, captures: [kk_box_int(7)])
        let sameCapture = reference(target: target, captures: [kk_box_int(7)])
        let otherCapture = reference(target: target, captures: [kk_box_int(8)])
        let firstProperty = reference(target: target, captures: [runtimeNullSentinelInt], isProperty: true)
        let sameProperty = reference(target: target, captures: [runtimeNullSentinelInt], isProperty: true)
        let differentPropertyCapture = reference(target: target, captures: [kk_box_int(7)], isProperty: true)

        #expect(boolValue(kk_any_equals(first, 0, same, 0)))
        #expect(kk_any_hashCode(first, 0) == kk_any_hashCode(same, 0))
        #expect(!boolValue(kk_any_equals(first, 0, other, 0)))
        #expect(boolValue(kk_any_equals(captured, 0, sameCapture, 0)))
        #expect(kk_any_hashCode(captured, 0) == kk_any_hashCode(sameCapture, 0))
        #expect(!boolValue(kk_any_equals(captured, 0, otherCapture, 0)))
        #expect(boolValue(kk_any_equals(firstProperty, 0, sameProperty, 0)))
        #expect(kk_any_hashCode(firstProperty, 0) == kk_any_hashCode(sameProperty, 0))
        #expect(!boolValue(kk_any_equals(firstProperty, 0, differentPropertyCapture, 0)))
        #expect(!boolValue(kk_any_equals(first, 0, firstProperty, 0)))

        var thrown = 0
        let lambda = kk_function_create_1(target, 0, &thrown)
        let otherLambda = kk_function_create_1(target, 0, &thrown)
        #expect(!boolValue(kk_any_equals(lambda, 0, otherLambda, 0)))
    }

    // KUU-2940: `fun interface` SAM adapters built from callable references get
    // JVM `FunctionAdapter` equality — equal when the other operand implements
    // the same interface and holds an equal function delegate; a raw callable
    // reference or a wrapper of another interface is never equal.
    @Test
    func samAdapterEqualityUsesInterfaceTargetAndCaptures() {
        let ifaceID = 0x51_40
        let otherIfaceID = 0x51_41
        let wrapperClassID = 0x51_42
        let otherWrapperClassID = 0x51_43
        _ = kk_type_register_iface(wrapperClassID, ifaceID)
        _ = kk_type_register_iface(otherWrapperClassID, otherIfaceID)
        func samWrapper(
            classID: Int = wrapperClassID,
            interfaceID: Int = ifaceID,
            target: Int,
            captures: [Int] = []
        ) -> Int {
            let value = kk_object_new(1, classID)
            let capturesRaw = captures.isEmpty
                ? runtimeNullSentinelInt
                : registerRuntimeObject(RuntimeListBox(elements: captures))
            __kk_sam_adapter_set_identity(value, interfaceID, target, capturesRaw, 0, 0)
            return value
        }

        let target = unsafeBitCast(runtimeCallableReferenceTarget, to: Int.self)
        let otherTarget = unsafeBitCast(runtimeCallableReferenceOtherTarget, to: Int.self)
        let first = samWrapper(target: target)
        let same = samWrapper(target: target)
        let other = samWrapper(target: otherTarget)
        let captured = samWrapper(target: target, captures: [kk_box_int(7)])
        let sameCapture = samWrapper(target: target, captures: [kk_box_int(7)])
        let otherCapture = samWrapper(target: target, captures: [kk_box_int(8)])
        let otherIface = samWrapper(classID: otherWrapperClassID, interfaceID: otherIfaceID, target: target)

        #expect(boolValue(kk_any_equals(first, 0, same, 0)))
        #expect(boolValue(kk_any_equals(same, 0, first, 0)))
        #expect(kk_any_hashCode(first, 0) == kk_any_hashCode(same, 0))
        #expect(!boolValue(kk_any_equals(first, 0, other, 0)))
        #expect(boolValue(kk_any_equals(captured, 0, sameCapture, 0)))
        #expect(kk_any_hashCode(captured, 0) == kk_any_hashCode(sameCapture, 0))
        #expect(!boolValue(kk_any_equals(captured, 0, otherCapture, 0)))
        #expect(!boolValue(kk_any_equals(first, 0, otherIface, 0)))
        #expect(!boolValue(kk_any_equals(otherIface, 0, first, 0)))

        // A SAM adapter is not equal to the raw callable reference it wraps,
        // but shares its delegate hash code (JVM FunctionAdapter contract).
        var thrown = 0
        let rawRef = kk_function_create_1(target, 0, &thrown)
        _ = kk_callable_ref_tag_kfunction(
            rawRef, runtimeMakeStringRaw("f"), runtimeMakeStringRaw("kotlin.Unit"), 0, 0
        )
        __kk_callable_ref_set_identity(rawRef, target, runtimeNullSentinelInt)
        #expect(!boolValue(kk_any_equals(first, 0, rawRef, 0)))
        #expect(!boolValue(kk_any_equals(rawRef, 0, first, 0)))
        #expect(kk_any_hashCode(first, 0) == kk_any_hashCode(rawRef, 0))

        // An object that implements the interface but carries no adapter
        // identity is not equal (it is not a FunctionAdapter on the JVM).
        let plainImpl = kk_object_new(1, wrapperClassID)
        #expect(!boolValue(kk_any_equals(first, 0, plainImpl, 0)))
        #expect(!boolValue(kk_any_equals(first, 0, runtimeNullSentinelInt, 0)))
    }

    @Test
    func testDataClassFieldMaskIgnoresBodyPropertySlotsInEqualityAndHash() {
        let classID = 0x51_20
        _ = kk_runtime_register_data_class(classID)
        // Slot 0 models a primary-constructor property, slot 1 a body property.
        _ = kk_runtime_register_data_class_fields(classID, 0b01)
        let first = kk_object_new(2, classID)
        let second = kk_object_new(2, classID)
        _ = kk_array_set(first, 0, 7, nil)
        _ = kk_array_set(second, 0, 7, nil)
        _ = kk_array_set(first, 1, 100, nil)
        _ = kk_array_set(second, 1, 200, nil)

        #expect(boolValue(kk_any_equals(first, 0, second, 0)))
        #expect(kk_any_hashCode(first, 0) == kk_any_hashCode(second, 0))

        _ = kk_array_set(second, 0, 8, nil)
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

    @Test
    func testResultBoxesUseValueEqualityAcrossErasedAnyPaths() {
        let success = runtimeResultSuccess(42)
        let sameSuccess = runtimeResultSuccess(42)
        let otherSuccess = runtimeResultSuccess(43)
        let exception = kk_illegal_state_exception_new()
        let failure = runtimeResultFailure(exception)
        let sameFailure = runtimeResultFailure(exception)
        let otherFailure = runtimeResultFailure(kk_illegal_state_exception_new())

        #expect(boolValue(kk_any_equals(success, 1, sameSuccess, 1)))
        #expect(boolValue(__kk_objects_equals(success, sameSuccess, nil)))
        #expect(!boolValue(kk_any_equals(success, 1, otherSuccess, 1)))
        #expect(!boolValue(kk_any_equals(success, 1, failure, 1)))
        #expect(boolValue(kk_any_equals(failure, 1, sameFailure, 1)))
        #expect(!boolValue(kk_any_equals(failure, 1, otherFailure, 1)))
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

    @Test
    func testMapEntryCompareAndHashStructurallyAcrossEntryKinds() {
        let readOnly = runtimeMapEntryNew(key: 7, value: 8)
        let sameReadOnly = runtimeMapEntryNew(key: 7, value: 8)
        let otherKey = runtimeMapEntryNew(key: 9, value: 8)
        let otherValue = runtimeMapEntryNew(key: 7, value: 10)

        let firstMap = registerRuntimeObject(RuntimeMapBox(keys: [7], values: [8]))
        let secondMap = registerRuntimeObject(RuntimeMapBox(keys: [7], values: [8]))
        let mutableEntry = runtimeMutableMapEntryNew(mapRaw: firstMap, key: 7, value: 8)
        let sameMutableEntry = runtimeMutableMapEntryNew(mapRaw: secondMap, key: 7, value: 8)

        #expect(kk_structural_eq(readOnly, sameReadOnly) == 1)
        #expect(kk_structural_eq(mutableEntry, sameMutableEntry) == 1)
        #expect(kk_structural_eq(readOnly, mutableEntry) == 1)
        #expect(kk_structural_eq(mutableEntry, readOnly) == 1)
        #expect(kk_structural_eq(readOnly, otherKey) == 0)
        #expect(kk_structural_eq(readOnly, otherValue) == 0)

        #expect(kk_any_hashCode(readOnly, 0) == kk_any_hashCode(sameMutableEntry, 0))
        let firstKey = RuntimeElementKey(value: readOnly)
        let secondKey = RuntimeElementKey(value: sameMutableEntry)
        #expect(firstKey == secondKey)
        #expect(firstKey.hashValue == secondKey.hashValue)

        _ = kk_mutable_map_put(secondMap, 7, 11, nil)
        #expect(kk_structural_eq(mutableEntry, sameMutableEntry) == 0)
    }

    @Test
    func testNativeEntryEqualityReadsSourceGettersWithoutReplacingCustomHash() {
        let entryInterface = runtimeStableNominalTypeID(fqName: "kotlin.collections.Map.Entry")
        let native = runtimeMapEntryNew(key: 7, value: 8)
        for (hash, expected) in [(runtimeAnyHashCodeOverride, 7), (runtimeAnyEntryHashOverride, 15)] {
            let source = kk_object_new(2, 0x51_21)
            _ = kk_array_set(source, 0, 7, nil)
            _ = kk_array_set(source, 1, 8, nil)
            _ = kk_object_register_equals_override(
                source, unsafeBitCast(runtimeAnyEntryEqualsOverride, to: Int.self)
            )
            _ = kk_object_register_hashcode_override(source, unsafeBitCast(hash, to: Int.self))
            let originalHash = RuntimeElementKey(value: source).hashValue
            _ = kk_object_register_itable_iface(source, Int(entryInterface), 0)
            _ = kk_object_register_itable_method(
                source, 0, 0, unsafeBitCast(runtimeAnyHashCodeOverride, to: Int.self)
            )
            _ = kk_object_register_itable_method(
                source, 0, 1, unsafeBitCast(runtimeAnyEntryValueGetter, to: Int.self)
            )
            #expect(kk_structural_eq(native, source) == 1)
            #expect(kk_structural_eq(source, native) == 1)
            #expect(kk_structural_eq(runtimeMapEntryNew(key: 9, value: 8), source) == 0)
            #expect(kk_any_hashCode(source, 0) == expected)
            if expected == 7 {
                #expect(RuntimeElementKey(value: source).hashValue == originalHash)
            }
            if expected == 15 {
                let nativeKey = RuntimeElementKey(value: native)
                let sourceKey = RuntimeElementKey(value: source)
                #expect(nativeKey.hashValue == sourceKey.hashValue)
                #expect(Set([nativeKey]).contains(sourceKey))
                #expect(Set([sourceKey]).contains(nativeKey))
                #expect([nativeKey: "entry"][sourceKey] == "entry")
            }
        }
        // Different contents with equal Java hashes still feed distinct content
        // to the randomized internal hasher (the KUU-812 collision boundary).
        let collisionFirst = runtimeMapEntryNew(key: registerRuntimeObject(RuntimeStringBox("Aa")), value: 8)
        let collisionSecond = runtimeMapEntryNew(key: registerRuntimeObject(RuntimeStringBox("BB")), value: 8)
        #expect(kk_any_hashCode(collisionFirst, 0) == kk_any_hashCode(collisionSecond, 0))
        #expect(RuntimeElementKey(value: collisionFirst).hashValue != RuntimeElementKey(value: collisionSecond).hashValue)
    }

    @Test
    func testIdentityEntryHashAndProtectedMembershipUseSourceGetters() throws {
        let key = registerRuntimeObject(RuntimeStringBox("identity-key"))
        let value = registerRuntimeObject(RuntimeStringBox("identity-value"))
        let map = kk_object_new(0, Int(runtimeStableNominalTypeID(fqName: "java.util.IdentityHashMap")))
        _ = kk_identity_hash_map_init(map)
        _ = kk_mutable_map_put(map, key, value, nil)
        let entries = try #require(runtimeSetBox(from: kk_map_entries(map)))
        let native = try #require(entries.elements.first)
        let entryInterface = runtimeStableNominalTypeID(fqName: "kotlin.collections.Map.Entry")
        let source = kk_object_new(2, 0x51_26)
        _ = kk_array_set(source, 0, key, nil)
        _ = kk_array_set(source, 1, value, nil)
        _ = kk_type_register_iface(0x51_26, Int(entryInterface))
        _ = kk_object_register_itable_iface(source, Int(entryInterface), 0)
        _ = kk_object_register_itable_method(source, 0, 0, unsafeBitCast(runtimeAnyHashCodeOverride, to: Int.self))
        _ = kk_object_register_itable_method(source, 0, 1, unsafeBitCast(runtimeAnyEntryValueGetter, to: Int.self))
        _ = kk_object_register_equals_override(source, unsafeBitCast(runtimeAnyEntryEqualsOverride, to: Int.self))
        _ = kk_object_register_hashcode_override(source, unsafeBitCast(runtimeAnyEntryIdentityHashOverride, to: Int.self))
        #expect(kk_structural_eq(native, source) == 1)
        #expect(kk_any_hashCode(native, 0) == kk_any_hashCode(source, 0))
        let nativeKey = RuntimeElementKey(value: native)
        let sourceKey = RuntimeElementKey(value: source)
        #expect(nativeKey.hashValue == sourceKey.hashValue)
        #expect(Set([nativeKey]).contains(sourceKey))
        #expect(Set([sourceKey]).contains(nativeKey))
        #expect([nativeKey: "entry"][sourceKey] == "entry")
        #expect(entries.contains(rawValue: source))

        let ordinary = registerRuntimeObject(RuntimeMapBox(keys: [key], values: [value]))
        let ordinaryEntries = try #require(runtimeSetBox(from: kk_map_entries(ordinary)))
        #expect(ordinaryEntries.contains(rawValue: source))
        let equalKey = registerRuntimeObject(RuntimeStringBox("identity-key"))
        let equalValue = registerRuntimeObject(RuntimeStringBox("identity-value"))
        _ = kk_array_set(source, 0, equalKey, nil)
        _ = kk_array_set(source, 1, equalValue, nil)
        #expect(!entries.contains(rawValue: source))
        #expect(ordinaryEntries.contains(rawValue: source))
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
