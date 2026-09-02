#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-991: Iterable.shuffled is bundled Kotlin source and owns its Random import
/// in the same virtual unit. This prevents a synthetic Random placeholder from
/// masking an invalid source file.
@Suite
struct IterableShuffledSourceMigrationTests {
    @Test
    func bundledIterableSourceOwnsRandomImport() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runFrontend(ctx)

        let ast = try #require(ctx.ast)
        let iterableFile = try #require(
            ast.files.first {
                ctx.sourceManager.path(of: $0.fileID) == "__bundled_kotlin/collections/Iterables.kt"
            }
        )
        let randomImport = iterableFile.imports.first {
            $0.path.map(ctx.interner.resolve) == ["kotlin", "random", "Random"]
        }
        #expect(
            randomImport != nil,
            "Iterables.kt must explicitly import kotlin.random.Random in its own virtual unit"
        )
    }
}
#endif
