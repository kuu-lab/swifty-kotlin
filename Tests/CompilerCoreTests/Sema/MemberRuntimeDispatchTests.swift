#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct MemberRuntimeDispatchTests {
    @Test func testRangeRuntimeDispatchUsesTypedReceiverKind() {
        let cases: [(MemberDispatchReceiverKind, String, Int, String)] = [
            (.intRange, "random", 0, "kk_range_random"),
            (.intRange, "random", 1, "kk_range_random_random"),
            (.longRange, "random", 0, "kk_long_range_random"),
            (.longRange, "random", 1, "kk_long_range_random_random"),
            (.charRange, "random", 0, "kk_range_random"),
            (.charRange, "random", 1, "kk_char_range_random_random"),
            (.uintRange, "randomOrNull", 0, "kk_uint_range_randomOrNull"),
            (.ulongRange, "randomOrNull", 1, "kk_ulong_range_randomOrNull_random"),
            (.charRange, "randomOrNull", 0, "kk_char_range_randomOrNull"),
            (.longRange, "firstOrNull", 0, "kk_long_range_firstOrNull"),
            (.longRange, "firstOrNull", 2, "kk_range_firstOrNull_predicate"),
            (.longRange, "lastOrNull", 0, "kk_long_range_lastOrNull"),
            (.longRange, "lastOrNull", 2, "kk_range_lastOrNull_predicate"),
            (.charProgression, "toList", 0, "kk_char_range_toList"),
            (.charProgression, "step", 1, "kk_char_range_step"),
            (.longProgression, "step", 0, "kk_long_range_step"),
            (.uintProgression, "step", 2, "kk_uint_step"),
            (.ulongProgression, "contains", 1, "kk_ulong_range_contains"),
            // step(n) as a dot call (arity 1) must resolve to the progression-
            // constructing runtime function, not the step-property getter
            // (KSWIFTK-RUNTIME-0001: (1L..10L).step(2L) used to alias the getter
            // and hand back a raw step value instead of a new range handle).
            (.intRange, "step", 1, "kk_op_step"),
            (.longRange, "step", 1, "kk_op_step"),
            (.longProgression, "step", 1, "kk_op_step"),
            (.uintRange, "step", 1, "kk_uint_step"),
            (.ulongRange, "step", 1, "kk_ulong_step"),
        ]

        for (receiverKind, memberName, arity, expectedLinkName) in cases {
            let key = MemberDispatchKey(receiverKind: receiverKind, memberName: memberName, arity: arity)
            #expect(
                MemberRuntimeDispatch.rangeRuntimeLinkName(for: key) == expectedLinkName,
                "\(receiverKind.rawValue).\(memberName)/\(arity)"
            )
        }
    }

    @Test func testCollectionRuntimeDispatchUsesStdlibSurfaceSpec() {
        let cases: [(MemberDispatchReceiverKind, String, Int, String)] = [
            (.iterable, "firstNotNullOf", 1, "kk_iterable_firstNotNullOf"),
            (.set, "map", 1, "kk_list_map"),
            (.map, "filterKeys", 1, "kk_map_filterKeys"),
            (.map, "mapValuesTo", 2, "kk_map_mapValuesTo"),
            (.sequence, "firstNotNullOf", 1, "kk_sequence_firstNotNullOf"),
        ]

        for (receiverKind, memberName, arity, expectedLinkName) in cases {
            let key = MemberDispatchKey(receiverKind: receiverKind, memberName: memberName, arity: arity)
            #expect(
                MemberRuntimeDispatch.collectionRuntimeLinkName(for: key) == expectedLinkName,
                "\(receiverKind.rawValue).\(memberName)/\(arity)"
            )
        }
    }

    @Test func testCollectionRuntimeDispatchIgnoresNonSurfaceMembers() {
        let cases: [(MemberDispatchReceiverKind, String, Int)] = [
            (.list, "size", 0),
            (.map, "getValue", 1),
            (.sequence, "toList", 0),
            (.intRange, "map", 1),
        ]

        for (receiverKind, memberName, arity) in cases {
            let key = MemberDispatchKey(receiverKind: receiverKind, memberName: memberName, arity: arity)
            #expect(
                MemberRuntimeDispatch.collectionRuntimeLinkName(for: key) == nil,
                "\(receiverKind.rawValue).\(memberName)/\(arity)"
            )
        }
    }

    @Test func testStringRuntimeDispatchUsesFlatStringTable() {
        let cases: [(String, Int, String, Bool, MemberRuntimeArgumentMode, MemberRuntimeThrownResultMode)] = [
            ("lowercase", 0, "kk_string_lowercase_flat", false, .lowered, .none),
            ("toInt", 0, "kk_string_toInt_flat", true, .lowered, .none),
            ("toInt", 1, "kk_string_toInt_radix_flat", true, .lowered, .none),
            ("mapIndexed", 1, "kk_string_mapIndexed_flat", false, .normalized, .none),
            ("partition", 1, "kk_string_partition_flat", true, .normalized, .nullableAny),
            ("take", 1, "kk_string_take_flat", true, .lowered, .none),
            ("removeSurrounding", 2, "kk_string_removeSurrounding_pair_flat", false, .lowered, .none),
            ("windowedSequence", 3, "kk_string_windowedSequence_partial_flat", false, .lowered, .none),
        ]

        for (memberName, arity, expectedLinkName, canThrow, argumentMode, thrownResultMode) in cases {
            let key = MemberDispatchKey(receiverKind: .string, memberName: memberName, arity: arity)
            let spec = MemberRuntimeDispatch.stringRuntimeCall(for: key)
            #expect(spec?.runtimeLinkName == expectedLinkName, "String.\(memberName)/\(arity)")
            #expect(spec?.canThrow == canThrow, "String.\(memberName)/\(arity) canThrow")
            #expect(spec?.argumentMode == argumentMode, "String.\(memberName)/\(arity) argument mode")
            #expect(spec?.thrownResultMode == thrownResultMode, "String.\(memberName)/\(arity) thrown result")
        }
    }
}
#endif
