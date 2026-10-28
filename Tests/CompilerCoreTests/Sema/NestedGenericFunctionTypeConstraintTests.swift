#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct NestedGenericFunctionTypeConstraintTests {
    @Test
    func nestedGenericFactoryUsesTypeInferredFromEarlierArgument() throws {
        let context = makeContextFromSource("""
        class Box<T>(val value: T)
        fun <T> makeBox(): Box<T> = Box("factory" as T)
        fun <T> consume(first: Box<T>, second: Box<T>): String = "OK"

        fun inferred(): String = consume(Box("first"), makeBox())
        fun explicit(): String = consume<String>(Box("first"), makeBox())
        fun expectedVariable(): String {
            val second: Box<String> = makeBox()
            return consume(Box("first"), second)
        }
        """)

        try runSema(context)
        let hasErrors = context.diagnostics.hasError
        let diagnostics = context.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
        #expect(!hasErrors, "Expected earlier argument inference to contextualize the nested factory, got: \(diagnostics)")
    }

    @Test
    func extensionReceiverSuppliesTypeToNestedGenericCallArgument() throws {
        let context = makeContextFromSource("""
        var result1 = "failed"
        var result2 = "failed"

        fun (Int.() -> String).foo(a: Int.() -> String) { result1 = "O" }
        fun <T> (Int.() -> T).bar(a: Int.() -> T) { result2 = "K" }
        fun <T> test(): Int.() -> T = { 1 as T }

        fun box(): String {
            test<String>().foo(test())
            test<Int>().bar(test())
            return result1 + result2
        }
        """)

        try runSema(context)
        let hasErrors = context.diagnostics.hasError
        let diagnostics = context.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
        #expect(!hasErrors, "Expected the extension receiver to contextualize the nested generic call, got: \(diagnostics)")
    }

    @Test
    func overloadedInvariantContextsRemainCandidateSpecific() throws {
        let context = makeContextFromSource("""
        class Box<T>(val value: T)
        fun <T> makeBox(): Box<T> = Box("factory" as T)
        fun choose(first: Box<Any>, second: Box<String>, mode: String): String = "string"
        fun choose(first: Box<Any>, second: Box<Int>, mode: Int): String = "int"

        fun main() {
            val first = Box<Any>(Any())
            choose(first, makeBox(), 0)
        }
        """)

        try runSema(context)
        let errorCodes = context.diagnostics.diagnostics
            .filter { $0.severity == .error }
            .map(\.code)
        #expect(errorCodes.isEmpty, "Expected the matching overload to infer its own invariant argument context, got: \(errorCodes)")
    }

    @Test(arguments: [true, false])
    func testFunctionTypeNestedInInvariantGenericArgumentResolves(explicitTypeArgument: Bool) throws {
        let invocation = explicitTypeArgument
            ? "invokeFromBox<String>(box, \"world\")"
            : "invokeFromBox(box, \"world\")"
        let source = """
        class Box<T>(val value: T)

        fun <T1> invokeFromBox(box: Box<(T1) -> Unit>, arg: T1) {
            box.value(arg)
        }

        fun main() {
            val block: (String) -> Unit = { value -> print(value) }
            val box = Box<(String) -> Unit>(block)
            \(invocation)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path])
            try runSema(context)

            let diagnostics = context.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(
                !context.diagnostics.hasError,
                Comment(rawValue: "Nested generic function type should resolve, got: \(diagnostics)")
            )
        }
    }

    @Test
    func testFunctionTypeNestedInInvariantGenericArgumentRejectsMismatch() throws {
        let source = """
        class Box<T>(val value: T)

        fun <T1> invokeFromBox(box: Box<(T1) -> Unit>, arg: T1) {}

        fun main() {
            val block: (String) -> Unit = { value -> print(value) }
            val box = Box<(String) -> Unit>(block)
            invokeFromBox<Int>(box, 42)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path])
            try runSema(context)

            let failures = context.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-TYPE-0001"
            }
            #expect(failures.count == 1)
        }
    }
}
#endif
