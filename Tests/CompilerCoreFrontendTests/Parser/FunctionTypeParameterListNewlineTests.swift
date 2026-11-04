#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

/// KUU-3968 (+ siblings KUU-3999 / KUU-3975): a function type-parameter
/// list `<…>` may span lines and end in a trailing comma — kotlinc accepts
/// both (Kotlin 1.4+). Kodein-DI and Store generate this style
/// (`fun <\n    T,\n    reified P1,\n> f(…)`), which used to fail with
/// KSWIFTK-PARSE-0002 "Expected function name."
@Suite
struct FunctionTypeParameterListNewlineTests {
    @Test(arguments: [
        // Plain multi-line lists.
        "fun <T,\n    P> f(x: P): T = TODO()",
        "fun <\n    T,\n    P\n> f(x: P): T = TODO()",
        "fun <T, P\n> f(x: P): T = TODO()",
        // Trailing comma, on one line or before a `>` on its own line.
        "fun <T,> f(x: T) = x",
        "fun <T : Any,> f(x: T) = x",
        "fun <T, P,> f(x: P): T = TODO()",
        "fun <\n    T,\n    P,\n> f(x: P): T = TODO()",
        // Store MutableStoreBuilder shape: bounded parameters + trailing comma.
        "interface Store\nfun <K : Any, N : Any, L : Any, O : Any,> Store.from(): Store = this",
        // Kodein shape: `reified` on its own line + trailing comma + receiver.
        "interface DIA\ninline fun <\n    T,\n    reified P1,\n> DIA.new(p: P1): T = TODO()",
        // Variance modifiers on their own lines.
        "class Box<T,\n    out P> { }",
        "class Box<T,\n    in P> { }",
        // Annotations on following lines keep the list open.
        "annotation class A\nfun <T,\n    @A P> f(x: P): T = TODO()",
        "annotation class A\nfun <T,\n    @A(1)\n    P> f(x: P): T = TODO()",
        "annotation class A\nclass Box<T,\n    @A P> { }",
        // A `where` clause after a multi-line list still binds.
        "fun <T,\n    P,> f(x: P): T where P : Any = TODO()",
    ])
    func multilineTypeParameterListParses(source: String) {
        let parsed = parse(source)

        #expect(parsed.diagnostics.diagnostics.isEmpty,
                "Unexpected diagnostics: \(parsed.diagnostics.diagnostics)")
        #expect(parsed.arena.nodes.contains { $0.kind == .typeArgs })
    }

    @Test(arguments: [
        "class Box<T,> { }",
        "interface Store<K : Any,> { }",
        "typealias PairBox<A,> = Int",
        "enum class Entry<T,> { A }",
    ])
    func trailingCommaTypeParametersParseForOtherDeclarations(source: String) {
        let parsed = parse(source)

        #expect(parsed.diagnostics.diagnostics.isEmpty,
                "Unexpected diagnostics: \(parsed.diagnostics.diagnostics)")
        #expect(parsed.arena.nodes.contains { $0.kind == .typeArgs })
    }

    @Test(arguments: [
        // Empty list, doubled comma, and dangling variance stay rejected.
        "fun <> f(x: Int) = x",
        "fun <,T> f(x: T) = x",
        "fun <T,,U> f(x: T) = x",
        "fun <T,,> f(x: T) = x",
        "fun <in> f(x: Int) = x",
        "fun <T, in> f(x: T) = x",
        "fun <T, out> f(x: T) = x",
    ])
    func malformedTypeParameterListsStayRejected(source: String) {
        let parsed = parse(source)

        #expect(parsed.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-PARSE-0002" },
                "Expected KSWIFTK-PARSE-0002 for `\(source)`: \(parsed.diagnostics.diagnostics)")
    }

    @Test
    func annotationOnNewLineStillEndsUnterminatedList() {
        // The `@` inside `<…>` only shields the next list element; an
        // annotation on a following declaration still ends the list so the
        // declaration is not swallowed.
        let parsed = parse("""
        annotation class A
        fun <T
            @A
            fun g() {}
        fun after() = 1
        """)

        #expect(parsed.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-PARSE-0005" })
        #expect(parsed.arena.nodes.count { $0.kind == .funDecl } == 3)
    }

    @Test
    func annotatedDeclarationModifierStillEndsUnterminatedList() {
        let parsed = parse("""
        annotation class A
        fun <T
            @A
            private val x = 1
        """)

        #expect(parsed.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-PARSE-0005" })
        #expect(parsed.arena.nodes.count { $0.kind == .propertyDecl } == 1)
    }

    @Test
    func hardKeywordStillEndsUnterminatedList() {
        let parsed = parse("""
        fun <T
        class C {}
        fun after() = 1
        """)

        #expect(parsed.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-PARSE-0005" })
        #expect(parsed.arena.nodes.count { $0.kind == .classDecl } == 1)
        #expect(parsed.arena.nodes.count { $0.kind == .funDecl } == 2)
    }
}
#endif
