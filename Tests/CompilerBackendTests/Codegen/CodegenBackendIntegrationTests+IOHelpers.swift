@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenBuildListProducesCorrectly() throws {
        let source = """
        fun main() {
            val list = buildList {
                add(1)
                add(2)
            }
            println(list.size)
            println(list.get(0))
            println(list.get(1))
        }
        """

        try assertKotlinOutput(source, moduleName: "BuildListRuntime", expected: "2\n1\n2\n")
    }

    func testCodegenBuildStringCapacityProducesCorrectly() throws {
        let source = """
        fun main() {
            val positional = buildString(16) {
                append("hello")
                append(" world")
            }
            val named = buildString(capacity = 4) {
                append("cap")
            }
            println(positional)
            println(named)
            try {
                println(buildString(-1) { append("bad") })
            } catch (e: Throwable) {
                println("caught")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "BuildStringCapacityRuntime", expected: "hello world\ncap\ncaught\n")
    }

    func testCodegenBuildStringAppendTypedValuesProducesCorrectly() throws {
        let source = """
        fun main() {
            val text = buildString {
                append("value=")
                append('A')
                append(" ")
                append(true)
                append(" ")
                append(42)
                append(" ")
                append(100L)
                append(" ")
                append(3.5f)
                append(" ")
                append(2.25)
                append(" ")
                append(null)
            }
            println(text)
        }
        """

        try assertKotlinOutput(source, moduleName: "BuildStringAppendTypedValuesRuntime", expected: "value=A true 42 100 3.5 2.25 null\n")
    }

    func testCodegenBuildStringBuilderProducesMutableBuilder() throws {
        let source = """
        fun main() {
            val sb = buildStringBuilder {
                append("hello")
                appendLine()
                appendRange("world!", 0, 5)
            }
            sb.append("!")
            println(sb.toString())
            try {
                println(buildStringBuilder(-1) { append("bad") }.toString())
            } catch (e: Throwable) {
                println("caught")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "BuildStringBuilderRuntime", expected: "hello\nworld!\ncaught\n")
    }

    func testCodegenPrintlnNoArgUsesRuntimeNewlineHelper() throws {
        let source = """
        fun main() {
            println()
            println("after")
        }
        """

        try assertKotlinOutput(source, moduleName: "PrintlnNoArgRuntime", expected: "\nafter\n")
    }

    func testCodegenRequireLazyMessageUsesCapturedValue() throws {
        let source = """
        fun main() {
            val suffix = "value"
            try {
                require(false) { suffix }
            } catch (e: Throwable) {
                println(e)
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "RequireLazyRuntime", expected: "Throwable(IllegalArgumentException: value)\n")
    }

    func testCodegenReadLineEOFReturnsNull() throws {
        let source = """
        fun main() {
            val line = readLine()
            println(line)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ReadLineEOF",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(
                executable: "/bin/sh",
                arguments: ["-c", "\"$1\" </dev/null", "sh", outputBase]
            )
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "null\n")
        }
    }

    func testCodegenReadLineEmptyLineReturnsEmptyString() throws {
        let source = """
        fun main() {
            val line = readLine()
            println(line)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ReadLineEmptyLine",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(
                executable: "/bin/sh",
                arguments: ["-c", "printf '\\n' | \"$1\"", "sh", outputBase]
            )
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "\n")
        }
    }

    func testCodegenReadlnReturnsInputLine() throws {
        let source = """
        fun main() {
            val line = readln()
            println(line)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ReadlnInput",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(
                executable: "/bin/sh",
                arguments: ["-c", "echo hello | \"$1\"", "sh", outputBase]
            )
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "hello\n")
        }
    }

    func testCodegenReadlnEOFThrows() throws {
        let source = """
        fun main() {
            try {
                val line = readln()
                println(line)
            } catch (e: RuntimeException) {
                println(e.message)
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ReadlnEOF",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(
                executable: "/bin/sh",
                arguments: ["-c", "\"$1\" </dev/null", "sh", outputBase]
            )
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertTrue(
                normalizedStdout.contains("EOF"),
                "Expected EOF-related message, got: \(normalizedStdout)"
            )
        }
    }

    func testCodegenReadlnOrNullReturnsInputLine() throws {
        let source = """
        fun main() {
            val line = readlnOrNull()
            println(line)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ReadlnOrNullInput",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(
                executable: "/bin/sh",
                arguments: ["-c", "echo hello | \"$1\"", "sh", outputBase]
            )
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "hello\n")
        }
    }

    func testCodegenReadlnOrNullEOFReturnsNull() throws {
        let source = """
        fun main() {
            val line = readlnOrNull()
            println(line)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ReadlnOrNullEOF",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(
                executable: "/bin/sh",
                arguments: ["-c", "\"$1\" </dev/null", "sh", outputBase]
            )
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "null\n")
        }
    }

    func testCodegenPrintNoArgIsNoOp() throws {
        let source = """
        fun main() {
            print()
            println("done")
        }
        """

        try assertKotlinOutput(source, moduleName: "PrintNoArgRuntime", expected: "done\n")
    }
}

