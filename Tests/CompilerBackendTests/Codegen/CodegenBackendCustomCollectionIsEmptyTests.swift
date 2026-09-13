@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendCustomCollectionIsEmptyTests {
    private func runExecutablePipeline(
        inputPath: String,
        moduleName: String,
        outputPath: String
    ) throws -> CompilationContext {
        let options = CompilerOptions(
            moduleName: moduleName,
            inputs: [inputPath],
            outputPath: outputPath,
            emit: .executable,
            target: defaultTargetTriple()
        )
        let ctx = CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: StringInterner()
        )
        try runToKIR(ctx)
        try LoweringPhase().run(ctx)
        try CodegenPhase().run(ctx)
        return ctx
    }

    private func assertKotlinOutput(
        _ source: String,
        moduleName: String,
        expected: String
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runExecutablePipeline(
                inputPath: path,
                moduleName: moduleName,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == expected)
        }
    }

    // A user-defined AbstractCollection subclass has no runtime list/set box,
    // so a Collection<T>-typed receiver's isEmpty()/size dispatch through the
    // Collection interface's itable getter slot (kk_itable_lookup_dynamic +
    // runtimeCollectionSizeGetterSlot in RuntimeCollectionHelpers.swift)
    // instead of a concrete-type runtime bridge. That slot number must track
    // Collection's own vtable method count; see KSP-960 (#6172), which shrank
    // it by removing the synthetic Collection.random/randomOrNull members
    // once they became source-backed extensions.
    @Test
    func testCodegenCustomAbstractCollectionIsEmptyUsesItableDispatch() throws {
        let source = """
        class CustomCollection : AbstractCollection<String?>() {
            override val size: Int get() = 1
            override fun iterator(): Iterator<String?> = emptyList<String?>().iterator()
        }

        fun collectionIsEmpty(value: Collection<String?>): Boolean = value.isEmpty()

        fun main() {
            println(collectionIsEmpty(CustomCollection()))
        }
        """

        try assertKotlinOutput(source, moduleName: "CustomCollectionIsEmpty", expected: "false\n")
    }
}
#endif
