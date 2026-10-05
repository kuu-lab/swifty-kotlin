#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct GenericCallableReferenceInferenceTests {
    @Test(arguments: [
        "val ref: (Int) -> Int = ::identity; ref(42)",
        "val ref: (String) -> String = ::identity; ref(\"hello\")",
        "val ref: (Int?) -> Int? = ::identity; ref(null)",
        "val ref: (Int) -> Any = ::identity; ref(42)",
        "val ref: (List<Int>) -> List<Int> = ::identity; ref(listOf(42))",
        "use(::identity)",
        "useGeneric<Int>(::identity)",
    ])
    func infersFromContext(body: String) throws {
        let ctx = makeContextFromSource("""
        fun <T> identity(value: T): T = value
        fun use(ref: (Int) -> Int): Int = ref(42)
        fun <T> useGeneric(ref: (T) -> T) {}
        fun main() { \(body) }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected errors: \(errors)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let ref = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })
        let type = try #require(sema.bindings.exprType(for: ref))
        #expect(!sema.types.typeContainsAnyTypeParam(type))
        #expect(sema.bindings.callableRefKind(for: ref) == .functionRef)
    }

    @Test(arguments: [
        "fun ref(): (Int) -> Int = ::identity",
        "val ref: (Int) -> Int = ::identity",
        "fun <T> first(a: T, b: T): T = a; val ref: (Int, Int) -> Int = ::first",
        "fun <A, B> second(a: A, b: B): B = b; val ref: (Int, String) -> String = ::second",
        "fun <T : String> make(): T = TODO(); val ref: () -> Any = ::make",
        "fun <T, C : List<T>> firstIn(values: C): T = values[0]; val ref: (List<Int>) -> Int = ::firstIn",
        "class Box<T> { fun <R> transform(value: R): R = value }; fun ref(box: Box<String>) { val f: (Int) -> Int = box::transform }",
        "class Box { fun <T> identity(value: T): T = value }; val ref: (Box, Int) -> Int = Box::identity",
        "fun <T> T.copy(): T = this; val ref: (String) -> String = String::copy",
        "fun <T> T.copy(): T = this; fun ref(value: String) { val f: () -> String = value::copy }",
        "fun interface IntOp { fun apply(value: Int): Int }; fun use(op: IntOp): Int = op.apply(42); fun main() { use(::identity) }",
    ])
    func supportsOtherCallableContexts(declaration: String) throws {
        let ctx = makeContextFromSource("""
        fun <T> identity(value: T): T = value
        \(declaration)
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected errors: \(errors)")
    }

    @Test(arguments: [
        "fun <T> identity(value: T): T = value; val ref: (Int) -> String = ::identity",
        "fun <T : String> identity(value: T): T = value; val ref: (Int) -> Int = ::identity",
        "fun <T : Any> identity(value: T): T = value; val ref: (Int?) -> Int? = ::identity",
        "fun <T> identity(value: T): T = value; val ref: (Int, Int) -> Int = ::identity",
        "fun <T> identity(value: T): T = value; val ref: suspend (Int) -> Int = ::identity",
        "fun <T> unused(value: Int): Int = value; val ref: (Int) -> Int = ::unused",
    ])
    func rejectsInvalidReference(source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains {
            $0.severity == .error && $0.code == "KSWIFTK-TYPE-0001"
        })
    }

    @Test(arguments: [false, true])
    func choosesApplicableOverload(preferConcrete: Bool) throws {
        let other = preferConcrete
            ? "fun choose(value: Int): Int = value + 1"
            : "fun choose(value: String): String = value"
        let ctx = makeContextFromSource("""
        fun <T> choose(value: T): T = value
        \(other)
        fun main() { val ref: (Int) -> Int = ::choose }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError)
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let ref = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })
        let chosen = try #require(sema.bindings.identifierSymbol(for: ref))
        let signature = try #require(sema.symbols.functionSignature(for: chosen))
        #expect(signature.typeParameterSymbols.isEmpty == preferConcrete)
    }
}
#endif
