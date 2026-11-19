#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite struct JVMQualifiedSuperGrammarTests {
    @Test(arguments: [
        "fun main() { super@Outer.call() }",
        "fun main() { super<Base>@Outer.call() }",
        "fun main() { run { super@Outer.call() } }",
        "class Outer { fun call() { super@Outer.call() } }",
    ])
    func acceptsQualifiedSuperLabels(source: String) throws {
        let context = makeContextFromSource(source, emit: .jvmJar)
        try LexPhase().run(context)
        try JVMSourceValidationPhase().run(context)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "fun main() { super@ { 1 } }",
        "fun main() { super@1.call() }",
        "fun main() { super@Outer. }",
        "fun main() { super<Base>@ }",
    ])
    func rejectsMalformedQualifiedSuperLabels(source: String) throws {
        let context = makeContextFromSource(source, emit: .jvmJar)
        try LexPhase().run(context)
        try JVMSourceValidationPhase().run(context)
        #expect(context.diagnostics.hasError)
    }
}
#endif
