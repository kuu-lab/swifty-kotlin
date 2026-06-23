@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesRangeRandomEdgeCases() throws {
        let source = """
        import kotlin.random.Random

        fun main() {
            val intValue = (1..5).random()
            println(
                intValue == 1 ||
                intValue == 2 ||
                intValue == 3 ||
                intValue == 4 ||
                intValue == 5
            )

            val longValue = (1L..5L).random()
            println(
                longValue == 1L ||
                longValue == 2L ||
                longValue == 3L ||
                longValue == 4L ||
                longValue == 5L
            )

            val charValue = ('a'..'f').random()
            println(
                charValue == 'a' ||
                charValue == 'b' ||
                charValue == 'c' ||
                charValue == 'd' ||
                charValue == 'e' ||
                charValue == 'f'
            )

            val uintValue = (1u..5u).random()
            println(
                uintValue == 1u ||
                uintValue == 2u ||
                uintValue == 3u ||
                uintValue == 4u ||
                uintValue == 5u
            )

            val ulongValue = (1uL..5uL).random()
            println(
                ulongValue == 1uL ||
                ulongValue == 2uL ||
                ulongValue == 3uL ||
                ulongValue == 4uL ||
                ulongValue == 5uL
            )

            val random = Random(7)

            val randomCharValue = ('a'..'z').random(random)
            val randomIntValue = (10..20).random(random)
            val randomLongValue = (100L..110L).random(random)
            val randomUIntValue = (10u..20u).random(random)
            val randomULongValue = (100uL..110uL).random(random)

            println(randomCharValue in 'a'..'z')
            println(randomIntValue in 10..20)
            println(randomLongValue in 100L..110L)
            println(randomUIntValue in 10u..20u)
            println(randomULongValue in 100uL..110uL)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RangeRandomEdgeCases",
            expected:
                """
                true
                true
                true
                true
                true
                true
                true
                true
                true
                true
                """ + "\n"
        )
    }

    func testCodegenCompilesRangeRandomWithRandomOverloads() throws {
        let source = """
        import kotlin.random.Random
        import kotlin.ranges.*

        fun useRandom(r: Random): Boolean {
            val intValue = (1..5).random(r)
            val longValue = (10L..15L).random(r)
            val charValue = ('a'..'f').random(r)
            val uintValue = (1u..5u).random(r)
            val ulongValue = (1uL..5uL).random(r)
            return intValue >= 1 &&
                longValue >= 10L &&
                charValue >= 'a' &&
                uintValue >= 1u &&
                ulongValue >= 1uL
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "RangeRandomWithRandomOverloads",
                emit: .object,
                outputPath: outputBase
            )
            let objectPath = try XCTUnwrap(ctx.generatedObjectPath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: objectPath))
        }
    }
}

