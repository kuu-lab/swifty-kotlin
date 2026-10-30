#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct CharArraySumOfSelectorTypeTests {
    private func context(_ source: String, useStdlibLibrary: Bool) -> CompilationContext {
        if useStdlibLibrary {
            TestStdlibCache.shared.prepare()
        }
        let ctx = makeContextFromSource(
            source,
            emit: useStdlibLibrary ? .executable : .kirDump,
            allowDefaultStdlibLibrary: useStdlibLibrary
        )
        #expect((ctx.options.stdlibLibraryPath != nil) == useStdlibLibrary)
        return ctx
    }

    @Test(arguments: [false, true])
    func intSelectorsBindToExactCharArraySourceOverload(useStdlibLibrary: Bool) throws {
        let ctx = context("""
        fun main() {
            println(charArrayOf('O', '.', 'O').sumOf { c -> if (c == 'O') 2 else 0 })
            val selector: (Char) -> Int = { it.code }
            println(charArrayOf('A').sumOf(selector))
        }
        """, useStdlibLibrary: useStdlibLibrary)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let calls = memberCallExprIDs(named: "sumOf", in: ast, interner: ctx.interner)
            .filter { isUserSourceExpr($0, in: ctx) }
        #expect(calls.count == 2)
        let charArray = try #require(sema.symbols.lookup(fqName: [
            ctx.interner.intern("kotlin"), ctx.interner.intern("CharArray"),
        ]))
        for call in calls {
            let binding = try #require(sema.bindings.callBinding(for: call))
            #expect(sema.symbols.isSourceBackedSymbol(binding.chosenCallee))
            let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
            #expect(signature.returnType == sema.types.intType)
            let receiver = try #require(signature.receiverType)
            guard case let .classType(receiverClass) = sema.types.kind(of: receiver) else {
                Issue.record("Expected a nominal CharArray receiver")
                continue
            }
            #expect(receiverClass.classSymbol == charArray)
            let parameter = try #require(signature.parameterTypes.first)
            guard case let .functionType(selector) = sema.types.kind(of: parameter) else {
                Issue.record("Expected a function selector")
                continue
            }
            #expect(selector.params == [sema.types.charType])
            #expect(selector.returnType == sema.types.intType)
        }
    }

    @Test(arguments: [false, true])
    func unsupportedSelectorsProduceDiagnostics(useStdlibLibrary: Bool) throws {
        let ctx = context("""
        fun main() {
            println(charArrayOf('A').sumOf { it.toString() })
            println(charArrayOf('A').sumOf { it.code.toFloat() })
            println(charArrayOf('A').sumOf { it == 'A' })
            val selector: (Char) -> String = { it.toString() }
            println(charArrayOf('A').sumOf(selector))
        }
        """, useStdlibLibrary: useStdlibLibrary)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
        let errorLines = Set(ctx.diagnostics.diagnostics.compactMap { diagnostic -> Int? in
            guard diagnostic.severity == .error, let range = diagnostic.primaryRange else { return nil }
            return ctx.sourceManager.lineColumn(of: range.start).line
        })
        #expect(errorLines == [2, 3, 4, 6], "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let calls = memberCallExprIDs(named: "sumOf", in: ast, interner: ctx.interner)
            .filter { isUserSourceExpr($0, in: ctx) }
        #expect(calls.count == 4)
        // Error recovery may retain a binding to the sole Int overload. The
        // per-call errors above must still reject every unsupported selector.
        for call in calls {
            if let binding = sema.bindings.callBinding(for: call) {
                let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
                #expect(signature.returnType == sema.types.intType)
            }
        }
    }

    @Test(arguments: [false, true])
    func lexicalUserOverloadKeepsPriority(useStdlibLibrary: Bool) throws {
        let ctx = context("""
        fun CharArray.sumOf(operation: (Char) -> Int): Int = 99
        fun CharArray.sumOf(seed: Int, selector: (Char) -> Int): Int = seed
        fun main() {
            println(charArrayOf('A').sumOf { it.code })
            println(charArrayOf('A').sumOf(7) { it.code })
            println(charArrayOf('A').sumOf(operation = { it.code }))
            println(charArrayOf('A').sumOf(selector = { it.code }))
        }
        """, useStdlibLibrary: useStdlibLibrary)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let calls = memberCallExprIDs(named: "sumOf", in: ast, interner: ctx.interner)
            .filter { isUserSourceExpr($0, in: ctx) }
        #expect(calls.count == 4)
        for (index, call) in calls.enumerated() {
            let binding = try #require(sema.bindings.callBinding(for: call))
            let symbol = try #require(sema.symbols.symbol(binding.chosenCallee))
            let expectedName = index == 3
                ? ["kotlin", "collections", "sumOf"] : ["sumOf"]
            #expect(symbol.fqName == expectedName.map(ctx.interner.intern))
        }
    }

    @Test(arguments: [false, true])
    func inapplicableUserShapesKeepStdlibCandidates(useStdlibLibrary: Bool) throws {
        let ctx = context("""
        fun CharArray.sumOf(vararg selector: (Char) -> Int): Int = 99
        fun IntArray.fill(fromIndex: Int, value: Int, toIndex: Int) {}
        fun main() {
            println(charArrayOf('A').sumOf(selector = { it.code }))
            intArrayOf(1).fill(2, fromIndex = 0, toIndex = 1)
        }
        """, useStdlibLibrary: useStdlibLibrary)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        for name in ["sumOf", "fill"] {
            let call = try #require(memberCallExprIDs(named: name, in: ast, interner: ctx.interner)
                .first { isUserSourceExpr($0, in: ctx) })
            let binding = try #require(sema.bindings.callBinding(for: call))
            let symbol = try #require(sema.symbols.symbol(binding.chosenCallee))
            #expect(symbol.fqName == ["kotlin", "collections", name].map(ctx.interner.intern))
        }
    }
}
#endif
