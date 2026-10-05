#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache

@Suite
struct MutableStateFlowPropertyTests {
    @Test(arguments: [false, true])
    func valueAssignmentLowersWithSourceAndArtifactStdlib(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        try withTemporaryFile(contents: """
        import kotlinx.coroutines.*
        import kotlinx.coroutines.flow.*

        fun update(state: MutableStateFlow<Int>) {
            state.value = 5
            state.value += 2
        }

        fun <T> replace(state: MutableStateFlow<T>, next: T) {
            state.value = next
        }

        fun main() = runBlocking {
            val state = MutableStateFlow(0)
            update(state)
            val view: StateFlow<Int> = state
            println(view.value)
            val nullable = MutableStateFlow<String?>("initial")
            replace(nullable, null)
            println(nullable.value)
        }
        """) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                emit: useArtifact ? .executable : .kirDump,
                allowDefaultStdlibLibrary: useArtifact
            )
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

            let sema = try #require(ctx.sema)
            let flowPackage = ["kotlinx", "coroutines", "flow"].map(ctx.interner.intern)
            let mutableValue = try #require(sema.symbols.lookup(
                fqName: flowPackage + [ctx.interner.intern("MutableStateFlow"), ctx.interner.intern("value")]
            ))
            #expect(sema.symbols.symbol(mutableValue)?.flags.contains(.mutable) == true)
            #expect(sema.symbols.isSourceBackedSymbol(mutableValue))
            let readOnlyValue = try #require(sema.symbols.lookup(
                fqName: flowPackage + [ctx.interner.intern("StateFlow"), ctx.interner.intern("value")]
            ))
            #expect(sema.symbols.symbol(readOnlyValue)?.flags.contains(.mutable) == false)
        }
    }
}
#endif
