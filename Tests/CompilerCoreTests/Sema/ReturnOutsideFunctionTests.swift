#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ReturnOutsideFunctionTests {

    @Test func testReturnInTopLevelPropertyInitializerIsRejected() throws {
        let sources = [
            """
            val x = return
            fun main() {}
            """,
            """
            fun f() {
                val x = return
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)

            let topLevelDiagnostics = diagnosticsForPath(paths[0], in: ctx)
            #expect(
                topLevelDiagnostics.contains {
                    $0.code == "KSWIFTK-SEMA-0042" && $0.severity == .error
                },
                "return in a top-level property initializer must be rejected: \(topLevelDiagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | "))"
            )

            let localDiagnostics = diagnosticsForPath(paths[1], in: ctx)
            #expect(
                !localDiagnostics.contains(where: { $0.severity == .error }),
                "return in a local property initializer must keep targeting its function: \(localDiagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | "))"
            )
        }
    }
}
#endif
