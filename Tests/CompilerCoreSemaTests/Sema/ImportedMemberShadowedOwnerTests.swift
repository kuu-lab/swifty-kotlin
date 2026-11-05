@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct ImportedMemberShadowedOwnerTests {
    // KUU-4251
    @Test func importedMemberTypeParametersNormalizeAgainstImportedOwner() throws {
        TestStdlibCache.shared.prepare()
        let library = try #require(CompilerOptions.defaultStdlibLibraryPath)
        let sources = [
            """
            package kotlinx.coroutines.channels

            import kotlinx.coroutines.*

            public interface ProducerScope<in E> : CoroutineScope, SendChannel<E> {
                public val channel: SendChannel<E>
            }
            """,
            """
            package kotlinx.coroutines.flow

            import kotlinx.coroutines.*
            import kotlinx.coroutines.channels.*

            internal fun CoroutineScope.fixedPeriodTicker(): ReceiveChannel<Unit> {
                return produce(capacity = 0) {
                    channel.send(Unit)
                }
            }
            """
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let context = makeCompilationContext(inputs: paths, stdlibLibraryPath: library)
            try runSema(context)
            let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "\(errors.map { "\($0.code): \($0.message)" })")
        }
    }
}
