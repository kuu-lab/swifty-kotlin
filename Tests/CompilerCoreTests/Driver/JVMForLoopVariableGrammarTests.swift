#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite struct JVMForLoopVariableGrammarTests {
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

    @Test(arguments: [
        "fun f(xs: List<String>) { for (x in xs) { println(x) } }",
        "fun f(xs: List<String>) { for (x: String in xs) { println(x) } }",
        "fun f(xs: List<String>) { for (_item: String in xs) { println(_item) } }",
        "fun f(xs: List<List<Int>>) { for (x: List<Int> in xs) { println(x.sum()) } }",
        "fun f(xs: List<Map<String, Int>?>) { for (x: Map<String, Int>? in xs) { println(x) } }",
        "fun f(xs: List<IntArray>) { for (x: IntArray in xs) { println(x.size) } }",
        "fun f(xs: List<Pair<String, Int>?>) { for (x: Pair<String, Int>? in xs) { } }",
        "fun f(xs: List<Pair<String, Int>>) { for (p: Pair<String, Int> in xs) { println(p.first) } }",
        "fun f(xs: List<kotlin.collections.Map.Entry<String, Int>>) { for (e: kotlin.collections.Map.Entry<String, Int> in xs) { } }",
        "fun f(xs: List<String>) { for (x: String in xs) for (y: Int in 1..3) { println(x + y) } }",
        "fun f(xs: Map<String, Int>) { for ((k, v) in xs) { println(k + v) } }",
        "fun f(xs: Map<String, Int>) { for ((k, v) in xs) { for (x: String in xs.keys) { println(x) } } }",
        "fun f(xs: List<Pair<String, Int>>) { for ((k: String, v) in xs) { println(k) } }",
        "fun f(xs: List<Pair<String, Int>>) { for ((k, v: Int) in xs) { println(v) } }",
        "fun f(xs: List<Pair<Map<String, Int>?, Int>>) { for ((k: Map<String, Int>?, v: Int) in xs) { println(v) } }",
        "fun f(xs: List<Pair<String, Int>>) { for ((k: String, v: Int,) in xs) { println(k + v) } }",
        "fun f(xs: List<String>) {\n    for (x: String in xs) {\n        println(x)\n    }\n}",
    ])
    func acceptsTypedAndUntypedLoopVariables(source: String) {
        accepts(source)
    }

    @Test(arguments: [
        // kotlinc: a for-loop variable cannot be declared with 'val' or 'var'.
        "fun f(xs: List<Int>) { for (val x: Int in xs) { println(x) } }",
        "fun f(xs: List<Int>) { for (var x in xs) { println(x) } }",
        // kotlinc: a loop variable needs a type after ':'.
        "fun f(xs: List<Int>) { for (x: in xs) { println(x) } }",
        "fun f(xs: List<Int>) { for (x: ) { println(x) } }",
        // kotlinc: a loop variable is a single name; a comma ends the header.
        "fun f(xs: List<Int>) { for (x: Int, y in xs) { println(x) } }",
        "fun f(xs: List<Int>) { for ((k, v) in xs) { for (x: String, y in xs) { println(x) } } }",
        "fun f(xs: List<Pair<String, Int>>) { for ((k:, v) in xs) { println(k) } }",
        "fun f(xs: List<Pair<String, Int>>) { for ((k, v:) in xs) { println(v) } }",
    ])
    func rejectsInvalidLoopVariables(source: String) {
        rejects(source)
    }
}
#endif
