@testable import CompilerCore
import Testing
import TestStdlibCache

/// KUU-1466: Channel factories require a channels import even inside a
/// receiver lambda supplied to the bundled select DSL.
@Suite
struct SelectChannelFactoryVisibilityTests {
    @Test(arguments: [false, true])
    func unimportedChannelFactoryRemainsUnresolvedInsideSelect(
        allowDefaultStdlibLibrary: Bool
    ) throws {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        try withTemporaryFile(contents: """
        import kotlinx.coroutines.*
        import kotlinx.coroutines.selects.*

        fun probe() = runBlocking {
            val outside = Channel<Int>(1)
            select<Int> {
                val channel = Channel<Int>(1)
                channel.onReceive { it }
            }
        }
        """) { path in
            let ctx = makeCompilationContext(
                inputs: [path], emit: .executable,
                allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
            )
            try runSema(ctx)
            let unresolvedChannelCalls = ctx.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-SEMA-0023" && $0.message.contains("Channel")
            }
            #expect(
                unresolvedChannelCalls.count == 2,
                "Expected both Channel factories to be unresolved without the channels import, got: \(ctx.diagnostics.diagnostics)"
            )
        }
    }

    @Test(arguments: [false, true])
    func importedChannelFactoryResolvesInsideSelect(
        allowDefaultStdlibLibrary: Bool
    ) throws {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        try withTemporaryFile(contents: """
        import kotlinx.coroutines.*
        import kotlinx.coroutines.channels.*
        import kotlinx.coroutines.selects.*

        fun probe() = runBlocking {
            val outside = Channel<Int>(1)
            select<Int> {
                val channel = Channel<Int>(1)
                channel.onReceive { it }
            }
        }
        """) { path in
            let ctx = makeCompilationContext(
                inputs: [path], emit: .executable,
                allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
            )
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }
}
