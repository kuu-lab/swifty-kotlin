#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite struct JVMNewlineContinuationGrammarTests {
    @Test(arguments: [
        ("&&", "true"),
        ("||", "false"),
        ("?:", "2"),
        ("as", "Any"),
    ])
    func acceptsLeadingContinuation(op: String, operand: String) throws {
        let context = makeContextFromSource("fun f() { val x = value\n\(op) \(operand) }", emit: .jvmJar)
        try LexPhase().run(context)
        try JVMSourceValidationPhase().run(context)
        #expect(context.errorDiagnostics.isEmpty)
    }

    @Test
    func rejectsLeadingMultiplication() throws {
        let context = makeContextFromSource("fun f() { val x = 1\n* 2 }", emit: .jvmJar)
        try LexPhase().run(context)
        try JVMSourceValidationPhase().run(context)
        #expect(context.errorDiagnostics.map(\.code) == ["KSWIFTK-JVM-0001"])
    }
}
#endif
