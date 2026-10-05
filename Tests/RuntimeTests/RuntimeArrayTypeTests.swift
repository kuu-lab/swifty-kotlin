@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeArrayTypeTests {
    private static let nominalBase: Int64 = 6
    private static let payloadShift: Int64 = 9

    private func nominalTypeToken(for fqName: String) -> Int {
        let typeID = runtimeStableNominalTypeID(fqName: fqName)
        return Int(Self.nominalBase | (typeID << Self.payloadShift))
    }

    @Test
    func taggedArrayMatchesItsNominalTypeAndSurvivesCopy() throws {
        let array = kk_array_new(2)
        let intArrayTypeID = runtimeStableNominalTypeID(fqName: "kotlin.IntArray")
        _ = kk_array_tag_type(array, Int(intArrayTypeID))

        #expect(kk_op_is(array, nominalTypeToken(for: "kotlin.IntArray")) == 1)
        #expect(kk_op_is(array, nominalTypeToken(for: "kotlin.LongArray")) == 0)

        let copy = __kk_array_copyOf(array)
        #expect(kk_op_is(copy, nominalTypeToken(for: "kotlin.IntArray")) == 1)
    }

    @Test(arguments: [
        "Array", "BooleanArray", "ByteArray", "CharArray", "DoubleArray", "FloatArray",
        "IntArray", "LongArray", "ShortArray", "UByteArray", "UShortArray", "UIntArray", "ULongArray",
    ])
    func arrayRenderingUsesStableIdentity(typeName: String) {
        let array = kk_array_new(1)
        let fqName = "kotlin.\(typeName)"
        _ = kk_array_tag_type(array, Int(runtimeStableNominalTypeID(fqName: fqName)))
        let hash = String(UInt32(truncatingIfNeeded: kk_any_hashCode(array, 0)), radix: 16)
        let expected = "\(fqName)@\(hash)"

        #expect(runtimeElementToString(array) == expected)
        #expect(runtimeRenderAnyForPrint(array) == expected)
        #expect(extractString(from: kk_any_to_string(array, 0)) == expected)

        var thrown = 0
        _ = kk_array_set(array, 0, 42, &thrown)
        #expect(thrown == 0)
        #expect(runtimeElementToString(array) == expected)
        #expect(runtimeElementToString(__kk_array_copyOf(array)) != expected)
    }

    @Test
    func nestedAndCyclicArraysRenderContentsOnlyForDeepConversion() {
        let inner = kk_array_new(2)
        var thrown = 0
        _ = kk_array_set(inner, 0, 1, &thrown)
        _ = kk_array_set(inner, 1, 2, &thrown)
        let outer = kk_array_new(1)
        _ = kk_array_set(outer, 0, inner, &thrown)
        #expect(thrown == 0)

        let innerIdentity = runtimeElementToString(inner)
        let list = kk_list_of(outer, 1)
        #expect(runtimeElementToString(list) == "[\(innerIdentity)]")
        #expect(runtimeRenderAnyForPrint(list) == "[\(innerIdentity)]")
        #expect(extractString(from: __kk_array_contentDeepToString(outer)) == "[[1, 2]]")

        _ = kk_array_set(outer, 0, outer, &thrown)
        #expect(thrown == 0)
        #expect(runtimeElementToString(outer).hasPrefix("kotlin.Array@"))
        #expect(runtimeRenderAnyForPrint(outer) == runtimeElementToString(outer))
        #expect(extractString(from: __kk_array_contentDeepToString(outer)) == "[[...]]")
    }
}
