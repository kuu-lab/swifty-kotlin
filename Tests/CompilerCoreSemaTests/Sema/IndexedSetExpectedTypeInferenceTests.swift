#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct IndexedSetExpectedTypeInferenceTests {
    @Test
    func arrayExtensionsDoNotUseInapplicableBuiltinElementContext() throws {
        let ctx = makeContextFromSource("""
        class Point
        operator fun Array<CharArray>.set(point: Point, value: Char) {}
        operator fun Array<CharArray>.set(index: Int, value: Char) {}
        operator fun Array<CharArray>.set(x: Int, y: Int, value: Char) {}
        fun character(): Char = 'x'
        fun use(grid: Array<CharArray>) {
            grid[Point()] = character()
            grid[0] = character()
            grid[0, 0] = character()
            var other = grid
            grid[0, 0] = run { other = grid; 'y' }
        }
        operator fun Array<Array<Int>>.set(point: Point, value: Char) {}
        fun builtin(grid: Array<Array<Int>>) { grid[0] = emptyArray() }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func genericExtensionSetContextualizesNestedConstructorArgument() throws {
        let source = """
        class Inv1<T>
        class Inv2<K, V>
        operator fun <K, V> Inv2<K, V>.set(key: K, value: V) { }
        class Something {
            val guilds = Inv2<Int, Inv1<String>>()
            fun test() { guilds[0] = Inv1() }
        }
        fun <T> assign(guilds: Inv2<Int, Inv1<T>>) { guilds[0] = Inv1() }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Expected the setter value type to infer Inv1<String>: \(errors)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let constructor = try #require(nameRefCallExprID(named: "Inv1", in: ast, interner: ctx.interner))
            guard case let .classType(inferredType) = sema.types.kind(of: try #require(sema.bindings.exprType(for: constructor))) else {
                Issue.record("Expected Inv1() to have a class type")
                return
            }
            let inv1 = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Inv1")]))
            #expect(inferredType.classSymbol == inv1)
            #expect(inferredType.args == [.invariant(sema.types.stringType)])
        }
    }

    @Test
    func ifExpressionIndexParsesAsIndexedSet() throws {
        // KUU-4458: the `<` inside the if condition used to leak angle depth,
        // hiding the top-level `=` from the assignment scan. The statement then
        // fell back to expression parsing, where the else branch swallowed
        // `] = v` as a local assignment (SEMA-0014) and the leftover get-index
        // failed the Int constraint (SEMA-0473).
        let ctx = makeContextFromSource("""
        class Box {
            operator fun set(index: Int, value: Int) {}
        }
        fun check(x: Int) {
            val box = Box()
            box[if (x < 0) 0 else x] = 9
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
#endif
