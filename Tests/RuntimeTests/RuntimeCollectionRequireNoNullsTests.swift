#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeCollectionRequireNoNullsTests {
    @Test
    func testIterableRequireNoNullsReturnsOriginalCollectionWhenAllElementsArePresent() {
        let source = makeList([1, 2, 3])
        var thrown = 0

        let result = kk_iterable_requireNoNulls(source, &thrown)

        #expect(result == source)
        #expect(thrown == 0)
    }

    @Test
    func testIterableRequireNoNullsThrowsForNullElement() {
        let source = makeList([runtimeStringRaw("a"), runtimeNullSentinelInt])
        var thrown = 0

        let result = kk_iterable_requireNoNulls(source, &thrown)

        #expect(result == runtimeExceptionCaughtSentinel)
        #expect(thrown != 0)
        let throwable = throwableBox(from: thrown)
        #expect(throwable?.message == "null element found in collection.")
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

    private func runtimeStringRaw(_ value: String) -> Int {
        value.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: max(1, value.utf8.count)) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(value.utf8.count)))
            }
        }
    }

    private func throwableBox(from handle: Int) -> RuntimeThrowableBox? {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
            return nil
        }
        return tryCast(ptr, to: RuntimeThrowableBox.self)
    }
}
#endif
