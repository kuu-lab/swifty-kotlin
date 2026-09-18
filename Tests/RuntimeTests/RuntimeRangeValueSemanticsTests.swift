@testable import Runtime
import Testing

/// Runtime contracts for typed range value equality and hashing.
@Suite(.serialized, .runtimeIsolation(.gcOnly))
struct RuntimeRangeValueSemanticsTests {
    @Test
    func rangesCompareByValueAndEmptyRangesCompareEqual() {
        let range = kk_op_rangeTo(1, 3)
        let sameRange = kk_op_rangeTo(1, 3)
        let differentRange = kk_op_rangeTo(1, 4)
        let emptyRange = kk_op_rangeTo(5, 2)
        let otherEmptyRange = kk_op_rangeTo(10, 0)
        let progression = __kk_op_step(range, 3, nil)
        let sameProgression = __kk_op_step(sameRange, 3, nil)
        let longUntil = __kk_long_rangeUntil(4_294_967_297, 4_294_967_300)
        let sameLongUntil = __kk_long_rangeUntil(4_294_967_297, 4_294_967_300)
        let charUntil = __kk_char_rangeUntil(kk_box_char(97), kk_box_char(99))
        let sameCharUntil = __kk_char_rangeUntil(kk_box_char(97), kk_box_char(99))

        #expect(runtimeValuesEqual(range, sameRange))
        #expect(!runtimeValuesEqual(range, differentRange))
        #expect(runtimeValuesEqual(emptyRange, otherEmptyRange))
        #expect(runtimeValuesEqual(progression, sameProgression))
        #expect(runtimeValuesEqual(longUntil, sameLongUntil))
        #expect(runtimeValuesEqual(charUntil, sameCharUntil))
        #expect(kk_structural_eq(range, sameRange) == 1)
        #expect(kk_structural_ne(range, differentRange) == 1)
    }

    @Test
    func rangesUseKotlinHashContracts() {
        let intRange = kk_op_rangeTo(1, 3)
        let emptyRange = kk_op_rangeTo(5, 2)
        let progression = __kk_op_step(kk_op_rangeTo(1, 10), 3, nil)
        let longRange = kk_long_rangeTo(1, 3)
        let longProgression = __kk_op_step(longRange, 3, nil)
        let charRange = kk_char_rangeTo(kk_box_char(97), kk_box_char(99))
        let charProgression = __kk_char_range_step(charRange, 2, nil)

        #expect(kk_any_hashCode(intRange, 1) == 34)
        #expect(kk_any_hashCode(emptyRange, 1) == -1)
        #expect(kk_any_hashCode(progression, 1) == 1274)
        #expect(kk_any_hashCode(longRange, 1) == 34)
        #expect(kk_any_hashCode(longProgression, 1) == 995)
        #expect(kk_any_hashCode(charRange, 1) == 3106)
        #expect(kk_any_hashCode(charProgression, 1) == 96_288)
    }

    @Test
    func nominalRangeKindsRemainDistinctInCollections() {
        let intRange = kk_op_rangeTo(1, 3)
        let sameIntRange = kk_op_rangeTo(1, 3)
        let longRange = kk_long_rangeTo(1, 3)
        let list = RuntimeListBox(elements: [intRange])
        let map = RuntimeMapBox(keys: [intRange], values: [42])

        #expect(list.elements.contains { runtimeValuesEqual($0, sameIntRange) })
        #expect(map.index(ofRawKey: sameIntRange) == 0)
        #expect(!runtimeValuesEqual(intRange, longRange))
        #expect(kk_unbox_bool(kk_any_equals(intRange, 1, sameIntRange, 1)) == 1)
        #expect(kk_unbox_bool(kk_any_equals(intRange, 1, longRange, 1)) == 0)
    }
}
