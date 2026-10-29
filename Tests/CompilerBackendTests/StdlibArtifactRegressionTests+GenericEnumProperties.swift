@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    @Test(arguments: [false, true], [0, 2])
    func testGenericEnumNameAndOrdinal(useArtifact: Bool, optimization: Int) throws {
        let optLevel: OptimizationLevel = optimization == 0 ? .O0 : .O2
        let artifactPath = useArtifact ? try testStdlibArtifactPath() : nil
        let source = try diffCaseSource("generic_enum_name_ordinal.kt", file: #filePath)
        try withTemporaryFile(contents: source) { path in
            let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path, moduleName: "GenericEnumProperties",
                outputPath: output, optLevel: optLevel,
                allowDefaultStdlibLibrary: false, stdlibLibraryPath: artifactPath
            )
            try assertNoDiagnosticErrors(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stdout == "A\nB\n0\n1\nA, B\n0, 1\nB\n1\nB\nnull\n0\nnull\nC\n1\nC\noverride\nB\nB\n1\nfield\n7\nA\nB\nB\noverride\nA, C\nA\n1\ntrue\ntrue\ntrue\n")
        }
    }

    @Test
    func testGenericEnumPropertiesAcrossLibraryBoundary() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = try testStdlibArtifactPath()
        let sourcePath = directory.appendingPathComponent("Names.kt").path
        let libraryPath = directory.appendingPathComponent("Names").path
        try """
        package names
        private enum class Hidden { A; override fun toString(): String = "hidden-display" }
        enum class Public { P, Q }
        fun exposed(): Enum<*> = Hidden.A
        inline fun <T : Enum<T>> libraryName(value: T): String = value.name
        fun <T : Enum<T>> T.libraryExtensionName(): String = name
        """.write(toFile: sourcePath, atomically: true, encoding: .utf8)
        let library = makeCompilationContext(
            inputs: [sourcePath], moduleName: "EnumNames", emit: .library,
            outputPath: libraryPath, stdlibLibraryPath: stdlib
        )
        try runToLowering(library)
        try assertNoDiagnosticErrors(library)
        try CodegenPhase().run(library)
        let consumerSource = """
        import names.exposed
        import names.libraryName
        import names.Public
        import names.libraryExtensionName
        enum class E { A, B }
        fun main() {
            println(exposed().name)
            println(exposed())
            val display: Any = exposed()
            println(display)
            println(libraryName(E.A))
            println(libraryName(E.B))
            println(Public.Q.libraryExtensionName())
        }
        """
        try withTemporaryFile(contents: consumerSource) { path in
            let output = directory.appendingPathComponent("consumer").path
            let consumer = makeCompilationContext(
                inputs: [path], moduleName: "EnumNamesConsumer", emit: .executable,
                outputPath: output, searchPaths: [libraryPath + ".kklib"], stdlibLibraryPath: stdlib
            )
            try runToLowering(consumer)
            try assertNoDiagnosticErrors(consumer)
            try CodegenPhase().run(consumer)
            try LinkPhase().run(consumer)
            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stdout == "A\nhidden-display\nhidden-display\nA\nB\nQ\n")
        }
    }
}
