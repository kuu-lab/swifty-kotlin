#if canImport(Testing)
@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.gcAndMetadata))
struct RuntimeFloatingPointArrayToStringTests {
    @Test
    func doubleArrayRendersValuesInsteadOfBits() {
        let values: [Double] = [1.0, 2.5, -0.5, 0.0, -0.0, .nan, .infinity, -.infinity, .leastNonzeroMagnitude]
        let array = makeArray(values.map { Int(bitPattern: UInt($0.bitPattern)) }, type: "kotlin.DoubleArray")
        expectRendering(array, "[1.0, 2.5, -0.5, 0.0, -0.0, NaN, Infinity, -Infinity, 4.9E-324]")
        expectRendering(__kk_array_copyOf(array), "[1.0, 2.5, -0.5, 0.0, -0.0, NaN, Infinity, -Infinity, 4.9E-324]")
    }

    @Test
    func floatArrayRendersValuesInsteadOfBits() {
        let values: [Float] = [1.0, 2.5, -0.5, 0.0, -0.0, .nan, .infinity, -.infinity, .leastNonzeroMagnitude]
        let array = makeArray(values.map { Int($0.bitPattern) }, type: "kotlin.FloatArray")
        expectRendering(array, "[1.0, 2.5, -0.5, 0.0, -0.0, NaN, Infinity, -Infinity, 1.4E-45]")
        expectRendering(__kk_array_copyOf(array), "[1.0, 2.5, -0.5, 0.0, -0.0, NaN, Infinity, -Infinity, 1.4E-45]")
    }

    @Test(arguments: ["kotlin.DoubleArray", "kotlin.FloatArray"])
    func emptyAndZeroInitializedArraysRenderValues(type: String) {
        expectRendering(makeArray([], type: type), "[]")
        expectRendering(makeArray([0, 0], type: type), "[0.0, 0.0]")
    }

    @Test
    func nestedArraysAndCollectionsRenderFloatingPointElements() {
        let doubles = makeArray([Int(bitPattern: UInt(Double(1.0).bitPattern))], type: "kotlin.DoubleArray")
        let floats = makeArray([Int(Float(2.5).bitPattern)], type: "kotlin.FloatArray")
        let nested = makeArray([doubles, floats], type: "kotlin.Array")
        expectRendering(nested, "[[1.0], [2.5]]")
        #expect(extractString(from: __kk_array_contentDeepToString(nested)) == "[[1.0], [2.5]]")

        let list = registerRuntimeObject(RuntimeListBox(elements: [doubles, floats]))
        expectRendering(list, "[[1.0], [2.5]]")
    }

    @Test
    func integerArraysAreNotReinterpretedAsFloatingPoint() {
        expectRendering(makeArray([1065353216, -1], type: "kotlin.IntArray"), "[1065353216, -1]")
        expectRendering(makeArray([4607182418800017408, -1], type: "kotlin.LongArray"), "[4607182418800017408, -1]")
        expectRendering(makeArray([1065353216, -1], type: "kotlin.Array"), "[1065353216, -1]")
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
