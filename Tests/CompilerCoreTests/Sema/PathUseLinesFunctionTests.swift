#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - STDLIB-IO-PATH-FN-038: Path.useLines { block }
//
// Verifies that `kotlin.io.path.Path.useLines(charset?, block)` resolves against
// the synthetic `kotlin.io.path.useLines` stub so that user code calling
// `path.useLines { lines -> ... }` (with or without a charset argument)
// compiles and type-checks correctly.

@Suite
struct PathUseLinesFunctionTests {

    // MARK: - Default-charset variant resolves

    @Test func testMergedRunToKIR() throws {
        let sources: [String] = [
            """
            package sample0

                    import kotlin.io.path.Path
                    import kotlin.io.path.useLines

                    fun sample0() {
                        val path = Path("/dev/null")
                        val count: Int = path.useLines { lines ->
                            lines.count()
                        }
                        println(count)
                    }

            """,
            """
            package sample1

                    import kotlin.io.path.Path
                    import kotlin.io.path.useLines
                    import kotlin.text.Charsets

                    fun firstLine(path: Path): String {
                        return path.useLines(Charsets.UTF_8) { lines ->
                            lines.firstOrNull() ?: ""
                        }
                    }

                    fun sample1() {
                        println(firstLine(Path("/dev/null")))
                    }

            """,
            """
            package sample2

                    import kotlin.io.path.Path
                    import kotlin.io.path.useLines

                    fun lineCount(path: Path): Int {
                        val n: Int = path.useLines { lines ->
                            lines.count()
                        }
                        return n
                    }

                    fun sample2() {
                        println(lineCount(Path("/dev/null")))
                    }

            """
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runToKIR(ctx)

            do {
                let samplePath = paths[0]
                let sampleDiagnostics = diagnosticsForPath(samplePath, in: ctx)

            #expect(
                !sampleDiagnostics.contains(where: { $0.severity == .error }),
                "Path.useLines { } should resolve and infer block return type: \(sampleDiagnostics.map(\.message))"
            )
            }
            do {
                let samplePath = paths[1]
                let sampleDiagnostics = diagnosticsForPath(samplePath, in: ctx)

            #expect(
                !sampleDiagnostics.contains(where: { $0.severity == .error }),
                "Path.useLines(charset) { } should resolve: \(sampleDiagnostics.map(\.message))"
            )
            }
            do {
                let samplePath = paths[2]
                let sampleDiagnostics = diagnosticsForPath(samplePath, in: ctx)

            #expect(
                !sampleDiagnostics.contains(where: { $0.severity == .error }),
                "Path.useLines block return type should propagate to call site: \(sampleDiagnostics.map(\.message))"
            )
            }
        }
    }
}
#endif
