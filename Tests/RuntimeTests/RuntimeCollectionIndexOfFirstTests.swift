#if canImport(Testing)
@testable import Runtime
import Testing

private let isEvenForIndexOfFirst: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value % 2 == 0 ? 1 : 0
}

@Suite
struct RuntimeCollectionIndexOfFirstTests {
    @Test
    func testListIndexOfFirstFindsPredicateMatchAndMissingElement() {
        let mixed = registerRuntimeObject(RuntimeListBox(elements: [1, 3, 4, 6]))
        let odds = registerRuntimeObject(RuntimeListBox(elements: [1, 3, 5]))
        let predicate = unsafeBitCast(isEvenForIndexOfFirst, to: Int.self)

        #expect(kk_list_indexOfFirst(mixed, predicate, 0, nil) == 2)
        #expect(kk_list_indexOfFirst(odds, predicate, 0, nil) == -1)
    }
}
#endif
