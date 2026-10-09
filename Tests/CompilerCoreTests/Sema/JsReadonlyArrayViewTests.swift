@testable import CompilerCore
import Foundation
import Testing

@Suite
struct JsReadonlyArrayViewTests {
    @Test
    func readonlyViewExposesOnlyCopyConversions() throws {
        let sources = [
            """
            package readonlyview.accepted
            @file:OptIn(kotlin.js.ExperimentalJsExport::class, kotlin.js.ExperimentalJsCollectionsApi::class)
            import kotlin.js.collections.toList
            import kotlin.js.collections.toMutableList
            fun probe(values: List<Int>) {
                val view = values.asJsReadonlyArrayView()
                view.toList()
                view.toMutableList().add(5)
            }
            """,
            """
            package readonlyview.rejected
            @file:OptIn(kotlin.js.ExperimentalJsExport::class, kotlin.js.ExperimentalJsCollectionsApi::class)
            fun probe(values: List<Int>) {
                val view = values.asJsReadonlyArrayView()
                view.add(5)
                view.clear()
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let acceptedErrors = diagnosticsForPath(paths[0], in: ctx).filter { $0.severity == .error }
            #expect(acceptedErrors.isEmpty, "Expected view read conversions to resolve: \(acceptedErrors)")

            let rejectedErrors = diagnosticsForPath(paths[1], in: ctx).filter { $0.severity == .error }
            #expect(
                rejectedErrors.filter { $0.code == "KSWIFTK-SEMA-0024" }.count == 2,
                "Expected the readonly view to reject mutation members: \(rejectedErrors)"
            )
        }
    }
}
