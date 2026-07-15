#if canImport(Testing)
@testable import Runtime
import Testing

private let isEvenForIndexOfLast: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value % 2 == 0 ? 1 : 0
}

@Suite
struct RuntimeCollectionIndexOfLastTests {
    @Test
    func testListIndexOfLastFindsPredicateMatchAndMissingElement() {
        let mixed = registerRuntimeObject(RuntimeListBox(elements: [1, 4, 5, 6]))
        let odds = registerRuntimeObject(RuntimeListBox(elements: [1, 3, 5]))
        let predicate = unsafeBitCast(isEvenForIndexOfLast, to: Int.self)

        #expect(kk_list_indexOfLast(mixed, predicate, 0, nil) == 3)
        #expect(kk_list_indexOfLast(odds, predicate, 0, nil) == -1)
    }
}
#endif
