@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-REFLECT-TYPE-013: KParameter member access codegen integration tests.
///
/// Verifies that the full compiler pipeline (parse → sema → KIR lowering → codegen → link)
/// handles `KParameter` property accesses: `index`, `name`, `type`, `isOptional`, `kind`.
extension CodegenBackendIntegrationTests {

    /// All five KParameter properties compile and link to a native binary without errors.
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

    /// KParameter property accesses in conditional branches compile and link correctly.
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

    /// KParameter.isOptional and KParameter.name accessed together compile correctly.
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
