#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

/// KUU-3940: native.concurrent freezing compatibility APIs must remain
/// available to consumers that emit a library against the bundled stdlib.
@Suite
struct KUU3940NativeConcurrentFreezingImportTests {
    @Test
    func nativeConcurrentFreezingImportsResolveForLibraryCompilation() throws {
        let source = """
        @file:Suppress("DEPRECATION_ERROR")
        package kotlinx.atomicfu

        import kotlin.native.concurrent.ensureNeverFrozen
        import kotlin.native.concurrent.isFrozen

        fun traceBaseUsesLegacyFreezingApi(value: Any): Boolean {
            value.ensureNeverFrozen()
            return value.isFrozen
        }
        """

        try withTemporaryFile(contents: source) { inputPath in
            let context = makeCompilationContext(
                inputs: [inputPath],
                moduleName: "KUU3940AtomicfuConsumer",
                emit: .library
            )
            try runSema(context)
            #expect(
                context.errorDiagnostics.isEmpty,
                "Expected native.concurrent freezing imports to resolve, got: \(context.errorDiagnostics)"
            )
        }
    }
}
#endif
