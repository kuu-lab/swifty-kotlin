#if canImport(Testing)
@testable import CompilerCore
import Testing

/// CLEANUP-STUB-116: the `kotlin.io.path` generic function stubs (`useLines`,
/// `useDirectoryEntries`, `readAttributes<A>`, `fileAttributesView<V>`,
/// `fileAttributesViewOrNull<V>`) are no longer registered by Sema.
@Suite
struct PathGenericFunctionStubRemovalTests {

    // MARK: - Shared Sema context

    private static let sharedSources: [String] = [
        """
        package sample0
        import kotlin.io.path.Path
        import kotlin.io.path.useLines

        fun main() {
            val path = Path("/dev/null")
            val count: Int = path.useLines { lines ->
                lines.count()
            }
            println(count)
        }
        """
    ]

    private static nonisolated(unsafe) var _sharedCtx: CompilationContext?

    private func sharedCtx() throws -> CompilationContext {
        if let cached = Self._sharedCtx { return cached }
        var result: CompilationContext?
        try withTemporaryFiles(contents: Self.sharedSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        Self._sharedCtx = ctx
        return ctx
    }
    private static let fixture = SemaFixture(surface: "Path generic function stubs")

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        try Self.fixture.shared()
    }

    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        try Self.fixture.make(source: source)
    }

    @Test func testRemovedPathGenericFunctionStubsAreNotRegistered() throws {
        let (sema, interner) = try sharedSema()
        let removedNames = [
            ["kotlin", "io", "path", "Path", "useLines"],
            ["kotlin", "io", "path", "useDirectoryEntries"],
            ["kotlin", "io", "path", "fileAttributesView"],
            ["kotlin", "io", "path", "fileAttributesViewOrNull"],
        ]
        for fqName in removedNames {
            let symbols = sema.symbols.lookupAll(fqName: fqName.map(interner.intern))
            #expect(symbols.isEmpty, Comment(rawValue: "\(fqName.joined(separator: ".")) should no longer be registered"))
        }
    }

    @Test func testPathUseLinesCallIsRejected() throws {

        let ctx = try sharedCtx()
            #expect(ctx.diagnostics.hasError, "Path.useLines should no longer resolve")

    }
}
#endif
