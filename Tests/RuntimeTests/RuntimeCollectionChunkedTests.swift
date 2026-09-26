#if canImport(Testing)
@testable import Runtime
import Testing

@Suite(.serialized)
struct RuntimeCollectionChunkedTests {
    @Test
    func testChunkedRejectsNonPositiveSizes() {
        let source = makeList([1, 2, 3])

        for size in [0, -2] {
            var thrown = 0
            let result = kk_list_bridge_chunked(source, size, &thrown)

            #expect(result == runtimeExceptionCaughtSentinel)
            let throwable = throwableBox(from: thrown)
            #expect(throwable?.exceptionFQName == "kotlin.IllegalArgumentException")
            #expect(throwable?.message == "size must be positive, but was \(size)")
        }
    }

    @Test
    func testChunkedTransformRejectsNonPositiveSizesBeforeInvokingTransform() {
        let source = makeList([1, 2, 3])

        for size in [0, -2] {
            var thrown = 0
            let result = kk_list_bridge_chunked_transform(source, size, 0, 0, &thrown)

            #expect(result == runtimeExceptionCaughtSentinel)
            let throwable = throwableBox(from: thrown)
            #expect(throwable?.exceptionFQName == "kotlin.IllegalArgumentException")
            #expect(throwable?.message == "size must be positive, but was \(size)")
        }
    }

    private func makeList(_ elements: [Int]) -> Int {
        let arrayRaw = kk_array_new(elements.count)
        for (index, value) in elements.enumerated() {
            var thrown = 0
            _ = kk_array_set(arrayRaw, index, value, &thrown)
            #expect(thrown == 0)
        }
        return kk_list_of(arrayRaw, elements.count)
    }

    private func throwableBox(from handle: Int) -> RuntimeThrowableBox? {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
            return nil
        }
        return tryCast(ptr, to: RuntimeThrowableBox.self)
    }
}
#endif
