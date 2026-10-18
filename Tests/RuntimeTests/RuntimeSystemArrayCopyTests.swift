#if canImport(Testing)
import RuntimeABI
import Testing
@testable import Runtime

/// The backend declares every runtime extern as returning `i64`, so
/// `System.arraycopy` (a `Unit` external) must return a word on every path.
/// The success and throwing paths all return 0; only `outThrown` differs.
@Suite(.serialized)
struct RuntimeSystemArrayCopyTests {
    /// Tagged as `IntArray` so the copy needs no reference-array component
    /// descriptor; an untagged `kk_array_new` array rejects non-null stores.
    private func makeArray(_ elements: [Int]) -> Int {
        let arrayRaw = kk_array_new(elements.count)
        _ = kk_array_tag_type(arrayRaw, Int(runtimeStableNominalTypeID(fqName: "kotlin.IntArray")))
        var thrown = 0
        for (index, element) in elements.enumerated() {
            _ = kk_array_set(arrayRaw, index, element, &thrown)
            #expect(thrown == 0)
        }
        return arrayRaw
    }

    private func element(_ arrayRaw: Int, _ index: Int) -> Int {
        var thrown = 0
        let value = kk_array_get(arrayRaw, index, &thrown)
        #expect(thrown == 0)
        return value
    }

    @Test
    func arraycopyExportIsRegisteredAsWordReturningUnitExternal() throws {
        let spec = try #require(RuntimeABISpec.allFunctions.first { $0.name == "__kk_system_arraycopy" })
        #expect(spec.returnType == .intptr)
        #expect(spec.isThrowing)
    }

    @Test
    func successfulCopyReturnsZeroAndLeavesThrownChannelClear() {
        let source = makeArray([10, 20, 30])
        let destination = makeArray([1, 2, 3, 4])
        var thrown = -1

        let result = kk_system_arraycopy(source, 1, destination, 2, 2, &thrown)

        #expect(result == 0)
        #expect(thrown == 0)
        #expect((0 ..< 4).map { element(destination, $0) } == [1, 2, 20, 30])
    }

    @Test
    func nullSourceReturnsZeroAndSetsNullPointerException() throws {
        let destination = makeArray([1])
        var thrown = 0

        let result = kk_system_arraycopy(runtimeNullSentinelInt, 0, destination, 0, 1, &thrown)

        #expect(result == 0)
        let box = try requireThrownBox(thrown)
        #expect(box.exceptionFQName == "kotlin.NullPointerException")
    }

    @Test
    func outOfRangeCopyReturnsZeroAndSetsIndexException() throws {
        let source = makeArray([1, 2])
        let destination = makeArray([0, 0])
        var thrown = 0

        let result = kk_system_arraycopy(source, 1, destination, 0, 2, &thrown)

        #expect(result == 0)
        let box = try requireThrownBox(thrown)
        #expect(box.exceptionFQName == "kotlin.ArrayIndexOutOfBoundsException")
    }
}
#endif
