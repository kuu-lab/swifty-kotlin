#if canImport(Testing)
import Foundation
import Testing
@testable import Runtime

@Suite(.serialized, .runtimeIsolation(.gcOnly))
struct RuntimeArithmeticOverflowTrapTests {
    private func makeList(_ elements: [Int]) -> Int {
        registerRuntimeObject(RuntimeListBox(elements: elements))
    }

    private func extractElements(_ raw: Int) -> [Int] {
        runtimeCollectionOrArrayElements(from: raw) ?? []
    }

    private func extractListOfLists(_ raw: Int) -> [[Int]] {
        let outer = extractElements(raw)
        return outer.map { extractElements($0) }
    }

    private func sequenceToListOfLists(_ seqRaw: Int) -> [[Int]] {
        var thrown = 0
        let listRaw = kk_sequence_to_list(seqRaw, &thrown)
        #expect(thrown == 0)
        return extractListOfLists(listRaw)
    }

    @Test
    func testListChunkedWithExtremeSizeDoesNotTrap() {
        let list = makeList([1, 2, 3, 4, 5])

        // size = Int.max -> single chunk containing all elements
        var thrown = 0
        let maxChunked = kk_list_bridge_chunked(list, Int.max, &thrown)
        #expect(thrown == 0)
        let maxChunks = extractListOfLists(maxChunked)
        #expect(maxChunks.count == 1)
        #expect(maxChunks.first == [1, 2, 3, 4, 5])

        // size = Int.min -> IllegalArgumentException instead of a trap
        thrown = 0
        _ = kk_list_bridge_chunked(list, Int.min, &thrown)
        #expect(thrown != 0)
    }

    @Test
    func testListChunkedTransformWithExtremeSizeDoesNotTrap() {
        let list = makeList([10, 20, 30])
        var thrown = 0

        let identityTransform: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, chunkRaw, _ in
            chunkRaw
        }
        let fnPtr = unsafeBitCast(identityTransform, to: Int.self)

        let resMax = kk_list_bridge_chunked_transform(list, Int.max, fnPtr, 0, &thrown)
        #expect(thrown == 0)
        let maxChunks = extractListOfLists(resMax)
        #expect(maxChunks.count == 1)
        #expect(maxChunks.first == [10, 20, 30])

        thrown = 0
        _ = kk_list_bridge_chunked_transform(list, Int.min, fnPtr, 0, &thrown)
        #expect(thrown != 0)
    }

    @Test
    func testListWindowedWithExtremeSizeAndStepDoesNotTrap() {
        let list = makeList([1, 2, 3, 4, 5])

        var thrown = 0

        // size = Int.max, step = Int.max, partialWindows = false -> empty
        let emptyWin = kk_list_bridge_windowed(list, Int.max, Int.max, 0, &thrown)
        #expect(thrown == 0)
        #expect(extractListOfLists(emptyWin).isEmpty)

        // size = Int.max, step = Int.max, partialWindows = true -> single window with all elements
        thrown = 0
        let partialWin = kk_list_bridge_windowed(list, Int.max, Int.max, 1, &thrown)
        #expect(thrown == 0)
        let partialWindows = extractListOfLists(partialWin)
        #expect(partialWindows.count == 1)
        #expect(partialWindows.first == [1, 2, 3, 4, 5])

        // size = 2, step = Int.max -> 1 window
        thrown = 0
        let stepMaxWin = kk_list_bridge_windowed(list, 2, Int.max, 0, &thrown)
        #expect(thrown == 0)
        let stepMaxWindows = extractListOfLists(stepMaxWin)
        #expect(stepMaxWindows.count == 1)
        #expect(stepMaxWindows.first == [1, 2])
    }

    @Test
    func testListWindowedTransformWithExtremeValuesDoesNotTrap() {
        let list = makeList([1, 2, 3])
        var thrown = 0

        let identityTransform: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, winRaw, _ in
            winRaw
        }
        let fnPtr = unsafeBitCast(identityTransform, to: Int.self)

        let res = kk_list_bridge_windowed_transform(list, Int.max, Int.max, 1, fnPtr, 0, &thrown)
        #expect(thrown == 0)
        let windows = extractListOfLists(res)
        #expect(windows.count == 1)
        #expect(windows.first == [1, 2, 3])
    }

    @Test
    func testRangeWindowedWithExtremeSizeAndStepDoesNotTrap() {
        let rangeBox = registerRuntimeObject(RuntimeRangeBox(first: 1, last: 5, step: 1))
        var thrown = 0

        // size = Int.max, step = Int.max, partial = false -> empty
        let emptyWin = kk_range_windowed(rangeBox, Int.max, Int.max, 0, &thrown)
        #expect(thrown == 0)
        #expect(extractListOfLists(emptyWin).isEmpty)

        // size = Int.max, step = Int.max, partial = true -> 1 window [1, 2, 3, 4, 5]
        let partialWin = kk_range_windowed(rangeBox, Int.max, Int.max, 1, &thrown)
        #expect(thrown == 0)
        let windows = extractListOfLists(partialWin)
        #expect(windows.count == 1)
        #expect(windows.first == [1, 2, 3, 4, 5])
    }

    @Test
    func testSequenceWindowedAndChunkedWithExtremeValuesDoesNotTrap() {
        let seq = registerRuntimeObject(RuntimeSequenceBox(steps: [.source(elements: [1, 2, 3, 4, 5])]))

        // chunked with Int.max
        let chunkedRaw = kk_sequence_chunked(seq, Int.max)
        let chunkLists = sequenceToListOfLists(chunkedRaw)
        #expect(chunkLists.count == 1)
        #expect(chunkLists.first == [1, 2, 3, 4, 5])

        // windowed with Int.max, Int.max, partial = false
        let winEmptyRaw = kk_sequence_windowed(seq, Int.max, Int.max, 0)
        let winEmptyLists = sequenceToListOfLists(winEmptyRaw)
        #expect(winEmptyLists.isEmpty)

        // windowed with Int.max, Int.max, partial = true
        let winPartialRaw = kk_sequence_windowed(seq, Int.max, Int.max, 1)
        let winLists = sequenceToListOfLists(winPartialRaw)
        #expect(winLists.count == 1)
        #expect(winLists.first == [1, 2, 3, 4, 5])

        // windowed with size = 2, step = Int.max, partial = false
        let winStepMaxRaw = kk_sequence_windowed(seq, 2, Int.max, 0)
        let winStepMaxLists = sequenceToListOfLists(winStepMaxRaw)
        #expect(winStepMaxLists.count == 1)
        #expect(winStepMaxLists.first == [1, 2])
    }
}
#endif
