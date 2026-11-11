#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct CollectionShuffledCalleeSelectionTests {
    @Test
    func randomArgumentSelectsStdlibOverUserIntExtension() throws {
        let ctx = try semaContext(from: """
        import kotlin.random.Random

        fun List<Int>.shuffled(seed: Int): String = "user-$seed"

        fun probe(): Int {
            val ints = listOf(1, 2, 3)
            return ints.shuffled(Random(42)).size + ints.shuffled(42).length
        }
        """)
        let sema = try #require(ctx.sema)
        let callSites = sema.bindings.callBindings.values.compactMap { binding -> String? in
            guard let symbol = sema.symbols.symbol(binding.chosenCallee) else { return nil }
            let fq = symbol.fqName.map(ctx.interner.resolve).joined(separator: ".")
            guard fq.hasSuffix("shuffled") else { return nil }
            return fq
        }
        #expect(callSites.contains("kotlin.collections.shuffled"))
    }
}
#endif
