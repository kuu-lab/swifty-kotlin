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

    // Floating-point arrays render contents under the KUU-1048 policy.
    @Test(arguments: [
        "Array", "BooleanArray", "ByteArray", "CharArray",
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
    @Test(arguments: ["Byte", "Short", "Int", "Long"])
    func signedAndUnsignedViewsKeepTheirKindsAndShareStorage(width: String) throws {
        let toUnsigned: (Int) -> Int
        let toSigned: (Int) -> Int
        let unsignedMax: String
        switch width {
        case "Byte":
            toUnsigned = kk_byteArray_asUByteArray
            toSigned = kk_uByteArray_asByteArray
            unsignedMax = "255"
        case "Short":
            toUnsigned = kk_shortArray_asUShortArray
            toSigned = kk_uShortArray_asShortArray
            unsignedMax = "65535"
        case "Int":
            toUnsigned = kk_intArray_asUIntArray
            toSigned = kk_uIntArray_asIntArray
            unsignedMax = "4294967295"
        default:
            toUnsigned = kk_longArray_asULongArray
            toSigned = kk_uLongArray_asLongArray
            unsignedMax = "18446744073709551615"
        }
        let unsignedWord = width == "Long" ? -1 : Int(unsignedMax)!
        // Exercise both signed and zero-extended unsigned storage encodings.
        for initiallyUnsigned in [false, true] {
            let signedName = "kotlin.\(width)Array"
            let unsignedName = "kotlin.U\(width)Array"
            let originalElements = [initiallyUnsigned ? unsignedWord : -1, 1]
            let original = taggedArray(initiallyUnsigned ? unsignedName : signedName, elements: originalElements)
            let view = initiallyUnsigned ? toSigned(original) : toUnsigned(original)
            let signed = initiallyUnsigned ? view : original
            let unsigned = initiallyUnsigned ? original : view
            #expect(view != original)
            #expect(toSigned(unsigned) == signed)
            #expect(toUnsigned(signed) == unsigned)
            #expect(kk_op_is(signed, nominalTypeToken(for: signedName)) == 1)
            #expect(kk_op_is(signed, nominalTypeToken(for: unsignedName)) == 0)
            #expect(kk_op_is(unsigned, nominalTypeToken(for: unsignedName)) == 1)
            #expect(kk_op_is(unsigned, nominalTypeToken(for: signedName)) == 0)

            let signedOuter = outerArray(of: signed)
            let unsignedOuter = outerArray(of: unsigned)
            #expect(extractString(from: __kk_array_contentDeepToString(signedOuter)) == "[[-1, 1]]")
            #expect(extractString(from: __kk_array_contentDeepToString(unsignedOuter))
                == "[[\(unsignedMax), 1]]")
            #expect(kk_unbox_bool(__kk_array_contentDeepEquals(signedOuter, unsignedOuter)) == 0)
            let equalUnsigned = outerArray(of: taggedArray(unsignedName, elements: [unsignedWord, 1]))
            let equalSigned = outerArray(of: taggedArray(signedName, elements: [-1, 1]))
            #expect(kk_unbox_bool(__kk_array_contentDeepEquals(signedOuter, equalSigned)) == 1)
            #expect(kk_unbox_bool(__kk_array_contentDeepEquals(unsignedOuter, equalUnsigned)) == 1)
            #expect(__kk_array_contentDeepHashCode(unsignedOuter) == __kk_array_contentDeepHashCode(equalUnsigned))
            #expect(__kk_array_contentDeepHashCode(signedOuter) == __kk_array_contentDeepHashCode(unsignedOuter))

            let copy = __kk_array_copyOf(view)
            #expect(kk_op_is(copy, nominalTypeToken(for: initiallyUnsigned ? signedName : unsignedName)) == 1)
            let signedBox = try #require(runtimeArrayBox(from: signed))
            let unsignedBox = try #require(runtimeArrayBox(from: unsigned))
            signedBox[0] = 42
            #expect(unsignedBox[0] == 42)
            unsignedBox.setValue(RuntimeValue(raw: 7), at: 1)
            #expect(signedBox[1] == 7)
            unsignedBox.elements = [8, 9]
            #expect(signedBox.elements == [8, 9])
            signedBox.values = [RuntimeValue(raw: 10), RuntimeValue(raw: 11)]
            #expect(unsignedBox.elements == [10, 11])
            #expect(runtimeArrayBox(from: copy)?.elements == originalElements)
        }
    }

}
