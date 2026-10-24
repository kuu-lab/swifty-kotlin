@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2822: BigInteger.compareTo must link through both stdlib surfaces.
    @Test
    func testBigIntegerCompareToAndPriorityQueueAcrossStdlibSurfaces() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let caseBase = repoRoot.appendingPathComponent("Scripts/diff_cases/big_integer_compare_to")
        let source = caseBase.appendingPathExtension("kt").path
        let expected = try String(
            contentsOf: caseBase.appendingPathExtension("expected"), encoding: .utf8
        )
        let artifactPath = try Self.buildStdlibArtifact()

        for (surface, libraryPath) in [("source", nil), ("artifact", artifactPath)] {
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: outputBase) }
            let context = try runCodegenPipeline(
                inputPath: source,
                moduleName: "KUU2822BigIntegerCompareTo",
                outputPath: outputBase,
                optLevel: .O0,
                allowDefaultStdlibLibrary: false,
                stdlibLibraryPath: libraryPath
            )
            try assertNoDiagnosticErrors(context)
            try LinkPhase().run(context)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "\(surface): \(result.stderr)")
            #expect(result.stderr.isEmpty, "\(surface): \(result.stderr)")
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == expected, "\(surface)")
        }
    }

    /// KUU-2010: value equality must survive source injection and metadata import.
    /// Expected output was measured with Kotlin 2.3.10 and JDK 17.
    /// Multiplication-derived cases remain in the diff fixtures; KUU-2026 blocks them.
    @Test
    func testBigIntegerEqualityAcrossStdlibSurfaces() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let artifactPath = try Self.buildStdlibArtifact()

        for caseName in ["big_integer_value_equality"] {
            let caseBase = repoRoot.appendingPathComponent("Scripts/diff_cases/\(caseName)")
            let expected = try String(contentsOf: caseBase.appendingPathExtension("expected"), encoding: .utf8)
            for (surface, libraryPath) in [("source", nil), ("artifact", artifactPath)] {
                for optLevel in [OptimizationLevel.O0, .O2] {
                    let outputBase = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString).path
                    defer { try? FileManager.default.removeItem(atPath: outputBase) }
                    let context = try runCodegenPipeline(
                        inputPath: caseBase.appendingPathExtension("kt").path,
                        moduleName: "BigIntegerEquality",
                        outputPath: outputBase,
                        optLevel: optLevel,
                        allowDefaultStdlibLibrary: false,
                        stdlibLibraryPath: libraryPath
                    )
                    try assertNoDiagnosticErrors(context)
                    try LinkPhase().run(context)
                    let result = try CommandRunner.run(executable: outputBase, arguments: [])
                    let route = "\(caseName), \(surface), \(optLevel)"
                    #expect(result.exitCode == 0, "\(route): \(result.stderr)")
                    #expect(result.stderr.isEmpty, "\(route): \(result.stderr)")
                    #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == expected, "\(route)")
                }
            }
        }
    }

    /// KUU-2011: preserve the exact ZERO reproducer and arithmetic controls
    /// through source injection and freshly serialized public metadata.
    @Test(arguments: [false, true], [0, 2])
    func testBigIntegerZeroAcrossStdlibSurfaces(
        useArtifact: Bool,
        optLevelRawValue: Int
    ) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optLevelRawValue))
        let artifactPath = useArtifact ? try BigIntegerZeroArtifact.path.get() : nil
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for (fixture, expected) in [
            ("big_integer_zero", "0\n0\n"),
            ("big_integer_zero_controls", "0\n0\n0\n0\n0\n0\n1\n1\n-6\n408\n0\n"),
        ] {
            let source = try String(
                contentsOf: repoRoot.appendingPathComponent("Scripts/diff_cases/\(fixture).kt"),
                encoding: .utf8
            )
            try withTemporaryFile(contents: source) { inputPath in
                let outputBase = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: outputBase) }
                let ctx = bigIntegerZeroContext(
                    inputPath: inputPath, outputPath: outputBase,
                    artifactPath: artifactPath, optLevel: optLevel
                )
                try runToKIR(ctx)
                try assertNoDiagnosticErrors(ctx)
                try LoweringPhase().run(ctx)
                try CodegenPhase().run(ctx)
                try LinkPhase().run(ctx)
                let result = try CommandRunner.run(executable: outputBase, arguments: [])
                #expect(result.exitCode == 0)
                #expect(result.stderr.isEmpty)
                #expect(result.stdout == expected, "\(fixture), artifact=\(useArtifact), \(optLevel)")
            }
        }
    }

    /// A consumer must not be able to replace the public val via either surface.
    @Test(arguments: [false, true])
    func testBigIntegerZeroRejectsReassignment(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try BigIntegerZeroArtifact.path.get() : nil
        let source = """
        package consumer
        import java.math.BigInteger
        fun main() { BigInteger.ZERO = BigInteger.ONE }
        """
        try withTemporaryFile(contents: source) { inputPath in
            let ctx = bigIntegerZeroContext(
                inputPath: inputPath, outputPath: nil,
                artifactPath: artifactPath, optLevel: .O0
            )
            do {
                try runSema(ctx)
            } catch {
                // Require the specific diagnostic, not just pipeline failure.
            }
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.map(\.code) == ["KSWIFTK-SEMA-0014"])
            #expect(errors.first?.message == "Val cannot be reassigned.")
        }
    }
}

private func bigIntegerZeroContext(
    inputPath: String,
    outputPath: String?,
    artifactPath: String?,
    optLevel: OptimizationLevel
) -> CompilationContext {
    CompilationContext(
        options: CompilerOptions(
            moduleName: "KUU2011BigIntegerZero",
            inputs: [inputPath],
            outputPath: outputPath ?? FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path,
            emit: .executable, target: TargetTriple.hostDefault(), optLevel: optLevel,
            includeStdlib: artifactPath == nil,
            stdlibLibraryPath: artifactPath, allowDefaultStdlibLibrary: false
        ),
        sourceManager: SourceManager(), diagnostics: DiagnosticEngine(),
        interner: StringInterner()
    )
}

private enum BigIntegerZeroArtifact {
    /// Build one fresh artifact for this matrix without preparing the default cache.
    static let path: Result<String, Error> = Result {
        let outputBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        return try StdlibArtifactBuilder.build(
            outputBase: outputBase,
            target: TargetTriple.hostDefault()
        )
    }
}
