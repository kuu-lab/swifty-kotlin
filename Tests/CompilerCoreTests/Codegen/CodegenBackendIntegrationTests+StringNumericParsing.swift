@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testStringToByteAndToByteOrNullExecution() throws {
        let source = """
        fun main() {
            println("42".toByte())
            println("-42".toByte())
            println("+42".toByte())
            println("42".toByteOrNull())
            println("+42".toByteOrNull())
            println("127".toByteOrNull())
            println("128".toByteOrNull())
            println("abc".toByteOrNull())
            println(" 42 ".toByteOrNull())
            try { "999".toByte() } catch (e: Throwable) { println("overflow") }
            try { "abc".toByte() } catch (e: Throwable) { println("invalid") }
            try { " 42 ".toByte() } catch (e: Throwable) { println("whitespace") }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringToByteExecution",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                42
                -42
                42
                42
                42
                127
                null
                null
                null
                overflow
                invalid
                whitespace
                """
                + "\n"
            )
        }
    }

    func testStringToShortAndToShortOrNullExecution() throws {
        let source = """
        fun main() {
            println("1000".toShort())
            println("-1000".toShort())
            println("+1000".toShort())
            println("32767".toShortOrNull())
            println("-32768".toShortOrNull())
            println("32768".toShortOrNull())
            println("40000".toShortOrNull())
            println("abc".toShortOrNull())
            println(" 1000 ".toShortOrNull())
            try { "40000".toShort() } catch (e: Throwable) { println("overflow") }
            try { "abc".toShort() } catch (e: Throwable) { println("invalid") }
            try { " 1000 ".toShort() } catch (e: Throwable) { println("whitespace") }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringToShortExecution",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                1000
                -1000
                1000
                32767
                -32768
                null
                null
                null
                null
                overflow
                invalid
                whitespace
                """
                + "\n"
            )
        }
    }

    func testStringToLongAndToLongOrNullExecution() throws {
        let source = """
        fun main() {
            println("9999999999".toLong())
            println("-9999999999".toLong())
            println("+9999999999".toLong())
            println("9999999999".toLongOrNull())
            println("99999999999999999999".toLongOrNull())
            println("abc".toLongOrNull())
            println(" 9999999999 ".toLongOrNull())
            try { "99999999999999999999".toLong() } catch (e: Throwable) { println("overflow") }
            try { "abc".toLong() } catch (e: Throwable) { println("invalid") }
            try { " 9999999999 ".toLong() } catch (e: Throwable) { println("whitespace") }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringToLongExecution",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                9999999999
                -9999999999
                9999999999
                9999999999
                null
                null
                null
                overflow
                invalid
                whitespace
                """
                + "\n"
            )
        }
    }

    func testStringToFloatAndToFloatOrNullExecution() throws {
        let source = """
        fun main() {
            println("0.5".toFloat())
            println("-2.0".toFloat())
            println("+1.5".toFloat())
            println(" 0.5 ".toFloat())
            println("NaN".toFloat())
            println("Infinity".toFloat())
            println("0.5".toFloatOrNull())
            println("abc".toFloatOrNull())
            println(" ".toFloatOrNull())
            try { "abc".toFloat() } catch (e: Throwable) { println("invalid") }
            try { "  ".toFloat() } catch (e: Throwable) { println("empty") }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringToFloatExecution",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                0.5
                -2.0
                1.5
                0.5
                NaN
                Infinity
                0.5
                null
                null
                invalid
                empty
                """
                + "\n"
            )
        }
    }

    func testStringToBooleanExecution() throws {
        let source = """
        fun main() {
            println("true".toBoolean())
            println("TRUE".toBoolean())
            println("True".toBoolean())
            println("false".toBoolean())
            println("False".toBoolean())
            println("yes".toBoolean())
            println("1".toBoolean())
            println("".toBoolean())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringToBooleanExecution",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                true
                true
                true
                false
                false
                false
                false
                false
                """
                + "\n"
            )
        }
    }

    func testStringToBooleanStrictExecution() throws {
        let source = """
        fun main() {
            println("true".toBooleanStrict())
            println("false".toBooleanStrict())
            try { "True".toBooleanStrict() } catch (e: Throwable) { println("mixed-case") }
            try { "FALSE".toBooleanStrict() } catch (e: Throwable) { println("uppercase") }
            try { "yes".toBooleanStrict() } catch (e: Throwable) { println("non-boolean") }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringToBooleanStrictExecution",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                true
                false
                mixed-case
                uppercase
                non-boolean
                """
                + "\n"
            )
        }
    }

    func testStringToBooleanStrictOrNullExecution() throws {
        let source = """
        fun main() {
            println("true".toBooleanStrictOrNull())
            println("false".toBooleanStrictOrNull())
            println("True".toBooleanStrictOrNull())
            println("FALSE".toBooleanStrictOrNull())
            println("yes".toBooleanStrictOrNull())
            println("".toBooleanStrictOrNull())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringToBooleanStrictOrNullExecution",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                true
                false
                null
                null
                null
                null
                """
                + "\n"
            )
        }
    }
}
