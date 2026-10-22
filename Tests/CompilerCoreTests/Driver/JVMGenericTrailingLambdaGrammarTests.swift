#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite struct JVMGenericTrailingLambdaGrammarTests {
    @Test(arguments: [
        "fun main() { consume<Int> { 1 } }",
        "fun main() { consume<Int, String> { \"value\" } }",
        "fun main() { receiver.consume<Int> { 1 } }",
        "fun main() { consume<Int> label@ { return@label 1 } }",
        "fun main() { consume<Int>() label@ { return@label 1 } }",
        "fun main() { consume<Int> { return@consume 1 } }",
        "fun main() { consume<Int> { return 1 } }",
        "fun main() { println(1 < 2); println(3 > 2); println(1 < 2 && 3 > 2) }",
    ])
    func acceptsExplicitArgumentsAndComparisonControls(source: String) throws {
        let context = makeContextFromSource(source, emit: .jvmJar)
        try LexPhase().run(context)
        try JVMSourceValidationPhase().run(context)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "fun main() { consume<> { 1 } }",
        "fun main() { consume<Int,> { 1 } }",
        "fun main() { consume<Int> { 1 }",
        "fun main() { consume<Int> }",
        "fun main() { consume<Int> label@ 1 }",
    ])
    func rejectsIncompleteCallSuffixes(source: String) throws {
        let context = makeContextFromSource(source, emit: .jvmJar)
        try LexPhase().run(context)
        try JVMSourceValidationPhase().run(context)
        #expect(context.diagnostics.hasError)
    }
}
#endif
