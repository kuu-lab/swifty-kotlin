#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - STDLIB-IO-FN-040: Reader.useLines { lines -> T }
//
// Verifies that `kotlin.io.Reader.useLines(block)` resolves against our synthetic
// `java.io.BufferedReader` declarations so that user code calling
// `reader.useLines { lines -> ... }` (the common shape for the Reader-flavour
// `useLines`) compiles and type-checks against the same `(List<String>) -> T`
// surface as `File.useLines`.

@Suite
struct ReaderUseLinesFunctionTests {

    // MARK: - Direct useLines call resolves and infers the block return type

    @Test func testMergedRunToKIR() throws {
        let sources: [String] = [
            """
            package sample0

                    import java.io.File

                    fun sample0() {
                        val reader = File("/dev/null").bufferedReader()
                        val count: Int = reader.useLines { lines ->
                            lines.size
                        }
                        println(count)
                    }

            """,
            """
            package sample1

                    import java.io.File

                    fun firstOrEmpty(file: File): String {
                        val reader = file.bufferedReader()
                        return reader.useLines { lines ->
                            if (lines.isEmpty()) "" else lines[0]
                        }
                    }

                    fun sample1() {
                        println(firstOrEmpty(File("/dev/null")))
                    }

            """,
            """
            package sample2

                    import java.io.File

                    fun loadJoined(file: File): String {
                        val reader = file.bufferedReader()
                        val joined: String = reader.useLines { lines ->
                            lines.joinToString("\\n")
                        }
                        return joined
                    }

                    fun sample2() {
                        println(loadJoined(File("/dev/null")))
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
                Comment(rawValue: "BufferedReader.useLines should resolve with List<String> lambda parameter: \(sampleDiagnostics.map(\.message))")
            )
            }
            do {
                let samplePath = paths[1]
                let sampleDiagnostics = diagnosticsForPath(samplePath, in: ctx)

            #expect(
                !(sampleDiagnostics.contains(where: { $0.severity == .error })),
                Comment(rawValue: "useLines lambda parameter should expose List<String> members: \(sampleDiagnostics.map(\.message))")
            )
            }
            do {
                let samplePath = paths[2]
                let sampleDiagnostics = diagnosticsForPath(samplePath, in: ctx)

            #expect(
                !(sampleDiagnostics.contains(where: { $0.severity == .error })),
                Comment(rawValue: "useLines block return type should flow back to the call site: \(sampleDiagnostics.map(\.message))")
            )
            }
        }
    }
}
#endif
