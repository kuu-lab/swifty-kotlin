@testable import CompilerCore
import TestStdlibCache
import Testing

@Suite
struct IterableFilterNotNullVarianceTests {
    @Test(arguments: [false, true])
    func filterNotNullAcceptsNullableAndNonNullableListElementsWithoutExpectedType(useLibrary: Bool) throws {
        if useLibrary { TestStdlibCache.shared.prepare() }
        let ctx = makeContextFromSource("""
        fun main() {
            println(listOf(1, 2).filterNotNull())
            println(listOf(1, null).filterNotNull())
        }
        """, allowDefaultStdlibLibrary: useLibrary)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected both List receivers to resolve with library=\(useLibrary): \(errors)")
    }
}
