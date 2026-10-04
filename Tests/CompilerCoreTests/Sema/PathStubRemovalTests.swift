#if canImport(Testing)
@testable import CompilerCore
import Testing

/// CLEANUP-STUB-116 first removed the `kotlin.io.path` generic function stubs
/// (`useLines`, `useDirectoryEntries`, `readAttributes<A>`,
/// `fileAttributesView<V>`, `fileAttributesViewOrNull<V>`). CLEANUP-STUB-115
/// then removed `HeaderHelpers+SyntheticPathStubs.swift` entirely: the bare
/// `kotlin.io.path.Path` shell, its related `java.nio.file`/`kotlin.io.path`
/// scaffolding (`PathWalkOption`, `OnErrorResult`, `CopyActionResult`,
/// `CopyActionContext`, `FileVisitorBuilder`, `ExperimentalPathApi`,
/// `StandardOpenOption`, ...), and the `kotlin.io.path` package itself are no
/// longer registered by Sema.
@Suite
struct PathStubRemovalTests {

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
    private static let fixture = SemaFixture(surface: "Path stub removal")

    private func sharedSema(
        sourceLocation: Testing.SourceLocation = #_sourceLocation
    ) throws -> (SemaModule, StringInterner) {
        try Self.fixture.shared(sourceLocation: sourceLocation)
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
        #expect(ctx.diagnostics.hasError, "kotlin.io.path.Path should no longer resolve")
    }

    @Test func testPathShellAndDependentSymbolsAreNotRegistered() throws {
        let (sema, interner) = try sharedSema()
        let removedFQNames = [
            ["kotlin", "io", "path", "Path"],
            ["kotlin", "io", "path", "PathWalkOption"],
            ["kotlin", "io", "path", "PathWalkOption", "BREADTH_FIRST"],
            ["kotlin", "io", "path", "OnErrorResult"],
            ["kotlin", "io", "path", "CopyActionResult"],
            ["kotlin", "io", "path", "CopyActionContext"],
            ["kotlin", "io", "path", "FileVisitorBuilder"],
            ["kotlin", "io", "path", "ExperimentalPathApi"],
            ["java", "nio", "file", "StandardOpenOption"],
            ["java", "nio", "file", "CopyOption"],
            ["java", "nio", "file", "OpenOption"],
            ["java", "nio", "file", "LinkOption"],
            ["java", "nio", "file", "FileStore"],
            ["java", "nio", "file", "FileVisitor"],
            ["java", "nio", "file", "attribute", "FileAttribute"],
            ["java", "nio", "file", "attribute", "FileAttributeView"],
            ["java", "nio", "file", "attribute", "BasicFileAttributes"],
            ["java", "nio", "file", "attribute", "UserPrincipal"],
            ["java", "nio", "file", "attribute", "PosixFilePermission"],
        ]
        for fqName in removedFQNames {
            let symbol = sema.symbols.lookup(fqName: fqName.map(interner.intern))
            #expect(symbol == nil, Comment(rawValue: "\(fqName.joined(separator: ".")) should no longer be registered"))
        }
    }

    @Test func testKotlinIOPathPackageIsNoLongerRegistered() throws {
        let (sema, interner) = try sharedSema()
        let fqName = ["kotlin", "io", "path"].map { interner.intern($0) }
        #expect(
            sema.symbols.lookup(fqName: fqName) == nil,
            "kotlin.io.path package should no longer be registered now that Path's synthetic stubs are removed"
        )
    }
}
#endif
