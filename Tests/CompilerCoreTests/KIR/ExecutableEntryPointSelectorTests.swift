@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite
struct ExecutableEntryPointSelectorTests {
    @Test(arguments: [false, true])
    func firstFileLevelMainOrderIsPreserved(argsFirst: Bool) throws {
        let noargs = "fun main() {}"
        let args = "fun main(args: Array<String>) {}"
        let context = makeContextFromSource("""
        package entrycontrols
        class Holder { fun main() {} }
        fun helper() { fun main() {} }
        \(argsFirst ? args : noargs)
        \(argsFirst ? noargs : args)
        """, allowDefaultStdlibLibrary: false)
        try runToKIR(context)
        #expect(!context.diagnostics.hasError)
        let ast = try #require(context.ast)
        let sema = try #require(context.sema)
        let kir = try #require(context.kir)
        let symbol = try #require(ExecutableEntryPointSelector.firstFileLevelSymbol(
            ast: ast, bindings: sema.bindings, arena: kir.arena, interner: context.interner,
            symbols: sema.symbols, entryPointFQName: nil
        ))
        let selected = try #require(kir.arena.function(for: symbol))
        #expect(sema.symbols.symbol(symbol)?.fqName.map(context.interner.resolve).joined(separator: ".") == "entrycontrols.main")
        #expect(selected.params.count == (argsFirst ? 1 : 0))
        let bridgeName = context.interner.intern("__kk_process_args_from_argv")
        #expect(sema.symbols.lookup(fqName: [bridgeName]) == nil)
    }

    @Test
    func exactDesignatedFunctionWinsAndMissingDoesNotFallback() throws {
        let context = makeContextFromSource("""
        package entrycontrols
        fun main() {}
        fun launch(args: Array<String>) {}
        """, allowDefaultStdlibLibrary: false)
        try runToKIR(context)
        let ast = try #require(context.ast)
        let sema = try #require(context.sema)
        let kir = try #require(context.kir)
        let launch = try #require(ExecutableEntryPointSelector.firstFileLevelSymbol(
            ast: ast, bindings: sema.bindings, arena: kir.arena, interner: context.interner,
            symbols: sema.symbols, entryPointFQName: "entrycontrols.launch"
        ))
        #expect(sema.symbols.symbol(launch)?.fqName.map(context.interner.resolve).joined(separator: ".") == "entrycontrols.launch")
        #expect(kir.arena.function(for: launch)?.params.count == 1)
        #expect(ExecutableEntryPointSelector.firstFileLevelSymbol(
            ast: ast, bindings: sema.bindings, arena: kir.arena, interner: context.interner,
            symbols: sema.symbols, entryPointFQName: "entrycontrols.missing"
        ) == nil)
    }

    @Test
    func unsupportedFirstMatchingFunctionIsNotSkipped() throws {
        let context = makeContextFromSource("""
        fun main(value: Int) {}
        fun main(args: Array<String>) {}
        """, allowDefaultStdlibLibrary: false)
        try runToKIR(context)
        #expect(!context.diagnostics.hasError)
        let ast = try #require(context.ast)
        let sema = try #require(context.sema)
        let kir = try #require(context.kir)
        let symbol = try #require(ExecutableEntryPointSelector.firstFileLevelSymbol(
            ast: ast, bindings: sema.bindings, arena: kir.arena, interner: context.interner,
            symbols: sema.symbols, entryPointFQName: nil
        ))
        let selected = try #require(kir.arena.function(for: symbol))
        #expect(selected.params.count == 1)
        #expect(selected.params.first?.type == sema.types.intType)
    }
}
