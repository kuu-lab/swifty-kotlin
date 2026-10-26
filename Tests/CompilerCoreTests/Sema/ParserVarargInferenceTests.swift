#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct ParserVarargInferenceTests {
    private func context(sources: [String]) -> CompilationContext {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let paths = sources.indices.map { directory.appendingPathComponent("input\($0).kt").path }
        let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
        for (path, source) in zip(paths, sources) {
            _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        }
        return ctx
    }

    private func context(source: String) -> CompilationContext {
        context(sources: [source])
    }

    @Test(arguments: [false, true])
    func inferredExtensionReturnTypeBeforeVarargCall(extensionFirst: Bool) throws {
        let declarations = """
        interface Parser<out T>
        class ParserState
        fun <T> parser(block: ParserState.() -> T): Parser<T> = null as Parser<T>
        fun charParser(char: Char): Parser<Char> = null as Parser<Char>
        fun <T, R> Parser<T>.map(transform: (T) -> R): Parser<R> = null as Parser<R>
        fun <T> ParserState.any(vararg parsers: Parser<T>): T = null as T
        fun <T> ParserState.any(list: List<Parser<T>>): T = null as T
        """
        let consumer = """
        fun specialCharacters(): Parser<String> = parser {
            any(charParser('"').string(), charParser('b').map { "backspace" })
        }
        """
        let stringExtension = "fun Parser<Char>.string() = map { it.toString() }"
        let source = declarations + "\n" + (extensionFirst
            ? stringExtension + "\n" + consumer
            : consumer + "\n" + stringExtension)
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let calls = allExprIDs(in: ast, path: path, ctx: ctx) { exprID, expression in
                guard case let .call(callee, _, _, _) = expression,
                      case let .nameRef(name, _) = ast.arena.expr(callee),
                      sema.bindings.callBinding(for: exprID) != nil
                else { return false }
                return ctx.interner.resolve(name) == "any"
            }
            #expect(calls.count == 1)
            let call = try #require(calls.first)
            #expect(sema.bindings.exprType(for: call) == sema.types.stringType)
            let binding = try #require(sema.bindings.callBinding(for: call))
            #expect(binding.substitutedTypeArguments == [sema.types.stringType])
        }
    }

    @Test
    func inferredReturnDependenciesUseOnlyApplicableOverloads() throws {
        let ctx = context(source: """
        fun result(): Int = first("input")
        fun first(value: String) = second(value)
        fun second(value: String) = first(7)
        fun first(value: Int) = value
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func inProgressGenericCandidateDoesNotCauseSpuriousCycle() throws {
        let ctx = context(source: """
        fun result(): Int = select("input")
        fun <T> select(value: T) = select(7)
        fun select(value: Int) = value
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [false, true])
    func inferredReturnUsesDeclarationFileScope(providerFirst: Bool) throws {
        let consumer = """
        package consumer
        import provider.*
        fun result(): String = Box('x').string().value
        """
        let provider = """
        package provider
        class Box<out T>(val value: T)
        fun <T, R> Box<T>.map(transform: (T) -> R): Box<R> = Box(transform(value))
        private fun label(): String = "provider"
        fun Box<Char>.string() = map { label() }
        """
        let ctx = context(sources: providerFirst ? [provider, consumer] : [consumer, provider])
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func inferredExtensionReturnTypeStillRejectsIncompatibleParser() throws {
        let ctx = context(source: """
        class Parser<out T>(val value: T)
        fun <T> any(vararg parsers: Parser<T>): T = parsers[0].value
        fun result(): String = any(Parser('x').string(), Parser(7))
        fun Parser<Char>.string() = Parser(value.toString())
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-TYPE-0001" })
    }

    @Test(arguments: ["\"valid\"", "7"])
    func inferredReturnPreservesGenericUpperBounds(argument: String) throws {
        let ctx = context(source: """
        fun result() = identity(\(argument))
        fun <T : CharSequence> identity(value: T) = value
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError == (argument == "7"), "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let identity = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("identity")]))
        let signature = try #require(sema.symbols.functionSignature(for: identity))
        #expect(signature.typeParameterUpperBoundsList.count == 1)
        #expect(signature.typeParameterUpperBoundsList[0].count == 1)
    }

    @Test(arguments: ["fun value() = value()", "fun value() = other()\nfun other() = value()"])
    func recursiveInferredReturnTypesRequireAnnotation(source: String) throws {
        let ctx = context(source: source)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-INFER" })
    }

    @Test(arguments: [false, true])
    func forwardInferredNullableReturnPreservesNullability(nullable: Bool) throws {
        let ctx = context(source: """
        fun result(): String\(nullable ? "?" : "") = later()
        fun later() = value()
        fun value(): String? = null
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError == !nullable, "\(ctx.diagnostics.diagnostics)")
    }
}
#endif
