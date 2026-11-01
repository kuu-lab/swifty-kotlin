@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// KUU-2813: opt-in `reachability-sema` skips body analysis for top-level
/// functions that are not (lexically) reachable from `main`.
struct TopLevelFunctionReachabilityTests {
    private static let source = """
    fun used(x: Int): Int = helper(x) + 1
    fun helper(x: Int): Int = x
    operator fun Int.unaryPlus(): Int = this
    fun overloaded(x: Int): Int = x
    fun overloaded(x: String): Int = 0
    fun unused(x: Int): Int {
        val s: String = x
        return 0
    }
    fun main() {
        println(used(41) + overloaded(1))
    }
    """

    private func semaDiagnosticCodes(flags: [String], emit: EmitMode = .executable) throws -> (codes: [String], skipped: Int) {
        let ctx = makeContextFromSource(Self.source, frontendFlags: flags, emit: emit)
        try runSema(ctx)
        return (ctx.diagnostics.diagnostics.map(\.code), ctx.sema?.unreachableTopLevelFunctionDecls.count ?? -1)
    }

    @Test
    func deadCodeBodyIsNotCheckedWhenFlagEnabled() throws {
        let off = try semaDiagnosticCodes(flags: [])
        #expect(off.codes.contains("KSWIFTK-SEMA-0468"))
        #expect(off.skipped == 0)

        let on = try semaDiagnosticCodes(flags: ["reachability-sema"])
        #expect(!on.codes.contains("KSWIFTK-SEMA-0468"))
        // Only `unused` is skipped: `used`/`helper`/`overloaded` are reachable
        // by name and the `operator` function is a root.
        #expect(on.skipped == 1)
    }

    @Test
    func nonExecutableEmitKeepsAllBodies() throws {
        let result = try semaDiagnosticCodes(flags: ["reachability-sema"], emit: .library)
        #expect(result.codes.contains("KSWIFTK-SEMA-0468"))
        #expect(result.skipped == 0)
    }
}
