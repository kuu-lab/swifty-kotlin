#if canImport(Testing)
@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.gcAndMetadata))
struct RuntimeFloatingPointArrayToStringTests {
    // KUU-4436: DoubleArray/FloatArray do not override Any.toString() on the
    // JVM, so every Any-context render spells the `[D@hash`/`[F@hash`
    // identity. Element-list rendering belongs to contentToString /
    // contentDeepToString, which keep their own paths.

    @Test
    func doubleArrayRendersIdentityAcrossAnyContexts() {
        let values: [Double] = [1.0, 2.5, -0.5, 0.0, -0.0, .nan, .infinity, -.infinity, .leastNonzeroMagnitude]
        let array = makeArray(values.map { Int(bitPattern: UInt($0.bitPattern)) }, type: "kotlin.DoubleArray")
        expectRendering(array, runtimeArrayIdentityToString(array))
        let copy = __kk_array_copyOf(array)
        expectRendering(copy, runtimeArrayIdentityToString(copy))
        #expect(extractString(from: __kk_array_contentDeepToString(array)) == "[1.0, 2.5, -0.5, 0.0, -0.0, NaN, Infinity, -Infinity, 4.9E-324]")
    }

    @Test
    func floatArrayRendersIdentityAcrossAnyContexts() {
        let values: [Float] = [1.0, 2.5, -0.5, 0.0, -0.0, .nan, .infinity, -.infinity, .leastNonzeroMagnitude]
        let array = makeArray(values.map { Int($0.bitPattern) }, type: "kotlin.FloatArray")
        expectRendering(array, runtimeArrayIdentityToString(array))
        let copy = __kk_array_copyOf(array)
        expectRendering(copy, runtimeArrayIdentityToString(copy))
        #expect(extractString(from: __kk_array_contentDeepToString(array)) == "[1.0, 2.5, -0.5, 0.0, -0.0, NaN, Infinity, -Infinity, 1.4E-45]")
    }

    @Test(arguments: ["kotlin.DoubleArray", "kotlin.FloatArray"])
    func emptyAndZeroInitializedArraysRenderIdentity(type: String) {
        let empty = makeArray([], type: type)
        expectRendering(empty, runtimeArrayIdentityToString(empty))
        #expect(extractString(from: __kk_array_contentDeepToString(empty)) == "[]")
        let zeros = makeArray([0, 0], type: type)
        expectRendering(zeros, runtimeArrayIdentityToString(zeros))
        #expect(extractString(from: __kk_array_contentDeepToString(zeros)) == "[0.0, 0.0]")
    }

    @Test
    func nestedArraysAndCollectionsRenderFloatingPointElementsByIdentity() {
        let doubles = makeArray([Int(bitPattern: UInt(Double(1.0).bitPattern))], type: "kotlin.DoubleArray")
        let floats = makeArray([Int(Float(2.5).bitPattern)], type: "kotlin.FloatArray")
        let nested = makeArray([doubles, floats], type: "kotlin.Array")
        expectRendering(nested, runtimeArrayIdentityToString(nested))
        #expect(extractString(from: __kk_array_contentDeepToString(nested)) == "[[1.0], [2.5]]")

        let list = registerRuntimeObject(RuntimeListBox(elements: [doubles, floats]))
        expectRendering(
            list,
            "[\(runtimeArrayIdentityToString(doubles)), \(runtimeArrayIdentityToString(floats))]"
        )
    }

    @Test
    func integerArraysAreNotReinterpretedAsFloatingPoint() {
        for type in ["kotlin.IntArray", "kotlin.LongArray", "kotlin.Array"] {
            let array = makeArray([1065353216, -1], type: type)
            expectRendering(array, runtimeArrayIdentityToString(array))
        }
    }

    private func makeArray(_ elements: [Int], type: String) -> Int {
        let box = RuntimeArrayBox(length: elements.count)
        box.elements = elements
        let raw = registerRuntimeObject(box)
        runtimeRegisterArrayType(rawValue: raw, typeID: runtimeStableNominalTypeID(fqName: type))
        return raw
    }

    private func expectRendering(_ raw: Int, _ expected: String) {
        #expect(runtimeElementToString(raw) == expected)
        #expect(runtimeRenderAnyForPrint(raw) == expected)
        #expect(extractString(from: kk_any_to_string(raw, 0)) == expected)
        #expect(extractString(from: kk_any_to_string_nullable(raw, 0)) == expected)
    }
}
#endif
