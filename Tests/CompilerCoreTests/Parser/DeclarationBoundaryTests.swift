#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// BUG-208 (found while implementing KSP-614): a body-less top-level
/// declaration — such as the `external fun` bridges used by the bundled Kotlin
/// stdlib — used to absorb the following declaration when that declaration
/// started with a visibility/linkage modifier, because only `fun`/`val`/`class`
/// and friends were treated as statement boundaries.  The absorbed declaration
/// disappeared from the symbol table entirely (calls to it failed with
/// `KSWIFTK-SEMA-0002` / `KSWIFTK-SEMA-0023`).
@Suite
struct DeclarationBoundaryTests {
    private func funDeclCount(_ source: String) -> Int {
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()
        let lexer = KotlinLexer(
            file: FileID(rawValue: 0),
            source: Data(source.utf8),
            interner: interner,
            diagnostics: diagnostics
        )
        let parser = KotlinParser(tokens: lexer.lexAll(), interner: interner, diagnostics: diagnostics)
        let parsed = parser.parseFile()
        return parsed.arena.nodes.count { $0.kind == .funDecl }
    }

    @Test
    func testBodylessFunctionDoesNotAbsorbFollowingModifiedDeclaration() {
        let source = """
        external fun bridge(message: Any?)

        public fun first() {
            bridge("first")
        }

        public fun second() {
            bridge("second")
        }
        """
        #expect(funDeclCount(source) == 3)
    }

    @Test
    func testExpressionBodiedPropertyDoesNotAbsorbFollowingModifiedDeclaration() {
        let source = """
        val answer = 42

        private fun helper(): Int = answer
        """
        #expect(funDeclCount(source) == 1)
    }
}
#endif
