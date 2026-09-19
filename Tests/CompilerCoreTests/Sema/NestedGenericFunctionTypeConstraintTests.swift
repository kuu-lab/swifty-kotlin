#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NestedGenericFunctionTypeConstraintTests {
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
