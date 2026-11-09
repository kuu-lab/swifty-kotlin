#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendRangeEdgeCasesTests {

    @Test
    func testCodegenLongRangeFirstAndLastOrNull() throws {
        let source = """
        fun main() {
            println((1L..5L).firstOrNull())
            println((1L..5L).lastOrNull())
            println((10L..1L).firstOrNull())
            println((10L..1L).lastOrNull())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "LongRangeFirstLastOrNull",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
                    == """
                    1
                    5
                    null
                    null
                    """ + "\n"
            )
        }
    }

    @Test
    func testCodegenProgressionPureKotlinConstructorsAndStep() throws {
        let source = """
        fun main() {
            // Int until & rangeUntil
            val r1 = 1 until 5
            println("${r1.first}..${r1.last}")
            val r1u = 1..<5
            println("${r1u.first}..${r1u.last}")
            val r1Empty = 1 until Int.MIN_VALUE
            println(r1Empty.isEmpty())

            // Long until
            val r2 = 1L until 5L
            println("${r2.first}..${r2.last}")
            val r2Empty = 1L until Long.MIN_VALUE
            println(r2Empty.isEmpty())

            // Char until
            val r3 = 'a' until 'e'
            println("${r3.first}..${r3.last}")

            // Unsigned ranges & until
            val r4 = 1u..5u
            println("${r4.first}..${r4.last}")
            val r4u = 1u until 5u
            println("${r4u.first}..${r4u.last}")
            val r5 = 1uL..5uL
            println("${r5.first}..${r5.last}")
            val r5u = 1uL until 5uL
            println("${r5u.first}..${r5u.last}")

            // Step
            val s1 = (1..9) step 2
            println(s1.toList().joinToString(","))

            val s2 = (1L..10L) step 3L
            println(s2.toList().joinToString(","))

            val s3 = ('a'..'g') step 2
            println(s3.toList().joinToString(","))

            val s4 = (9 downTo 1) step 2
            println(s4.toList().joinToString(","))

            try {
                (1..5) step 0
                println("no exception")
            } catch (e: IllegalArgumentException) {
                println(e.message)
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ProgressionConstructorsPureKotlin",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
                    == """
                    1..4
                    1..4
                    true
                    1..4
                    true
                    a..d
                    1..5
                    1..4
                    1..5
                    1..4
                    1,3,5,7,9
                    1,4,7,10
                    a,c,e,g
                    9,7,5,3,1
                    Step must be positive, was: 0.
                    """ + "\n"
            )
        }
    }
}
#endif
