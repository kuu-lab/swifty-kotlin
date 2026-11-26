#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite struct JVMContextFunctionTypeGrammarTests {
    @Test(arguments: [
        """
        typealias Handler = context(String) () -> String
        fun main() {
            val f: Handler = context(a: String) fun() = a
            println(f("O"))
        }
        """,
        "fun take(f: context(String, Int) suspend (String) -> String) { println(f) }",
        "fun take(f: suspend context(String) (Int) -> String) { println(f) }",
        "fun take(f: context(String) List<Int>.() -> String) { println(f) }",
        "fun take(f: context(String) String?.() -> Int) { println(f) }",
        "fun take(f: context(String) (List<Int>?).() -> String) { println(f) }",
        "fun take(f: context(String) (String)?.() -> String) { println(f) }",
        "fun take(f: context(String) (String)? .() -> String) { println(f) }",
        "fun take(f: suspend context(String) (List<Int>?).() -> String) { println(f) }",
        "fun take(f: (context(String) () -> String)?) { println(f) }",
        "fun take(f: List<context(Map<String, Int>) () -> String>) { println(f) }",
        "fun take(f: context((String, Int) -> String, List<Int?>) () -> String) { println(f) }",
    ])
    func acceptsContextualFunctionTypes(source: String) throws {
        let context = makeContextFromSource(source, emit: .jvmJar)
        try LexPhase().run(context)
        try JVMSourceValidationPhase().run(context)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "fun take(f: context() () -> String) { println(f) }",
        "fun take(f: context(String)) { println(f) }",
        "fun take(f: context(String) String) { println(f) }",
    ])
    func rejectsMalformedContextualFunctionTypes(source: String) throws {
        let context = makeContextFromSource(source, emit: .jvmJar)
        try LexPhase().run(context)
        try JVMSourceValidationPhase().run(context)
        #expect(context.diagnostics.hasError)
    }
}
#endif
