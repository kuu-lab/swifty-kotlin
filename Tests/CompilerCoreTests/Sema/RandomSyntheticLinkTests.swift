#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct RandomSyntheticLinkTests {
    func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            result = (sema, ctx.interner)
        }
        return try #require(result)
    }

    // MIGRATION-RANDOM-001: nextLong / nextFloat / nextDouble / nextBoolean / nextInt
    // are migrated to Kotlin source. Their synthetic stubs are removed.
    // Tests for those stub-specific external links were deleted in this migration.
}
#endif
