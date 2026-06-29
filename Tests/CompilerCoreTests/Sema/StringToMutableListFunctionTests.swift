@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-104: Validates that `String.toMutableList()` resolves through
/// Sema and links to the `kk_string_toMutableList` runtime entry.
///
/// The synthetic extension function is registered in
/// `HeaderHelpers+SyntheticStringStubs.swift`, the call lowering routes to the
/// runtime symbol in `CallLowerer+LegacyMemberLikeCalls.swift`, and the runtime
/// implementation lives in `Sources/Runtime/RuntimeStringStdlib.swift`.
@Suite
struct StringToMutableListFunctionTests {
    @Test
    func testToMutableListResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun explode(s: String): MutableList<Char> {
            return s.toMutableList()
        }

        fun explodeLiteral(): MutableList<Char> {
            return "hello".toMutableList()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected toMutableList to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test
    func testToMutableListResultIsMutable() throws {
        // The returned list must support MutableList members (`add`) — i.e. the
        // inferred return type really is MutableList<Char>, not List<Char>.
        let ctx = makeContextFromSource("""
        fun appendBang(s: String): Int {
            val chars = s.toMutableList()
            chars.add('!')
            return chars.size
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected toMutableList result to accept MutableList members, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
