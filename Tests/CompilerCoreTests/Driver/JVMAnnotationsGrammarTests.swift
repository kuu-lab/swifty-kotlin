#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite struct JVMAnnotatedSourceGrammarTests {
    @Test(arguments: [
        "fun value(): Int = @Suppress(\"UNUSED\") -7 + 9",
        "fun value(flag: Boolean): Int = if (flag) @A { 3 } else @B { 4 }",
        "fun value(flag: Boolean): Int = when { flag -> @A { 3 }; else -> 4 }",
        "fun value(): Int = @A @B() (1 + 2)",
        "fun value(): Int = ++@A counter",
        "fun value(): Int = @A items[1]",
        "fun value(value: @UnsafeVariance T) {}",
        "fun value(value: List<@A out String>) {}",
        "fun value() { @A val x: Int = 1; println(x) }",
        "fun value() { val x = object { @A val y = 1 }; println(x.y) }",
    ])
    func preservesExpressionTypeAndLocalDeclarationAnnotations(source: String) throws {
        let context = makeContextFromSource(source, emit: .jvmJar)
        try LexPhase().run(context)
        try JVMSourceValidationPhase().run(context)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "fun value(): Int = @",
        "fun value(): Int = @A",
        "fun value(): Int = @A(1",
        "fun value(value: @A) {}",
        "fun value(flag: Boolean): Int = if (flag) @A else 1",
    ])
    func rejectsIncompleteAnnotatedOperands(source: String) throws {
        let context = makeContextFromSource(source, emit: .jvmJar)
        try LexPhase().run(context)
        try JVMSourceValidationPhase().run(context)
        #expect(context.diagnostics.hasError)
    }
}
#endif
