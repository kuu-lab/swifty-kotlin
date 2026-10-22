#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct DeclarationNameQuestionParsingTests {
    @Test(arguments: [
        "val x? = 5",
        "var x? = 5",
        "fun main() { val x? = 5 }",
        "class Box { val x? = 5 }",
        "val x?: Int",
        "fun f(x?: Int) {}",
        "fun f(x? : Int) {}",
        "class Box(x?: Int)",
    ])
    func rejectsQuestionMarkImmediatelyAfterDeclarationName(_ source: String) throws {
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)
        let diagnostics = context.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-PARSE-0019"
        }

        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.severity == .error)
    }

    @Test
    func nullableTypeAndReceiverQuestionMarksRemainValid() throws {
        let source = """
        val value: Int? = null
        fun f(value: Int?) {}
        val String?.label: Int get() = 1
        """
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)

        #expect(!context.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-PARSE-0019" })
    }
}
#endif
