#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite struct JVMControlFlowBodyLambdaGrammarTests {
    private func validates(_ source: String) -> Bool {
        let context = makeContextFromSource(source, emit: .jvmJar)
        try? LexPhase().run(context)
        try? JVMSourceValidationPhase().run(context)
        return !context.diagnostics.hasError
    }

    private func accepts(_ source: String, sourceLocation: Testing.SourceLocation = #_sourceLocation) {
        #expect(validates(source), "expected JVM source validation to accept: \(source) (\(sourceLocation.fileID):\(sourceLocation.line))")
    }

    private func rejects(_ source: String, sourceLocation: Testing.SourceLocation = #_sourceLocation) {
        #expect(!validates(source), "expected JVM source validation to reject: \(source) (\(sourceLocation.fileID):\(sourceLocation.line))")
    }

    // kotlinc parses a control-flow body whose braces open with a lambda
    // signature (`{ p -> ... }`) as a lambda literal, not a block.
    @Test(arguments: [
        "typealias Index = (String) -> (() -> ByteArray)?\nfun indexFor(entry: Any): Index =\n    when (entry) {\n        is String -> { _ -> null }\n        is Int -> { path -> null }\n        else -> { _ -> null }\n    }",
        "fun f(x: Any) = when (x) { 1 -> { a -> a } else -> { _ -> 0 } }",
        "fun f(x: Any) = when (x) { is String -> { s: String -> s } else -> { -> 0 } }",
        "fun f(x: Any) = when (x) { 1 -> { a, b -> a } else -> { (a, b) -> a } }",
        "fun f(c: Boolean): (Int) -> Int = if (c) { x -> x + 1 } else { y -> y - 1 }",
        "fun f(xs: List<Int>) { for (x in xs) { y -> y } }",
        "fun f() { var i = 0\nwhile (i < 1) { x -> x }\ni++ }",
        "fun f(x: Any) = when (x) { else -> { x -> foo(x)\nbar(x) } }",
    ])
    func acceptsLambdaBodiesInControlFlow(source: String) {
        accepts(source)
    }

    // Brace bodies without a lambda signature stay blocks.
    @Test(arguments: [
        "fun f(x: Any) = when (x) { 1 -> { foo() } else -> { val y = 1 } }",
        "fun f(x: Any) = when (x) { 1 -> { foo { y -> y } } else -> emptyMap() }",
        "fun f(x: Any) = when (x) { 1 -> { x } else -> { null } }",
    ])
    func stillAcceptsBlockBodies(source: String) {
        accepts(source)
    }

    @Test(arguments: [
        // A parameter needs a type after ':'.
        "fun f(x: Any) = when (x) { else -> { s: -> s } }",
        // A lambda signature must be closed by '->'.
        "fun f(x: Any) = when (x) { else -> { a, b } }",
        // The lambda body must be terminated.
        "fun f(x: Any) = when (x) { else -> { a -> a ",
    ])
    func rejectsInvalidLambdaBodies(source: String) {
        rejects(source)
    }
}
#endif
