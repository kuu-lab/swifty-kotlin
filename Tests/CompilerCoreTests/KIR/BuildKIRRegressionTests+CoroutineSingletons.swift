@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    @Test
    func testCoroutineSingletonsRetainsGeneratedAPIsAndLoopElementType() throws {
        let source = """
        @file:Suppress("INVISIBLE_REFERENCE", "INVISIBLE_MEMBER")
        import kotlin.coroutines.intrinsics.CoroutineSingletons

        fun main() {
            println(CoroutineSingletons.entries.size)
            println(CoroutineSingletons.valueOf("RESUMED").ordinal)
            for (value in CoroutineSingletons.values()) {
                println(value.name)
                println(value.ordinal)
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let fqName = ["kotlin", "coroutines", "intrinsics", "CoroutineSingletons"].map(ctx.interner.intern)
        let enumSymbol = try #require(sema.symbols.lookup(fqName: fqName))
        #expect(sema.symbols.isSourceBackedSymbol(enumSymbol))
        let module = try #require(ctx.kir)
        #expect(module.arena.declarations.contains { declaration in
            guard case let .nominalType(nominal) = declaration else { return false }
            return nominal.symbol == enumSymbol
        })
        let main = try findKIRFunction(named: "main", in: module, interner: ctx.interner)
        #expect(!main.body.contains { instruction in
            guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
            return ["name", "ordinal"].contains(ctx.interner.resolve(callee))
        })
    }
}
