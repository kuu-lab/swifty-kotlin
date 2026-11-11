@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite
struct RangeForEachNonLocalReturnTests {
    @Test
    func rangeAndProgressionForEachAllowNonLocalReturn() throws {
        let source = try diffCaseSource("int_range_foreach_non_local_return.kt", file: #filePath)
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
