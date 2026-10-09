#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

struct FQNBundledObjectPropertyTests {
    @Test(arguments: [false, true])
    func testFQNObjectPropertyReadsDoNotLowerPackageSegments(useArtifact: Bool) throws {
        let stdlibLibraryPath = useArtifact ? try testStdlibArtifactPath() : nil
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        package my.pkg

        import kotlin.native.Platform as NativePlatform
        import kotlinx.coroutines.Dispatchers as ShortDispatchers

        object O {
            val x = 42
        }

        fun main() {
            val platform = NativePlatform
            val dispatchers = ShortDispatchers
            println(kotlin.native.Platform.isDebugBinary == platform.isDebugBinary)
            println(kotlinx.coroutines.Dispatchers.Default === dispatchers.Default)
            println(kotlin.native.Platform.getAvailableProcessors())
            println(kotlin.native.Platform)
            println(kotlin.native.OsFamily.MACOSX)
            println(kotlin.native.BitSet(4))
            println(kotlin.Int.MAX_VALUE)
            println(kotlin.Char.MIN_VALUE)
            println(kotlin.Double.NaN)
            println(kotlin.math.PI)
            println(kotlin.coroutines.EmptyCoroutineContext)
            println(my.pkg.O.x)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "FQNBundledObjectProperty",
                emit: .kirDump,
                includeStdlib: !useArtifact,
                stdlibLibraryPath: stdlibLibraryPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "Expected bundled-object FQN properties to compile (artifact: \(useArtifact)), got: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            let phantomCallees = callees.filter { ["native", "Platform", "coroutines", "Dispatchers"].contains($0) }
            #expect(
                phantomCallees.isEmpty,
                "Package/object path segments must not become calls (artifact: \(useArtifact)): \(phantomCallees)"
            )
        }
    }
}
#endif
