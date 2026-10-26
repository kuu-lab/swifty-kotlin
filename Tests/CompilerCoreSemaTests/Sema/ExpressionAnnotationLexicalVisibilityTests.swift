@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ExpressionAnnotationLexicalVisibilityTests {
    @Test
    func localClassCanUseItsLexicalOwnersPrivateAnnotation() throws {
        let source = """
        class Owner {
            @Target(AnnotationTarget.EXPRESSION)
            @Retention(AnnotationRetention.SOURCE)
            private annotation class Tag
            fun make(): Int {
                class Local { fun value(): Int = @Tag 7 }
                return Local().value()
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let context = try makeExpressionAnnotationContext(inputs: [path])
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        }
    }
}
