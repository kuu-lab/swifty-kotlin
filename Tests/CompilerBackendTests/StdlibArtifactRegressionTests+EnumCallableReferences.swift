@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2305: enum type-name references bind the singleton companion for
    /// valueOf while instance members and explicit companion receivers keep
    /// their established function shapes.
    @Test
    func testEnumValueOfCallableReferenceAcrossStdlibModes() throws {
        let artifactPath = try testStdlibArtifactPath()
        let source = """
        enum class E {
            ENTRY;
            fun label(): String = "entry"
        }

        enum class Shadowed {
            ENTRY;
            companion object {
                fun valueOf(name: String): Shadowed = ENTRY
            }
        }

        class Plain(val value: Int) {
            companion object {
                fun from(value: Int): Plain = Plain(value)
            }
        }

        fun box(): String {
            val fromName: (String) -> E = E::valueOf
            val label: (E) -> String = E::label
            val custom: (String) -> Shadowed = Shadowed::valueOf
            val explicitCompanion: (String) -> Shadowed = Shadowed.Companion::valueOf
            val ordinaryCompanion: (Int) -> Plain = Plain.Companion::from
            return if (
                fromName("ENTRY") == E.ENTRY
                    && label(E.ENTRY) == "entry"
                    && custom("ENTRY") == Shadowed.ENTRY
                    && explicitCompanion("ENTRY") == Shadowed.ENTRY
                    && ordinaryCompanion(17).value == 17
                    && E.valueOf("ENTRY") == E.ENTRY
            ) "OK" else "FAIL"
        }

        fun main() { print(box()) }
        """

        let surfaces: [(name: String, libraryPath: String?)] = [
            ("source stdlib", nil),
            ("fresh .kklib", artifactPath),
        ]
        for (surface, libraryPath) in surfaces {
            for optimization in [OptimizationLevel.O0, .O2] {
                let output = try runEnumCallableReference(
                    source,
                    moduleName: "KUU2305EnumCallableReference_\(surface)_\(optimization.rawValue)",
                    stdlibLibraryPath: libraryPath,
                    optLevel: optimization
                )
                #expect(
                    output == "OK",
                    "Unexpected output using \(surface) at \(optimization): \(String(reflecting: output))"
                )
            }
        }
    }

    /// KUU-2850: Enum.name/ordinal property references must use the enum's
    /// ordinal-backed representation when a consumer imports the stdlib artifact.
    @Test
    func testEnumNameOrdinalCallableReferenceGetFromStdlibArtifact() throws {
        let artifactPath = try testStdlibArtifactPath()
        let source = """
        enum class E { I }

        fun main() {
            val name = (E::name).get(E.I)
            val ordinal = (E::ordinal).get(E.I)
            print("$name:$ordinal")
        }
        """

        let output = try runEnumCallableReference(
            source,
            moduleName: "KUU2850EnumNameOrdinalReference",
            stdlibLibraryPath: artifactPath,
            optLevel: .O0,
            issueLabel: "KUU-2850"
        )
        #expect(output == "I:0", "Unexpected enum property-reference output: \(String(reflecting: output))")
    }
}

private func runEnumCallableReference(
    _ source: String,
    moduleName: String,
    stdlibLibraryPath: String?,
    optLevel: OptimizationLevel,
    issueLabel: String = "KUU-2305"
) throws -> String {
    var output = ""
    try withTemporaryFile(contents: source) { inputPath in
        let outputBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .path
        defer { try? FileManager.default.removeItem(atPath: outputBase) }

        let context = CompilationContext(
            options: CompilerOptions(
                moduleName: moduleName,
                inputs: [inputPath],
                outputPath: outputBase,
                emit: .executable,
                target: TargetTriple.hostDefault(),
                optLevel: optLevel,
                includeStdlib: stdlibLibraryPath == nil,
                stdlibLibraryPath: stdlibLibraryPath,
                allowDefaultStdlibLibrary: false
            ),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: StringInterner()
        )

        do {
            try runToKIR(context)
        } catch {
            throw CompilerPipelineError.invalidInput(
                "\(issueLabel) frontend failed: \(error); diagnostics: \(context.diagnostics.diagnostics)"
            )
        }
        do {
            try LoweringPhase().run(context)
        } catch {
            throw CompilerPipelineError.invalidInput(
                "\(issueLabel) lowering failed: \(error); diagnostics: \(context.diagnostics.diagnostics)"
            )
        }
        do {
            try CodegenPhase().run(context)
        } catch {
            throw CompilerPipelineError.invalidInput(
                "\(issueLabel) codegen failed: \(error); diagnostics: \(context.diagnostics.diagnostics)"
            )
        }
        do {
            try LinkPhase().run(context)
        } catch {
            throw CompilerPipelineError.invalidInput(
                "\(issueLabel) link failed: \(error); diagnostics: \(context.diagnostics.diagnostics)"
            )
        }
        #expect(
            !context.diagnostics.hasError,
            "Compilation failed: \(context.diagnostics.diagnostics)"
        )

        let result = try CommandRunner.run(executable: outputBase, arguments: [])
        #expect(result.exitCode == 0, "Execution stderr: \(result.stderr)")
        output = result.stdout
    }
    return output
}
