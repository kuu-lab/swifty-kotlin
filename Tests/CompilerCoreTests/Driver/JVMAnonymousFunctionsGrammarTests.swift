#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite struct JVMAnonymousFunctionGrammarTests {
    @Test(arguments: [
        "fun value() { val f = fun(x: Int): Int { return x + 1 } }",
        "fun value() { val f = fun(x: Int): Int = x + 1 }",
        "fun value() { val f = fun Int.(): String { return \"OK\" } }",
        "fun value() { val f = fun Int?.(): Int { return 1 } }",
        "fun value() { val f = fun List<Int>.(): Int { return size } }",
        "fun value() { consume(fun(x): Int { return x }) }",
        "fun value() { consume(fun(x: Int) { println(x) }) }",
    ])
    func acceptsAnonymousBodiesAndReceivers(source: String) throws {
        let context = makeContextFromSource(source, emit: .jvmJar)
        try LexPhase().run(context)
        try JVMSourceValidationPhase().run(context)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "fun value() { val f = fun(x: Int) }",
        "fun value() { val f = fun(x: Int): Int }",
        "fun value() { val f = fun named(x: Int): Int = x }",
        "fun value() { val f = fun Int(x: Int): Int = x }",
        "fun value() { val f = fun(x: Int = 1): Int = x }",
        "fun value() { val f = fun(x: Int): Int { return x }",
    ])
    func rejectsInvalidAnonymousFunctions(source: String) throws {
        let context = makeContextFromSource(source, emit: .jvmJar)
        try LexPhase().run(context)
        try JVMSourceValidationPhase().run(context)
        #expect(context.diagnostics.hasError)
    }
}
#endif
