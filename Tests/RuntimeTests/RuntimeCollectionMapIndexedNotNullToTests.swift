#if canImport(Testing)
import Foundation
import Testing
@testable import Runtime

private let mapIndexedNotNullToEvenIndex: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, value, _ in
    index.isMultiple(of: 2) ? value + index : runtimeNullSentinelInt
}

@Suite
struct RuntimeCollectionMapIndexedNotNullToTests {
    init() {
        kk_runtime_force_reset()
    }

    @Test
    func testMapIndexedNotNullToAppendsOnlyNonNullResults() {
        defer {
            kk_runtime_force_reset()
        }

        let source = makeList([10, 20, 30, 40])
        let destination = makeList([])
        let returned = kk_list_mapIndexedNotNullTo(
            source,
            destination,
            unsafeBitCast(mapIndexedNotNullToEvenIndex, to: Int.self),
            0,
            nil as UnsafeMutablePointer<Int>?
        )

        #expect(returned == destination)
        #expect(listElements(destination) == [10, 32])
    }

    private func makeList(_ elements: [Int]) -> Int {
        registerRuntimeObject(RuntimeListBox(elements: elements))
    }

    private func listElements(_ listRaw: Int) -> [Int] {
        runtimeListBox(from: listRaw)?.elements ?? []
    }
}
#endif
