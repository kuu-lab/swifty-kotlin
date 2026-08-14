#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct RangeRandomSyntheticLinkTests {
    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner)?

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = (try #require(ctx.sema), ctx.interner)
        }
        let semaResult = try #require(result)
        Self._sharedSema = semaResult
        return semaResult
    }

    @Test
    func testLegacyRangeRandomSyntheticLinksAreGone() throws {
        let (sema, interner) = try sharedSema()
        let rangeTypes = ["IntRange", "LongRange", "CharRange", "UIntRange", "ULongRange"]
        let members = ["random", "randomOrNull"]
        let legacyLinks = [
            "kk_range_random", "kk_range_random_random", "kk_range_randomOrNull", "kk_range_randomOrNull_random",
            "kk_long_range_random", "kk_long_range_random_random", "kk_long_range_randomOrNull", "kk_long_range_randomOrNull_random",
            "kk_char_range_random", "kk_char_range_random_random", "kk_char_range_randomOrNull", "kk_char_range_randomOrNull_random",
            "kk_uint_range_random", "kk_uint_range_random_random", "kk_uint_range_randomOrNull", "kk_uint_range_randomOrNull_random",
            "kk_ulong_range_random", "kk_ulong_range_random_random", "kk_ulong_range_randomOrNull", "kk_ulong_range_randomOrNull_random",
        ]

        for typeName in rangeTypes {
            for member in members {
                let fqName = ["kotlin", "ranges", typeName, member].map { interner.intern($0) }
                let symbols = sema.symbols.lookupAll(fqName: fqName)
                #expect(
                    symbols.allSatisfy { symbol in
                        guard let link = sema.symbols.externalLinkName(for: symbol) else { return true }
                        return !legacyLinks.contains(link)
                    },
                    "(typeName).(member) must not retain a legacy synthetic runtime link"
                )
            }
        }
    }
}
#endif
