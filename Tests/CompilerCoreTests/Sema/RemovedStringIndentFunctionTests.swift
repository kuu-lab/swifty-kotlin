@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// KUU-3420: Kotlin 2.4.20 does not resolve these bundled String extensions.
@Suite
struct RemovedStringIndentFunctionTests {
    @Test
    func removedIndentOverloadsAreUnresolved() throws {
        let ctx = makeContextFromSource("""
        package probe
        fun noArgument(): String = "a".indent()
        fun withArgument(): String = "a".indent(2)
        """)

        do {
            try runSema(ctx)
        } catch {
            // Sema reports errors before throwing; assert both overloads below.
        }

        let unresolvedIndentCalls = ctx.diagnostics.diagnostics.filter {
            $0.severity == .error && $0.message.contains("Unresolved") && $0.message.contains("'indent'")
        }
        #expect(
            unresolvedIndentCalls.count == 2,
            "Expected both removed overloads to be unresolved, got: \(ctx.diagnostics.diagnostics)"
        )

        let sema = try #require(ctx.sema)
        let fqName = ["kotlin", "text", "indent"].map { ctx.interner.intern($0) }
        #expect(sema.symbols.lookupAll(fqName: fqName).isEmpty)
    }
}
