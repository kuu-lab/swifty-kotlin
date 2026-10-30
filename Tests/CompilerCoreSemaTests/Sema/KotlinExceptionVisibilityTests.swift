import CompilerCore
@testable import CompilerTestSupport
import Testing
import TestStdlibCache

@Suite
struct KotlinExceptionVisibilityTests {
    private func context(_ source: String, useArtifact: Bool) throws -> CompilationContext {
        if useArtifact { TestStdlibCache.shared.prepare() }
        let ctx = makeContextFromSource(
            source,
            emit: useArtifact ? .executable : .kirDump,
            allowDefaultStdlibLibrary: useArtifact
        )
        if useArtifact {
            _ = try #require(ctx.options.stdlibLibraryPath, "Expected the prebuilt stdlib artifact")
        }
        try runSema(ctx)
        return ctx
    }

    @Test(arguments: [false, true])
    func deprecatedNullPointerAliasRemainsUsable(useArtifact: Bool) throws {
        let ctx = try context("fun probe(): NullPointerException = KotlinNullPointerException()", useArtifact: useArtifact)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [false, true], [
        "fun probe() { KotlinNothingValueException() }",
        "fun probe(value: KotlinNothingValueException) {}",
    ])
    func nothingValueExceptionIsInternal(useArtifact: Bool, source: String) throws {
        let ctx = try context(source, useArtifact: useArtifact)
        #expect(ctx.diagnostics.diagnostics.contains {
            $0.severity == .error && $0.code == "KSWIFTK-SEMA-0044"
        }, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [false, true])
    func suppressedInternalAccessRemainsAvailable(useArtifact: Bool) throws {
        let ctx = try context("""
        @file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
        fun probe(): Throwable = KotlinNothingValueException("message")
        """, useArtifact: useArtifact)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
