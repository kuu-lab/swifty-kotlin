@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    // STDLIB-CINTEROP-FN-039: typeOf<T>() from kotlinx.cinterop
    func testCodegenCinteropTypeOfNonNullable() throws {
        let source = """
        import kotlinx.cinterop.typeOf
        import kotlin.reflect.KType

        fun getStringType(): KType = typeOf<String>()

        fun main() {
            val t = getStringType()
            println(t.isMarkedNullable)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CinteropTypeOf",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "false\n")
        }
    }

    func testCodegenCinteropTypeOfNullable() throws {
        let source = """
        import kotlinx.cinterop.typeOf
        import kotlin.reflect.KType

        fun getNullableIntType(): KType = typeOf<Int?>()

        fun main() {
            val t = getNullableIntType()
            println(t.isMarkedNullable)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CinteropTypeOfNullable",
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
