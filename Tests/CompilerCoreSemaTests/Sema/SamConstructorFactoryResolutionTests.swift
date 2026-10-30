#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

@Suite
struct SamConstructorFactoryResolutionTests {
    private func context(_ source: String) -> CompilationContext {
        TestStdlibCache.shared.prepare()
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(
            inputs: [path], stdlibLibraryPath: CompilerOptions.defaultStdlibLibraryPath,
            allowDefaultStdlibLibrary: false
        )
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }

    private func sourceLambdas(in ctx: CompilationContext) throws -> [ExprID] {
        let ast = try #require(ctx.ast)
        let file = try #require(ctx.sourceManager.fileID(forPath: ctx.options.inputs[0]))
        return ast.arena.exprs.enumerated().compactMap { index, expr in
            let id = ExprID(rawValue: Int32(index))
            guard case .lambdaLiteral = expr, ast.arena.exprRange(id)?.start.file == file else { return nil }
            return id
        }
    }

    @Test
    func functionTypeFactoryProvidesLambdaContext() throws {
        let ctx = context("""
        fun interface Operation<T> { fun apply(value: T): Int }
        object CharOperation : Operation<Char> { override fun apply(value: Char): Int = value.code }
        fun Operation(block: (String) -> Int): Operation<Char> = CharOperation
        fun main() { println(Operation { it.length }.apply('a')) }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Expected the String factory context: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let factory = try #require(sema.symbols.allSymbols().first {
            $0.kind == .function && ctx.interner.resolve($0.name) == "Operation"
        })
        #expect(sema.bindings.callBindings.values.contains { $0.chosenCallee == factory.id })
        let lambdas = try sourceLambdas(in: ctx)
        #expect(lambdas.count == 1)
        for id in lambdas {
            #expect(!sema.bindings.isSamConversion(id))
            let type = try #require(sema.bindings.exprType(for: id))
            guard case let .functionType(function) = sema.types.kind(of: type) else {
                Issue.record("Expected a function-typed factory argument")
                continue
            }
            #expect(function.params == [sema.types.stringType])
        }
    }

    @Test(arguments: [
        "fun Operation(value: Int): Operation = Operation { it.code }",
        "fun Operation(block: (String, String) -> Int): Operation = Operation { it.code }",
        "fun Operation(value: Int, block: (String) -> Int): Operation = Operation { it.code }",
    ])
    func incompatibleFactoryFallsBackToSam(factory: String) throws {
        let ctx = context("""
        fun interface Operation { fun apply(value: Char): Int }
        \(factory)
        fun main() { println(Operation { it.code }.apply('a')) }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Expected raw SAM fallback: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let lambda = try #require(try sourceLambdas(in: ctx).last)
        #expect(sema.bindings.isSamConversion(lambda))
    }

    @Test
    func applicableFactoryStillRejectsWrongLambdaResult() throws {
        let ctx = context("""
        fun interface Operation { fun apply(value: Char): String }
        object CharOperation : Operation { override fun apply(value: Char): String = "sam" }
        fun Operation(block: (String) -> Int): Operation = CharOperation
        fun main() { println(Operation { "wrong" }.apply('a')) }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "A wrong factory result must not fall back to a valid String-returning SAM")
    }

    @Test
    func multipleFactoriesRemainAmbiguous() throws {
        let ctx = context("""
        fun interface Operation { fun apply(value: Char): Int }
        object CharOperation : Operation { override fun apply(value: Char): Int = value.code }
        fun Operation(block: (String) -> Int): Operation = CharOperation
        fun Operation(block: (Int) -> Int): Operation = CharOperation
        fun main() { println(Operation { 1 }.apply('a')) }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.severity == .error && $0.code == "KSWIFTK-SEMA-0003" },
                "Competing function contexts must remain ambiguous: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func callableReferenceSelectsFactory() throws {
        let ctx = context("""
        fun interface Operation { fun apply(value: Char): Int }
        object CharOperation : Operation { override fun apply(value: Char): Int = value.code }
        fun Operation(block: (String) -> Int): Operation = CharOperation
        fun length(value: String): Int = value.length
        fun main() { println(Operation(::length).apply('a')) }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Callable references must also select the factory: \(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "Operation<Char> { it.code }",
        "Operation { c: Char -> c.code }",
    ])
    func explicitTypesExcludeIncompatibleFactory(expression: String) throws {
        let ctx = context("""
        fun interface Operation<T> { fun apply(value: T): Int }
        object CharOperation : Operation<Char> { override fun apply(value: Char): Int = value.code }
        fun Operation(block: (String) -> Int): Operation<Char> = CharOperation
        fun main() { println(\(expression).apply('a')) }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Explicit types must permit SAM fallback: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        #expect(!sema.bindings.samConversionExprs.isEmpty)
    }

    @Test(arguments: ["Operation { it.length }", "Operation(block = { it.length })"])
    func defaultAndNamedFactoryArgumentsProvideContext(expression: String) throws {
        let ctx = context("""
        fun interface Operation { fun apply(value: Char): Int }
        object CharOperation : Operation { override fun apply(value: Char): Int = value.code }
        fun Operation(value: Int = 0, block: (String) -> Int): Operation = CharOperation
        fun main() { println(\(expression).apply('a')) }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Factory argument mapping must preserve String context: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func genericFactoryReturnIsInferredAfterSelection() throws {
        let ctx = context("""
        fun interface Operation<T> { fun apply(value: T): Int }
        object CharOperation : Operation<Char> { override fun apply(value: Char): Int = value.code }
        fun <R> Operation(block: (String) -> R): Operation<Char> = CharOperation
        fun main() { println(Operation { it.length }.apply('a')) }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Generic factory must remain applicable before result inference: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func nonCallableFactoryDoesNotDisplaceSam() throws {
        let ctx = context("""
        fun interface Operation { fun apply(value: Char): Int }
        object CharOperation : Operation { override fun apply(value: Char): Int = 11 }
        fun Operation(block: Any): Operation = CharOperation
        fun main() { println(Operation { 42 }.apply('a')) }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError)
        let sema = try #require(ctx.sema)
        #expect(!sema.bindings.samConversionExprs.isEmpty)
    }

    @Test(arguments: [
        ("Operation { it.length }", "StringOperation"),
        ("Operation { s: String -> s.length }", "StringOperation"),
        ("Operation { c: Char -> c.code }", "Operation"),
    ])
    func samTypedFactoryAndRawConstructorUseTheirOwnContexts(expression: String, expectedSymbolName: String) throws {
        let ctx = context("""
        fun interface StringOperation { fun apply(value: String): Int }
        fun interface Operation { fun apply(value: Char): Int }
        object CharOperation : Operation { override fun apply(value: Char): Int = value.code }
        fun Operation(block: StringOperation): Operation = CharOperation
        fun main() { println(\(expression).apply('a')) }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "SAM-typed factories must retain applicability boundaries: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let lambda = try #require(try sourceLambdas(in: ctx).last)
        #expect(sema.bindings.isSamConversion(lambda))
        let type = try #require(sema.bindings.samInterfaceType(for: lambda) ?? sema.bindings.exprType(for: lambda))
        guard case let .classType(sam) = sema.types.kind(of: type) else {
            Issue.record("Expected the selected SAM context")
            return
        }
        let symbol = try #require(sema.symbols.symbol(sam.classSymbol))
        #expect(ctx.interner.resolve(symbol.name) == expectedSymbolName)
    }

    @Test
    func rawSamDoesNotDiscardExtraArguments() throws {
        let ctx = context("""
        fun interface Operation { fun apply(value: Char): Int }
        fun main() { println(Operation(1) { it.code }.apply('a')) }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "A synthetic SAM constructor accepts only its callable argument")
    }

    @Test
    func samFactoryTypeBoundsExcludeAnnotatedLambda() throws {
        let ctx = context("""
        fun interface Block<T> { fun run(value: T): Int }
        fun interface Operation { fun apply(value: Char): Int }
        object CharOperation : Operation { override fun apply(value: Char): Int = 11 }
        fun <T : Number> Operation(block: Block<T>): Operation = CharOperation
        fun main() { println(Operation { c: Char -> c.code }.apply('a')) }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "An annotation violating factory bounds must permit raw SAM fallback: \(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: ["42", "\"ok\""])
    func annotatedFactoriesRetainReturnTypeRefinement(body: String) throws {
        let ctx = context("""
        import kotlin.OptIn
        import kotlin.OverloadResolutionByLambdaReturnType
        import kotlin.experimental.ExperimentalTypeInference
        import kotlin.jvm.JvmName
        fun interface Operation { fun apply(value: Char): Int }
        object CharOperation : Operation { override fun apply(value: Char): Int = value.code }
        @OptIn(ExperimentalTypeInference::class)
        @OverloadResolutionByLambdaReturnType
        @JvmName("intOperation")
        fun Operation(block: (String) -> Int): Operation = CharOperation
        @JvmName("stringOperation")
        fun Operation(block: (String) -> String): Operation = CharOperation
        fun main() { println(Operation { \(body) }.apply('a')) }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Factory selection must preserve annotated return refinement: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let expectedReturn = body == "42" ? sema.types.intType : sema.types.stringType
        let factory = try #require(sema.bindings.callBindings.values.compactMap {
            sema.symbols.symbol($0.chosenCallee)
        }.first { ctx.interner.resolve($0.name) == "Operation" })
        let signature = try #require(sema.symbols.functionSignature(for: factory.id))
        guard case let .functionType(function) = sema.types.kind(of: signature.parameterTypes[0]) else {
            Issue.record("Expected the chosen function-type factory")
            return
        }
        #expect(function.returnType == expectedReturn)
    }

    @Test
    func moreSpecificFactoryProvidesItsInputContext() throws {
        let ctx = context("""
        import kotlin.jvm.JvmName
        fun interface Operation { fun apply(value: Char): Int }
        object CharOperation : Operation { override fun apply(value: Char): Int = value.code }
        @JvmName("stringOperation")
        fun Operation(block: (String) -> Int): Operation = CharOperation
        @JvmName("anyOperation")
        fun Operation(block: (Any) -> Int): Operation = CharOperation
        fun main() { println(Operation { 1 }.apply('a')) }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "A dominant factory must provide context before body inference: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let lambda = try #require(try sourceLambdas(in: ctx).last)
        let type = try #require(sema.bindings.exprType(for: lambda))
        guard case let .functionType(function) = sema.types.kind(of: type) else {
            Issue.record("Expected the factory function argument")
            return
        }
        #expect(function.params == [sema.types.anyType])
    }
}
#endif
