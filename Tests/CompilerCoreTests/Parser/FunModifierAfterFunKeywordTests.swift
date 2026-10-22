#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct FunModifierAfterFunKeywordTests {
    @Test
    func rejectsModifierWrittenAfterFunKeyword() throws {
        let ctx = makeContextFromSource("""
        fun infix f(x: Int) = x
        fun main() { println(f(1)) }
        """)
        try runFrontend(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-PARSE-0002" }
        #expect(errors.count == 1)
        #expect(errors.first?.message == "Expecting '('.")
    }

    @Test
    func keepsValidInfixDeclaration() throws {
        let ctx = makeContextFromSource("""
        infix fun Int.f(x: Int) = this + x
        fun main() { println(1 f 2) }
        """)
        try runFrontend(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
