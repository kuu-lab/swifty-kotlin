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

    private func taggedArray(_ fqName: String, elements: [Int]) -> Int {
        let array = kk_array_new(elements.count)
        _ = kk_array_tag_type(array, Int(runtimeStableNominalTypeID(fqName: fqName)))
        var thrown = 0
        for (index, element) in elements.enumerated() {
            _ = kk_array_set(array, index, element, &thrown)
        }
        return array
    }

    private func outerArray(of raw: Int) -> Int {
        let outer = kk_array_new(1)
        var thrown = 0
        _ = kk_array_set(outer, 0, raw, &thrown)
        return outer
    }

    @Test
    func deepOperationsReadPrimitiveArrayElementsByValue() {
        let doubles = taggedArray("kotlin.DoubleArray", elements: [
            kk_double_to_bits(1.0), kk_double_to_bits(-0.0),
        ])
        let booleans = taggedArray("kotlin.BooleanArray", elements: [1, 0])
        let chars = taggedArray("kotlin.CharArray", elements: [97, 122])
        let ulongs = taggedArray("kotlin.ULongArray", elements: [-1])
        let outer = kk_array_new(4)
        var thrown = 0
        _ = kk_array_set(outer, 0, doubles, &thrown)
        _ = kk_array_set(outer, 1, booleans, &thrown)
        _ = kk_array_set(outer, 2, chars, &thrown)
        _ = kk_array_set(outer, 3, ulongs, &thrown)
        #expect(thrown == 0)

        #expect(extractString(from: __kk_array_contentDeepToString(outer))
            == "[[1.0, -0.0], [true, false], [a, z], [18446744073709551615]]")
    }

    @Test
    func deepHashCodeUsesPrimitiveElementSemantics() {
        // Arrays.hashCode(double[]) folds the element's full bit pattern
        // (Double.hashCode), and canonicalizes every NaN payload.
        let one = outerArray(of: taggedArray("kotlin.DoubleArray", elements: [kk_double_to_bits(1.0)]))
        let negativeZero = outerArray(of: taggedArray("kotlin.DoubleArray", elements: [kk_double_to_bits(-0.0)]))
        let payloadNaN = outerArray(of: taggedArray(
            "kotlin.DoubleArray",
            elements: [kk_double_to_bits(Double(bitPattern: 0x7FF4_0000_0000_0001))]
        ))
        #expect(__kk_array_contentDeepHashCode(one) == 1_072_693_310)
        #expect(__kk_array_contentDeepHashCode(negativeZero) == -2_147_483_586)
        #expect(__kk_array_contentDeepHashCode(payloadNaN) == 2_146_959_422)

        let boolTrue = outerArray(of: taggedArray("kotlin.BooleanArray", elements: [1]))
        let boolFalse = outerArray(of: taggedArray("kotlin.BooleanArray", elements: [0]))
        #expect(__kk_array_contentDeepHashCode(boolTrue) == 1_293)
        #expect(__kk_array_contentDeepHashCode(boolFalse) == 1_299)

        let longMin = outerArray(of: taggedArray("kotlin.LongArray", elements: [Int.min]))
        #expect(__kk_array_contentDeepHashCode(longMin) == -2_147_483_586)

        // Unsigned arrays hash their signed storage value.
        let ubyte = outerArray(of: taggedArray("kotlin.UByteArray", elements: [200]))
        #expect(__kk_array_contentDeepHashCode(ubyte) == 6)
    }

    @Test
    func deepEqualsRequiresSamePrimitiveArrayKind() {
        let oneDouble = taggedArray("kotlin.DoubleArray", elements: [kk_double_to_bits(1.0)])
        let sameBitsLong = taggedArray("kotlin.LongArray", elements: [kk_double_to_bits(1.0)])
        let oneDoubleCopy = taggedArray("kotlin.DoubleArray", elements: [kk_double_to_bits(1.0)])
        let payloadNaN = taggedArray(
            "kotlin.DoubleArray",
            elements: [kk_double_to_bits(Double(bitPattern: 0x7FF4_0000_0000_0001))]
        )
        let canonicalNaN = taggedArray("kotlin.DoubleArray", elements: [kk_double_to_bits(.nan)])
        let negativeZero = taggedArray("kotlin.DoubleArray", elements: [kk_double_to_bits(-0.0)])
        let positiveZero = taggedArray("kotlin.DoubleArray", elements: [kk_double_to_bits(0.0)])
        let oneGeneric = outerArray(of: oneDouble)
        let sameBitsLongOuter = outerArray(of: sameBitsLong)

        #expect(kk_unbox_bool(__kk_array_contentDeepEquals(oneGeneric, outerArray(of: oneDoubleCopy))) == 1)
        // Same element bit pattern, different array kind: not deep-equal.
        #expect(kk_unbox_bool(__kk_array_contentDeepEquals(oneGeneric, sameBitsLongOuter)) == 0)
        // NaN payloads canonicalize: payload NaN == canonical NaN.
        #expect(kk_unbox_bool(__kk_array_contentDeepEquals(
            outerArray(of: payloadNaN), outerArray(of: canonicalNaN)
        )) == 1)
        // -0.0 != 0.0 (Double.equals semantics).
        #expect(kk_unbox_bool(__kk_array_contentDeepEquals(
            outerArray(of: negativeZero), outerArray(of: positiveZero)
        )) == 0)
        // A primitive array never deep-equals a generic Array<Double>,
        // even when the boxed element is the same value.
        var thrown = 0
        let genericInner = kk_array_new(1)
        _ = kk_array_set(genericInner, 0, kk_box_double(kk_double_to_bits(1.0)), &thrown)
        #expect(thrown == 0)
        #expect(kk_unbox_bool(__kk_array_contentDeepEquals(
            oneGeneric, outerArray(of: genericInner)
        )) == 0)
    }
}
