@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-SYSTEM-FN-004: `fun getTimeNanos(): Long` in kotlin.system.
///
/// Verifies the function resolves cleanly when imported in a source file.
@Suite
struct SystemGetTimeNanosFunctionTests {
    @Test
    func testGetTimeNanosFunctionResolvesInSource() throws {
        let source = """
        import kotlin.system.getTimeNanos

        fun now(): Long {
            return getTimeNanos()
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
                "Expected kotlin.system.getTimeNanos to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try #require(ctx.sema)
            let fq = ["kotlin", "system", "getTimeNanos"].map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: fq)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                links.contains("kk_system_getTimeNanos"),
                "kotlin.system.getTimeNanos must link to kk_system_getTimeNanos; got: \(links)"
            )
        }
    }
}
