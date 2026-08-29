@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.metadataOnly))
struct RuntimeEnumTests {
    @Test
    func emptyEnumEntriesUseDistinctStableCacheKeys() {
        let firstEnumID = 91_001
        let secondEnumID = 91_002

        let firstEntries = kk_enum_make_entries_list(kk_array_new(0), 0, firstEnumID)
        let firstEntriesAgain = kk_enum_make_entries_list(kk_array_new(0), 0, firstEnumID)
        let secondEntries = kk_enum_make_entries_list(kk_array_new(0), 0, secondEnumID)

        #expect(firstEntries == firstEntriesAgain)
        #expect(firstEntries != secondEntries)
    }
}
