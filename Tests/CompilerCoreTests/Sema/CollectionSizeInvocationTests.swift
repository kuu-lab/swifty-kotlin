@testable import CompilerCore
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

@Suite
struct CollectionSizeInvocationTests {
    @Test
    func nonCallableSizeValuesCannotBeInvokedAndCallableValuesStillCan() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource("""
        fun invalidPropertyCall() { listOf(1, 2).size() }
        fun invalidValueCall() {
            val size: Int = listOf(1, 2).size
            size()
        }
        fun validPropertyRead(): Int = listOf(1, 2).size
        fun validFunctionValueCall(): Int {
            val value: () -> Int = { 42 }
            return value()
        }
        """, allowDefaultStdlibLibrary: true)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 2, "Expected errors only for the two non-callable values: \(ctx.diagnostics.diagnostics)")
    }
}
