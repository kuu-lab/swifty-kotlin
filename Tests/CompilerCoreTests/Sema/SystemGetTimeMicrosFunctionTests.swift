@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-SYSTEM-FN-002: `fun getTimeMicros(): Long` in kotlin.system.
///
/// Verifies the function resolves cleanly when imported in a source file.
@Suite
struct SystemGetTimeMicrosFunctionTests {
    @Test
    func testGetTimeMicrosFunctionResolvesInSource() throws {
        let source = """
        import kotlin.system.getTimeMicros

        fun now(): Long {
            return getTimeMicros()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(
                !(ctx.diagnostics.hasError),
                "Expected kotlin.system.getTimeMicros to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try #require(ctx.sema)
            let fq = ["kotlin", "system", "getTimeMicros"].map { ctx.interner.intern($0) }
            #expect(
                !sema.symbols.lookupAll(fqName: fq).isEmpty,
                "kotlin.system.getTimeMicros must be declared in bundled Kotlin source"
            )
            // KSP-617: the public API is Kotlin source; only the private bridge
            // carries the runtime link name.
            let bridgeLinks = Set(
                sema.symbols.allSymbols()
                    .compactMap { sema.symbols.externalLinkName(for: $0.id) }
            )
            #expect(
                bridgeLinks.contains("__kk_system_getTimeMicros"),
                "kotlin.system.getTimeMicros must be backed by __kk_system_getTimeMicros; got: \(bridgeLinks.filter { $0.hasPrefix("__kk_system_") })"
            )
        }
    }
}
