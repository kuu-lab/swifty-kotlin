@testable import CompilerCore
import Foundation
import XCTest

// STDLIB-CINTEROP-FN-038: CPointer<T>?.toLong() end-to-end codegen tests.
//
// CPointer<T>?.toLong() returns the raw pointer address as Long.
// - null pointer  → 0L
// - non-null pointer → non-zero address (non-deterministic, test with != 0L)

extension CodegenBackendIntegrationTests {

    // MARK: - Null pointer returns 0

    func testCPointerToLongNullReturnsZero() throws {
        let source = """
        import kotlinx.cinterop.ByteVar
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.toLong

        fun main() {
            val nullPtr: CPointer<ByteVar>? = null
            println(nullPtr.toLong())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CPointerToLongNull",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "0\n")
        }
    }

    // MARK: - Function wrapper compiles and links

    func testCPointerToLongFunctionWrapperCompilesAndLinks() throws {
        let source = """
        import kotlinx.cinterop.ByteVar
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.toLong

        fun pointerAddress(p: CPointer<ByteVar>?): Long = p.toLong()

        fun main() {
            println(pointerAddress(null))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CPointerToLongWrapper",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "0\n")
        }
    }

    // MARK: - Return type is Long (64-bit)

    func testCPointerToLongReturnTypeIsLong() throws {
        let source = """
        import kotlinx.cinterop.ByteVar
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.toLong

        fun main() {
            val nullPtr: CPointer<ByteVar>? = null
            val addr: Long = nullPtr.toLong()
            println(addr == 0L)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CPointerToLongReturnType",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "true\n")
        }
    }
}
