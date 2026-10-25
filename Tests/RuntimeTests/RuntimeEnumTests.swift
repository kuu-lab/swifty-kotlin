@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.metadataOnly))
struct RuntimeEnumTests {
    @Test
    func enumNameReadsDeclaredNameFromTaggedBox() {
        let first = kk_enum_box_ordinal(0, runtimeMakeStringRaw("FIRST"), 91_201)
        let second = kk_enum_box_ordinal(1, runtimeMakeStringRaw("SECOND"), 91_201)
        let other = kk_enum_box_ordinal(1, runtimeMakeStringRaw("OTHER"), 91_202)
        #expect(extractString(from: UnsafeMutableRawPointer(bitPattern: kk_enum_name(first))) == "FIRST")
        #expect(extractString(from: UnsafeMutableRawPointer(bitPattern: kk_enum_name(second))) == "SECOND")
        #expect(extractString(from: UnsafeMutableRawPointer(bitPattern: kk_enum_name(other))) == "OTHER")
        #expect(kk_unbox_int(first) == 0)
        #expect(kk_unbox_int(second) == 1)

        let clone = runtimeClonePrimitiveBox(second) as? RuntimeIntBox
        #expect(clone?.enumEntryName == "SECOND")
        #expect(clone?.renderedString == "SECOND")
        let values = kk_array_new(1)
        _ = kk_array_set(values, 0, second, nil)
        let token = (Int64(91_201) << RuntimeTypeTokenEncoding.payloadShift)
            | RuntimeTypeTokenEncoding.nominalBase
        _ = kk_enum_register_values(Int(token), values, 1)
        let restored = kk_array_get(kk_enum_values_for_token(Int(token)), 0, nil)
        #expect(extractString(from: UnsafeMutableRawPointer(bitPattern: kk_enum_name(restored))) == "SECOND")
        #expect(extractString(from: kk_any_member_to_string(restored)) == "SECOND")
    }

    @Test
    func emptyEnumEntriesUseDistinctStableCacheKeys() {
        let firstEnumID = 91_001
        let secondEnumID = 91_002

        let firstEntries = kk_enum_make_entries_list_cached(kk_array_new(0), 0, firstEnumID)
        let firstEntriesAgain = kk_enum_make_entries_list_cached(kk_array_new(0), 0, firstEnumID)
        let secondEntries = kk_enum_make_entries_list_cached(kk_array_new(0), 0, secondEnumID)

        #expect(firstEntries == firstEntriesAgain)
        #expect(firstEntries != secondEntries)
    }

    @Test
    func enumBoxEqualityIncludesEnumClassIdentity() {
        let firstEnumEntry = kk_enum_box_ordinal(0, 0, 91_101)
        let sameEnumEntry = kk_enum_box_ordinal(0, 0, 91_101)
        let otherEnumEntry = kk_enum_box_ordinal(0, 0, 91_102)

        #expect(kk_unbox_bool(kk_any_member_equals(firstEnumEntry, sameEnumEntry)) == 1)
        #expect(kk_unbox_bool(kk_any_member_equals(firstEnumEntry, otherEnumEntry)) == 0)
        #expect(kk_unbox_bool(kk_any_member_equals(firstEnumEntry, kk_box_int(0))) == 0)
    }

    @Test
    func enumEntryHashCodeMatchesAcrossDirectAndBoxedRepresentations() {
        let enumClassID = 91_301
        let firstDirectHash = kk_enum_hash_code(0, enumClassID)
        let secondDirectHash = kk_enum_hash_code(1, enumClassID)
        let firstBox = kk_enum_box_ordinal(0, 0, enumClassID)
        let secondBox = kk_enum_box_ordinal(1, 0, enumClassID)

        #expect(firstDirectHash != 0)
        #expect(secondDirectHash != 1)
        #expect(kk_enum_hash_code(0, enumClassID) == firstDirectHash)
        #expect(kk_any_member_hashCode(firstBox) == firstDirectHash)
        #expect(kk_any_member_hashCode(secondBox) == secondDirectHash)
    }

    @Test
    func enumCompareToReturnsOrdinalDifferenceForRawAndBoxedValues() {
        let first = kk_enum_box_ordinal(0, runtimeMakeStringRaw("FIRST"), 91_401)
        let last = kk_enum_box_ordinal(2, runtimeMakeStringRaw("LAST"), 91_401)

        #expect(kk_enum_compareTo(0, 2) == -2)
        #expect(kk_enum_compareTo(2, 0) == 2)
        #expect(kk_enum_compareTo(1, 1) == 0)
        #expect(kk_enum_compareTo(first, last) == -2)
        #expect(kk_enum_compareTo(last, first) == 2)
    }
}
