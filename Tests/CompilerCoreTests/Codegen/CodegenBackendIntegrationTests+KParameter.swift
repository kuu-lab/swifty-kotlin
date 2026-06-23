@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {

    func testKParameterPropertyAccessCompiles() throws {
        let source = """
        import kotlin.reflect.KParameter
        import kotlin.reflect.KType

        fun inspectIndex(p: KParameter): Int = p.index

        fun inspectName(p: KParameter): String? = p.name

        fun inspectType(p: KParameter): KType = p.type

        fun inspectOptional(p: KParameter): Boolean = p.isOptional

        fun inspectKind(p: KParameter): Int = p.kind

        fun main() {
            println("kparameter-codegen-ok")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KParameterPropertyAccess",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(
                result.stdout.trimmingCharacters(in: .newlines),
                "kparameter-codegen-ok"
            )
        }
    }

    func testKParameterPropertyAccessInConditional() throws {
        let source = """
        import kotlin.reflect.KParameter

        fun describeKind(p: KParameter): String {
            return when (p.kind) {
                0 -> "INSTANCE"
                1 -> "EXTENSION_RECEIVER"
                else -> "VALUE"
            }
        }

        fun main() {
            println("kparameter-conditional-codegen-ok")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KParameterConditional",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(
                result.stdout.trimmingCharacters(in: .newlines),
                "kparameter-conditional-codegen-ok"
            )
        }
    }

    func testKParameterNullableNameAndIsOptionalCompile() throws {
        let source = """
        import kotlin.reflect.KParameter

        fun label(p: KParameter): String {
            val n = p.name ?: "<no-name>"
            val opt = if (p.isOptional) "?" else ""
            return n + opt
        }

        fun main() {
            println("kparameter-nullable-codegen-ok")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KParameterNullableName",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(
                result.stdout.trimmingCharacters(in: .newlines),
                "kparameter-nullable-codegen-ok"
            )
        }
    }
}

