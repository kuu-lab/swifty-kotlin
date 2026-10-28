#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct RangeUserExtensionResolutionTests {
    @Test func heterogeneousPrimitiveRangeToExtensionsResolveForOperatorsAndCalls() throws {
        TestStdlibCache.shared.prepare()
        let stdlibPath = try #require(CompilerOptions.defaultStdlibLibraryPath)
        let source = """
        operator fun Int.rangeTo(right: String): String = right
        operator fun Long.rangeTo(right: Double): Double = right
        operator fun String.rangeTo(right: Int): Int = right

        fun test() {
            val intOperator: String = 1.."a"
            val intCall: String = 1.rangeTo("a")
            val longOperator: Double = 1L..2.0
            val longCall: Double = 1L.rangeTo(2.0)
            val stringOperator: Int = "a"..1
            val stringCall: Int = "a".rangeTo(1)
        }
        """

        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                includeStdlib: false,
                stdlibLibraryPath: stdlibPath,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }.map { "\($0.code): \($0.message)" }
            #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            var resolvedHeterogeneousCalls = 0
            for index in ast.arena.exprs.indices {
                let id = ExprID(rawValue: Int32(index))
                guard let binding = sema.bindings.callBinding(for: id),
                      let symbol = sema.symbols.symbol(binding.chosenCallee),
                      ctx.interner.resolve(symbol.name) == "rangeTo",
                      let signature = sema.symbols.functionSignature(for: binding.chosenCallee),
                      let receiver = signature.receiverType,
                      signature.parameterTypes.count == 1
                else {
                    continue
                }
                let isExpectedHeterogeneousPair = (receiver == sema.types.intType && signature.parameterTypes[0] == sema.types.stringType)
                    || (receiver == sema.types.longType && signature.parameterTypes[0] == sema.types.doubleType)
                    || (receiver == sema.types.stringType && signature.parameterTypes[0] == sema.types.intType)
                if isExpectedHeterogeneousPair {
                    #expect(!symbol.flags.contains(.synthetic))
                    resolvedHeterogeneousCalls += 1
                }
            }
            #expect(resolvedHeterogeneousCalls == 6)
        }
    }

    @Test func inferredAndLiteralReceiversResolveUserExtensions() throws {
        let ctx = makeContextFromSource("""
        fun IntRange.onRange() = "int"
        fun LongRange.onRange() = "long"
        fun CharRange.onRange() = "char"
        fun <T> Iterable<T>.genExt() = "gen"
        fun Int.scalarOrRange() = "scalar"
        fun IntRange.scalarOrRange() = "range"
        fun test() {
            val ints = 1..3
            val longs = 1L..3L
            val chars = 'a'..'c'
            ints.onRange()
            longs.onRange()
            chars.onRange()
            ints.genExt()
            longs.genExt()
            chars.genExt()
            (1..3).genExt()
            (1L..3L).genExt()
            ('a'..'c').genExt()
            val typed: IntRange = 1..3
            typed.genExt()
            ints.scalarOrRange()
            1.scalarOrRange()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }.map { "\($0.code): \($0.message)" }
        #expect(errors.isEmpty)
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        var calls = 0
        for index in ast.arena.exprs.indices {
            let id = ExprID(rawValue: Int32(index))
            guard let binding = sema.bindings.callBinding(for: id),
                  let symbol = sema.symbols.symbol(binding.chosenCallee),
                  ["onRange", "genExt", "scalarOrRange"].contains(ctx.interner.resolve(symbol.name))
            else { continue }
            #expect(!symbol.flags.contains(.synthetic))
            if symbol.name == ctx.interner.intern("genExt") {
                #expect(binding.substitutedTypeArguments.count == 1)
                let elementType = try #require(binding.substitutedTypeArguments.first)
                #expect([sema.types.intType, sema.types.longType, sema.types.charType].contains(elementType))
            }
            calls += 1
        }
        #expect(calls == 12)
    }

    @Test(arguments: [
        "fun LongRange.onlyLong() {}\nfun test() { (1..3).onlyLong() }",
        "fun Iterable<String>.onlyStrings() {}\nfun test() { (1..3).onlyStrings() }",
        "fun IntRange.onlyRange() {}\nfun test() { 1.onlyRange() }",
        "fun IntRange.onlyRange() {}\nfun test() { (1.0..3.0).onlyRange() }",
        "fun IntRange.onlyRange() {}\nfun test(range: IntRange?) { range.onlyRange() }"
    ])
    func incompatibleReceiversRemainRejected(source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test func inferredRangeResolvesImportedIterableAsFlow() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.coroutines.flow.asFlow
        import kotlinx.coroutines.flow.Flow
        fun test() {
            val ints = 1..3
            val inferred: Flow<Int> = ints.asFlow()
            val literal: Flow<Int> = (1..3).asFlow()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }.map { "\($0.code): \($0.message)" }
        #expect(errors.isEmpty)
    }
}
#endif
