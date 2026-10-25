#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct StringReplaceOverloadShapeTests {
    @Test
    func rejectsMixedCharAndStringArguments() throws {
        let ctx = makeContextFromSource("""
        fun invalid(): String = "aXb".replace('X', "Y")
        fun replaceStrings(): String = "aXb".replace("X", "Y")
        fun replaceChars(): String = "aXb".replace('X', 'Y')
        """)

        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(!errors.isEmpty, "Expected replace(Char, String) to be rejected")
        #expect(errors.count == 1, "Expected valid String/String and Char/Char controls to remain accepted: \(errors.map { "\($0.code): \($0.message)" })")
    }
}
#endif
