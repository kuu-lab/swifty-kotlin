#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ValueParameterMissingTypeTests {
    @Test(arguments: [
        "class C(Int)",
        "class C(val x)",
        "class C(var x)",
        "class C(x)",
        "class C(x, y)",
        "class C(val x: Int, y)",
        "fun f(x) {}",
        "fun f(x: Int, y) {}",
        "class C { constructor(x) {} }",
        "annotation class A(val v)",
        "fun f(@Suppress(\"x\") q) {}",
        "fun f(x = 5) {}",
    ])
    func rejectsValueParameterWithoutType(_ source: String) throws {
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)

        #expect(context.diagnostics.diagnostics.contains {
            $0.severity == .error
                && $0.code == "KSWIFTK-PARSE-0020"
                && $0.message == "An explicit type is required on a value parameter."
        })
    }

    @Test(arguments: [
        "class C(val x: Int)",
        "class C(x: Int)",
        "class C(val x: Int, y: String = \"a\")",
        "class C()",
        "interface I { fun m(p: Int) }",
        "fun f(a: Int, vararg b: String, c: (Int) -> Unit) {}",
        "fun f(@Suppress(\"x\") q: Int) {}",
        "fun f(x: Int = 5) {}",
        "val h = { a: Int, b: String -> a }",
        "val j = { a, b -> a }",
        // Anonymous function literals may leave parameter types implicit; the
        // expected function type supplies them during Sema.
        "val k: (Int) -> Int = fun(x) { return x }",
        "val l: (Int) -> Int = fun(x: Int) { return x }",
        "fun probe(): (Int) -> Int { return fun(value) { return value + 1 } }",
    ])
    func acceptsWellFormedParameters(_ source: String) throws {
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)

        #expect(!context.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-PARSE-0020"
        })
    }
}
#endif
