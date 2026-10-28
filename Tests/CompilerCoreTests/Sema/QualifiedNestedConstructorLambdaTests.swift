#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct QualifiedNestedConstructorLambdaTests {
    @Test
    func exactReproducerWithoutImport() throws {
        let ctx = makeContextFromSource("""
        class A { class B(val xs: List<String>, val f: (String) -> String) }
        fun main() { println(A.B(listOf("a"), { it }).xs.size) }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")
    }

    @Test(arguments: [
        "A.B(listOf(\"a\"), { it })",
        "A.B(listOf(\"a\"), { s: String -> s })",
        "A.B(listOf(\"a\")) { it }",
        "A.B(f = { it }, xs = listOf(\"a\"))",
        "A.B(listOf(\"a\"), fn)",
        "B(listOf(\"a\"), { it })",
    ])
    func acceptsIssueMatrix(expression: String) throws {
        let ctx = makeContextFromSource("""
        import A.B
        class A { class B(val xs: List<String>, val f: (String) -> String) }
        fun main() {
            val fn: (String) -> String = { it }
            println(\(expression).xs.size)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")
    }

    @Test(arguments: [
        """
        class A { class B(val f: (String) -> String) }
        fun main() { A.B({ it }) }
        """,
        """
        class A { class B(val xs: List<String>) }
        fun main() { A.B(listOf("a")) }
        """,
        """
        class A { class B(val first: (Int) -> Int, val second: (String) -> String) }
        fun main() { A.B(second = { it }, first = { it + 1 }) }
        """,
        """
        class A { class B {
            constructor(f: (String) -> String, marker: String)
            constructor(f: (Int) -> Int, marker: Int)
        } }
        fun main() { A.B({ it + 1 }, 7) }
        """,
        """
        class A { class B(val f: (String) -> String) }
        fun identity(s: String): String = s
        fun identity(i: Int): Int = i
        fun main() { A.B(::identity) }
        """,
    ])
    func acceptsContextualArguments(source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")
    }

    @Test(arguments: [
        "val value = A.B(listOf(\"a\"), { it })",
        "val value = A.B<String>(listOf(\"a\"), { it })",
        "val value: A.B<String> = A.B(listOf(\"a\"), { it })",
        "val value = A.B(f = { it }, xs = listOf(\"a\"))",
    ])
    func genericConstructorInfersString(statement: String) throws {
        let ctx = makeContextFromSource("""
        class A { class B<T : Any>(val xs: List<T>, val f: (String) -> T) }
        fun main() { \(statement) }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let call = try #require(memberCallExprIDs(named: "B", in: ast, interner: ctx.interner).first {
            sema.bindings.callBinding(for: $0) != nil
        })
        let binding = try #require(sema.bindings.callBinding(for: call))
        let nestedClass = try #require(sema.symbols.lookup(fqName: [
            ctx.interner.intern("A"), ctx.interner.intern("B"),
        ]))
        #expect(sema.symbols.symbol(binding.chosenCallee)?.kind == .constructor)
        #expect(sema.symbols.parentSymbol(for: binding.chosenCallee) == nestedClass)
        #expect(sema.bindings.exprType(for: call) == sema.types.make(.classType(ClassType(
            classSymbol: nestedClass,
            args: [.invariant(sema.types.stringType)],
            nullability: .nonNull
        ))))
    }

    @Test(arguments: [
        """
        class A { class B(val f: (String) -> String) }
        fun main() { A.B({ s: Int -> s }) }
        """,
        """
        class A { class B(val f: (String) -> String) }
        fun main() { A.B({ 1 }) }
        """,
        """
        class A { class B(val f: (String) -> String) }
        fun main() { A.B({ it - 1 }) }
        """,
        """
        class A { class B(val f: (String) -> String) }
        fun main() { A.B({ x, y -> x }) }
        """,
        """
        class A { class B private constructor(val f: (String) -> String) }
        fun main() { A.B({ it }) }
        """,
        """
        class A { class B<T : Any>(val xs: List<T>, val f: (String) -> T) }
        fun main() { A.B<String>(listOf("a"), { 1 }) }
        """,
    ])
    func rejectsInvalidArguments(source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "Invalid nested constructor argument must be rejected")
    }

    @Test
    func conflictingImplicitParameterTypesRemainAmbiguous() throws {
        let ctx = makeContextFromSource("""
        class A { class B {
            constructor(f: (String) -> String)
            constructor(f: (Int) -> Int)
        } }
        fun main() { A.B({ it }) }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0003" }, "Expected overload ambiguity: \(errors)")
    }
}
#endif
