import Testing
@testable import Runtime

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeUIntSignedBackingRenderingTests {
    @Test(arguments: [-1, -2_147_483_648, 0, 2_147_483_647])
    func rendersSignedBackingAsUInt(value: Int) {
        let expected = String(UInt32(truncatingIfNeeded: value))
        #expect(extractString(from: kk_any_to_string(value, 9)) == expected)
        #expect(extractString(from: kk_any_to_string(value, 1)) == String(value))
        let objectRaw = registerRuntimeObject(RuntimeIntBox(value, anyFallbackTag: 9))
        #expect(runtimeRenderAnyForPrint(objectRaw) == expected)
        for boxed in [kk_box_uint(value), kk_box_uint_static(value)] {
            #expect(runtimeElementToString(boxed) == expected)
            #expect(extractString(from: kk_any_to_string(boxed, 1)) == expected)
            #expect(extractString(from: kk_any_to_string(boxed, 9)) == expected)
            #expect(kk_any_hashCode(boxed, 1) == value)
            #expect(kk_unbox_int_static(boxed) == value)
        }
    }

    @Test func nullableUIntRetainsNull() {
        #expect(extractString(from: kk_any_to_string(runtimeNullSentinelInt, 9)) == "null")
        #expect(kk_box_uint(runtimeNullSentinelInt) == runtimeNullSentinelInt)
        #expect(kk_box_uint_static(runtimeNullSentinelInt) == runtimeNullSentinelInt)
    }
}
