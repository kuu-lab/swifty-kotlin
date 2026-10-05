@testable import CompilerCore
import Testing

@Suite
struct NestedWithContextLoweringTests {
    @Test(arguments: [false, true])
    func clonedBlockReferencesUseRuntimeEntryPoints(useArtifact: Bool) throws {
        let source = """
        import kotlinx.coroutines.*
        fun main() {
            runBlocking {
                val prefix = "nested"
                println(withContext(Dispatchers.Default) {
                    withContext(Dispatchers.IO) { prefix }
                })
            }
        }
        """
        let ctx = makeContextFromSource(source, allowDefaultStdlibLibrary: useArtifact)
        try runToLowering(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let functions = findAllKIRFunctions(in: module)
        let adapters = functions.filter {
            ctx.interner.resolve($0.name).hasPrefix("kk_suspend_kk_coroutine_block_adapter_")
        }
        #expect(!adapters.isEmpty)
        let callees = functions.flatMap { extractCallees(from: $0.body, interner: ctx.interner) }
        #expect(!callees.contains("withContext"))
        #expect(callees.contains("kk_with_context"))
        #expect(callees.contains("kk_coroutine_launcher_arg_set"))
    }
}
