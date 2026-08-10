#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - STDLIB-IO-FN-017: Reader.forEachLine { line -> Unit }
//
// Verifies that `kotlin.io.Reader.forEachLine(action)` resolves against our synthetic
// `java.io.BufferedReader` declarations so that user code calling
// `reader.forEachLine { line -> ... }` compiles and type-checks. Unlike `useLines`,
// `forEachLine` does not close the reader — the lambda parameter is `String` and
// the call returns `Unit`.

@Suite
struct ReaderForEachLineFunctionTests {

    // MARK: - Direct forEachLine call resolves without errors

    @Test func testMergedRunToKIR() throws {
        let sources: [String] = [
            """
            package sample0

                    import java.io.File

                    fun sample0() {
                        val reader = File("/dev/null").bufferedReader()
                        reader.forEachLine { line ->
                            println(line)
                        }
                    }

            """,
            """
            package sample1

                    import java.io.File

                    fun sample1() {
                        val reader = File("/tmp/test.txt").bufferedReader()
                        reader.forEachLine { line ->
                            val len: Int = line.length
                            println(len)
                        }
                    }

            """,
            """
            package sample2

                    import java.io.File

                    fun processLines(file: File): Unit {
                        val reader = file.bufferedReader()
                        val result: Unit = reader.forEachLine { line ->
                            println(line)
                        }
                        return result
                    }

                    fun sample2() {
                        processLines(File("/dev/null"))
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
                !(sampleDiagnostics.contains(where: { $0.severity == .error })),
                Comment(rawValue: "BufferedReader.forEachLine should resolve without errors: \(sampleDiagnostics.map(\.message))")
            )
            }
            do {
                let samplePath = paths[1]
                let sampleDiagnostics = diagnosticsForPath(samplePath, in: ctx)

            #expect(
                !(sampleDiagnostics.contains(where: { $0.severity == .error })),
                Comment(rawValue: "forEachLine lambda parameter should be typed as String (line.length should resolve): \(sampleDiagnostics.map(\.message))")
            )
            }
            do {
                let samplePath = paths[2]
                let sampleDiagnostics = diagnosticsForPath(samplePath, in: ctx)

            #expect(
                !(sampleDiagnostics.contains(where: { $0.severity == .error })),
                Comment(rawValue: "BufferedReader.forEachLine should return Unit: \(sampleDiagnostics.map(\.message))")
            )
            }
        }
    }
}
#endif
