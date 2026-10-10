#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing
import TestStdlibCache

@Suite
struct ExplicitImportResolutionTests {
    @Test
    func unusedUnresolvedExplicitImportsAreDiagnosed() throws {
        let source = try repositoryFileSource(
            "docs/fixtures/js_annotations/diagnostics/collection_imports.kt"
        )
        let ctx = makeContextFromSource(source, allowDefaultStdlibLibrary: false)
        try runSema(ctx)

        let unresolvedImports = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-0024"
        }
        #expect(unresolvedImports.count == 3, "Expected all three unused imports to be rejected: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func unresolvedMemberImportIsDiagnosedEvenWhenMemberIsUsed() throws {
        let source = """
        @file:OptIn(kotlin.js.ExperimentalJsExport::class, kotlin.js.ExperimentalJsCollectionsApi::class)
        import kotlin.js.collections.asJsMapView
        fun use(values: MutableMap<String, Int>) {
            values.asJsMapView()
        }
        """
        let ctx = makeContextFromSource(source, allowDefaultStdlibLibrary: false)
        try runSema(ctx)

        let importErrors = ctx.diagnostics.diagnostics.filter {
            $0.severity == .error && $0.message == "Unresolved import path."
        }
        #expect(importErrors.count == 1, "Expected the unused-as-import error while the member call still resolves: \(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [false, true])
    func nestedMemberAndExtensionImportsResolve(useArtifact: Bool) throws {
        if useArtifact {
            TestStdlibCache.shared.prepare()
        }

        let source = """
        import kotlin.collections.Map.Entry
        import kotlin.collections.Map.Entry as MapEntry
        import kotlin.ranges.isEmpty

        fun identity(entry: Entry<String, Int>): Entry<String, Int> = entry
        fun identityAlias(entry: MapEntry<String, Int>): MapEntry<String, Int> = entry
        fun isEmpty(range: IntRange): Boolean = range.isEmpty()
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                allowDefaultStdlibLibrary: useArtifact
            )
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test(arguments: ["import importfixture.library.*", "import importfixture.library"])
    func sourcePackageImportFallbackStillContributesMembers(importDirective: String) throws {
        let sources = [
            """
            package importfixture.library
            class Token
            fun token(): Token = Token()
            """,
            """
            package importfixture.app
            \(importDirective)
            fun use(): Token = token()
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, allowDefaultStdlibLibrary: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func wildcardImportResolvesPrecompiledLibraryPackage() throws {
        TestStdlibCache.shared.prepare()
        let source = """
        import kotlin.ranges.*
        fun isEmpty(range: IntRange): Boolean = range.isEmpty()
        """
        let ctx = makeContextFromSource(
            source,
            allowDefaultStdlibLibrary: true
        )
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
