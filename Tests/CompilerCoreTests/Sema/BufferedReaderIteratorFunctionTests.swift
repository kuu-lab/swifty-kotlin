#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - STDLIB-IO-FN-022: BufferedReader.iterator()
//
// Verifies that `kotlin.io.BufferedReader.iterator()` is resolved by Sema so
// that user code calling `reader.iterator()` (or iterating with `for-in`) compiles
// against our synthetic `java.io.BufferedReader` declarations.

@Suite
struct BufferedReaderIteratorFunctionTests {

    // MARK: - Direct iterator() call resolves and types as Iterator<String>

    @Test func testMergedRunToKIR() throws {
        let sources: [String] = [
            """
            package sample0

                    import java.io.File

                    fun sample0() {
                        val reader = File("/dev/null").bufferedReader()
                        val iter = reader.iterator()
                        if (iter.hasNext()) {
                            val first: String = iter.next()
                            println(first)
                        }
                        reader.close()
                    }

            """,
            """
            package sample1

                    import java.io.File

                    fun firstLine(file: File): String? {
                        val reader = file.bufferedReader()
                        val iter = reader.iterator()
                        val result: String? = if (iter.hasNext()) iter.next() else null
                        reader.close()
                        return result
                    }

                    fun sample1() {
                        println(firstLine(File("/dev/null")))
                    }

            """,
            """
            package sample2

                    import java.io.File

                    fun sample2() {
                        File("/dev/null").bufferedReader().use { reader ->
                            val iter = reader.iterator()
                            while (iter.hasNext()) {
                                println(iter.next())
                            }
                        }
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
                "BufferedReader.iterator() should resolve to Iterator<String>: \(sampleDiagnostics.map(\.message))"
            )
            }
            do {
                let samplePath = paths[1]
                let sampleDiagnostics = diagnosticsForPath(samplePath, in: ctx)

            #expect(
                !sampleDiagnostics.contains(where: { $0.severity == .error }),
                "iter.next() on BufferedReader iterator should type as String: \(sampleDiagnostics.map(\.message))"
            )
            }
            do {
                let samplePath = paths[2]
                let sampleDiagnostics = diagnosticsForPath(samplePath, in: ctx)

            #expect(
                !sampleDiagnostics.contains(where: { $0.severity == .error }),
                "BufferedReader.iterator() should resolve inside Closeable.use { } block: \(sampleDiagnostics.map(\.message))"
            )
            }
        }
    }
}
#endif
