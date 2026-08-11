@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-SYSTEM-FN-003: `fun getTimeMillis(): Long` in kotlin.system.
///
/// Verifies the function resolves cleanly when imported in a source file.
@Suite
struct SystemGetTimeMillisFunctionTests {
    @Test
    func testGetTimeMillisFunctionResolvesInSource() throws {
        let source = """
        import kotlin.system.getTimeMillis

        fun now(): Long {
            return getTimeMillis()
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
                "Expected kotlin.system.getTimeMillis to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try #require(ctx.sema)
            let fq = ["kotlin", "system", "getTimeMillis"].map { ctx.interner.intern($0) }
            #expect(
                !sema.symbols.lookupAll(fqName: fq).isEmpty,
                "kotlin.system.getTimeMillis must be declared in bundled Kotlin source"
            )
            // KSP-617: the public API is Kotlin source; only the private bridge
            // carries the runtime link name.
            let bridgeLinks = Set(
                sema.symbols.allSymbols()
                    .compactMap { sema.symbols.externalLinkName(for: $0.id) }
            )
            #expect(
                bridgeLinks.contains("__kk_system_getTimeMillis"),
                "kotlin.system.getTimeMillis must be backed by __kk_system_getTimeMillis; got: \(bridgeLinks.filter { $0.hasPrefix("__kk_system_") })"
            )
        }
    }
}
