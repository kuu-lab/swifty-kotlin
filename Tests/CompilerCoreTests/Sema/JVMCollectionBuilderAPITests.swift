#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct JVMCollectionBuilderAPITests {
    @Test(arguments: [
        "fun test() { val values = buildList { add(1) }; val value: Int = values[0] }",
        "fun test() { val values = buildMap { put(1, \"one\") }; val value: String? = values[1] }",
        "fun test() { val value: Int; buildList<Int> { value = 42 }; println(value) }",
        "fun test() { val value: String; buildMap<Int, String>(capacity = 0) { value = \"ok\" }; println(value) }",
    ])
    func acceptsInferredReceiversAndExactlyOnceInitialization(source: String) throws {
        try check(source, expectsError: false)
    }

    @Test(arguments: [
        "fun test() { buildList<Int> { add(\"wrong\") } }",
        "fun test() { buildMap<Int, String> { put(\"wrong\", 1) } }",
        "fun test() { val value: MutableList<Int> = buildList { add(1) } }",
        "fun test() { val value: Int; buildList<Int> { if (false) value = 42 }; println(value) }",
        "fun test() { buildMap<Int, String>(capacity = \"wrong\") { put(1, \"one\") } }",
    ])
    func rejectsInvalidElementsReadonlyAssignmentsAndConditionalInitialization(source: String) throws {
        try check(source, expectsError: true)
    }

    private func check(_ source: String, expectsError: Bool) throws {
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], emit: .jvmJar)
            try JVMPreparationPhase().run(context)
            try runSema(context)
            #expect(context.diagnostics.hasError == expectsError, "\(context.diagnostics.diagnostics)")
            #expect(!context.diagnostics.diagnostics.contains { $0.code.hasPrefix("KSWIFTK-ICE") })
        }
    }
}
#endif
