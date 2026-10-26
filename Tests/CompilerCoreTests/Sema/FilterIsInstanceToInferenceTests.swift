#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct FilterIsInstanceToInferenceTests {
    @Test
    func emptyDestinationWithoutTypeContextFailsInference() throws {
        let path = "/filter-is-instance-to/inference.kt"
        let source = """
        fun main() {
            val values = listOf(1, "a", 2)
            println(values.filterIsInstanceTo(mutableListOf()))
        }
        """
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: true)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))

        try runSema(ctx)

        #expect(
            ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-INFER" },
            "Expected type inference to reject an untyped empty destination: \(ctx.diagnostics.diagnostics)"
        )
    }
}
#endif
