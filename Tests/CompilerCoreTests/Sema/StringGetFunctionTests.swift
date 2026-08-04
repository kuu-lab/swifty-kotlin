@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-018: Validates that `String.get(index)` operator resolves
/// through Sema for `String` receivers, dispatching to the runtime link name
/// `kk_string_get`.
@Suite
struct StringGetFunctionTests {
    @Test func testGetResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun firstChar(s: String): Char {
            return s.get(0)
        }

        fun charAt(s: String, i: Int): Char {
            return s[i]
        }

        fun firstOfHello(): Char {
            return "hello".get(0)
        }

        fun secondOfHello(): Char {
            return "hello"[1]
        }
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected String.get/indexed access to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
