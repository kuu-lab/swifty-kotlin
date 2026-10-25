@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2232: resolve BigDecimal constants from source and fresh metadata at O0/O2.
    /// This is compile-only coverage; it intentionally does not execute generated functions.
    @Test(arguments: [false, true], [0, 2])
    func testBigDecimalConstantsAcrossStdlibSurfaces(
        useArtifact: Bool,
        optLevelRawValue: Int
    ) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optLevelRawValue))
        let artifactPath = useArtifact ? try BigDecimalZeroArtifact.path.get() : nil
        let source = """
        import java.math.BigDecimal

        fun zero(): BigDecimal = BigDecimal.ZERO
        fun one(): BigDecimal = BigDecimal.ONE
        fun parsedZero(): BigDecimal = "0".toBigDecimal()
        fun compareToZero(value: BigDecimal): Int = value.compareTo(BigDecimal.ZERO)
        fun jsonDecimalToJSON(value: BigDecimal): String =
            if (value == BigDecimal.ZERO) "0" else value.toString()
        fun jsonDecimalIsZero(value: BigDecimal): Boolean =
            value.compareTo(BigDecimal.ZERO) == 0
        fun jsonDecimalIsNegative(value: BigDecimal): Boolean = value < BigDecimal.ZERO
        fun jsonDecimalIsNotNegative(value: BigDecimal): Boolean = value >= BigDecimal.ZERO
        fun jsonDecimalIsWithinUnsignedRange(value: BigDecimal, max: BigDecimal): Boolean =
            value in BigDecimal.ZERO..max
        """

        try withTemporaryFile(contents: source) { inputPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: outputBase) }
            let context = bigDecimalZeroContext(
                inputPath: inputPath,
                outputPath: outputBase,
                artifactPath: artifactPath,
                optLevel: optLevel
            )
            try runToKIR(context)
            try assertNoDiagnosticErrors(context)
            try LoweringPhase().run(context)
            try CodegenPhase().run(context)
        }
    }

    /// A consumer must not be able to assign to the public ZERO property.
    @Test(arguments: [false, true])
    func testBigDecimalZeroRejectsReassignment(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try BigDecimalZeroArtifact.path.get() : nil
        let source = """
        import java.math.BigDecimal
        fun main() { BigDecimal.ZERO = BigDecimal.ONE }
        """
        try withTemporaryFile(contents: source) { inputPath in
            let context = bigDecimalZeroContext(
                inputPath: inputPath,
                outputPath: nil,
                artifactPath: artifactPath,
                optLevel: .O0
            )
            do {
                try runSema(context)
            } catch {
                // Require the specific diagnostic, not just pipeline failure.
            }
            let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.map(\.code) == ["KSWIFTK-SEMA-0014"])
            #expect(errors.first?.message == "Val cannot be reassigned.")
        }
    }

    /// KUU-2233: BigDecimal's Number conversions survive a fresh .kklib and O0/O2 consumers.
    @Test(arguments: [0, 2])
    func testBigDecimalNumberConversionsThroughFreshStdlibArtifact(optLevelRawValue: Int) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optLevelRawValue))
        let artifactPath = try Self.buildStdlibArtifact()
        let source = try diffCaseSource("big_decimal_number_conversions.kt")
        let expected = try CompilerTestSupport.repositoryFileSource(
            "Scripts/diff_cases/big_decimal_number_conversions.expected"
        )

        try withTemporaryFile(contents: source) { inputPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: outputBase) }
            let context = try runCodegenPipeline(
                inputPath: inputPath,
                moduleName: "KUU2233_BigDecimal_\(optLevel.rawValue)",
                outputPath: outputBase,
                optLevel: optLevel,
                allowDefaultStdlibLibrary: false,
                stdlibLibraryPath: artifactPath
            )
            try assertNoDiagnosticErrors(context)
            try LinkPhase().run(context)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "\(optLevel): \(result.stderr)")
            #expect(result.stderr.isEmpty, "\(optLevel): \(result.stderr)")
            #expect(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == expected,
                "Unexpected output at \(optLevel): \(String(reflecting: result.stdout))"
            )
        }
    }

    /// KUU-3061: arithmetic and scale rounding work through a fresh stdlib artifact at O0/O2.
    @Test(arguments: [0, 2])
    func testBigDecimalArithmeticThroughFreshStdlibArtifact(optLevelRawValue: Int) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optLevelRawValue))
        let artifactPath = try Self.buildStdlibArtifact()
        let source = try diffCaseSource("big_decimal_arithmetic.kt")
        let expected = try CompilerTestSupport.repositoryFileSource(
            "Scripts/diff_cases/big_decimal_arithmetic.expected"
        )

        try withTemporaryFile(contents: source) { inputPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: outputBase) }
            let context = try runCodegenPipeline(
                inputPath: inputPath,
                moduleName: "KUU3061_BigDecimalArithmetic_\(optLevel.rawValue)",
                outputPath: outputBase,
                optLevel: optLevel,
                allowDefaultStdlibLibrary: false,
                stdlibLibraryPath: artifactPath
            )
            try assertNoDiagnosticErrors(context)
            try LinkPhase().run(context)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "\(optLevel): \(result.stderr)")
            #expect(result.stderr.isEmpty, "\(optLevel): \(result.stderr)")
            #expect(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == expected,
                "Unexpected output at \(optLevel): \(String(reflecting: result.stdout))"
            )
        }
    }

    /// KUU-3367: the public Double constructor preserves Java's exact binary-to-decimal value.
    @Test(arguments: [0, 2])
    func testBigDecimalDoubleConstructorThroughFreshStdlibArtifact(optLevelRawValue: Int) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optLevelRawValue))
        let artifactPath = try Self.buildStdlibArtifact()
        let source = try diffCaseSource("big_decimal_constructors.kt")
        let expected = try CompilerTestSupport.repositoryFileSource(
            "Scripts/diff_cases/big_decimal_constructors.expected"
        )

        try withTemporaryFile(contents: source) { inputPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: outputBase) }
            let context = try runCodegenPipeline(
                inputPath: inputPath,
                moduleName: "KUU3367_BigDecimalConstructors_\(optLevel.rawValue)",
                outputPath: outputBase,
                optLevel: optLevel,
                allowDefaultStdlibLibrary: false,
                stdlibLibraryPath: artifactPath
            )
            try assertNoDiagnosticErrors(context)
            try LinkPhase().run(context)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "\(optLevel): \(result.stderr)")
            #expect(result.stderr.isEmpty, "\(optLevel): \(result.stderr)")
            #expect(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == expected,
                "Unexpected output at \(optLevel): \(String(reflecting: result.stdout))"
            )
        }
    }

    /// KUU-3400: primitive numbers convert to BigDecimal through the bundled stdlib.
    @Test(arguments: [0, 2])
    func testPrimitiveToBigDecimalThroughFreshStdlibArtifact(optLevelRawValue: Int) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optLevelRawValue))
        let artifactPath = try Self.buildStdlibArtifact()
        let source = try diffCaseSource("kuu_3400_primitive_to_big_decimal.kt")
        let expected = try CompilerTestSupport.repositoryFileSource(
            "Scripts/diff_cases/kuu_3400_primitive_to_big_decimal.expected"
        )

        try withTemporaryFile(contents: source) { inputPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: outputBase) }
            let context = try runCodegenPipeline(
                inputPath: inputPath,
                moduleName: "KUU3400_PrimitiveBigDecimal_\(optLevel.rawValue)",
                outputPath: outputBase,
                optLevel: optLevel,
                allowDefaultStdlibLibrary: false,
                stdlibLibraryPath: artifactPath
            )
            try assertNoDiagnosticErrors(context)
            try LinkPhase().run(context)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "\(optLevel): \(result.stderr)")
            #expect(result.stderr.isEmpty, "\(optLevel): \(result.stderr)")
            #expect(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == expected,
                "Unexpected output at \(optLevel): \(String(reflecting: result.stdout))"
            )
        }
    }
}

private func bigDecimalZeroContext(
    inputPath: String,
    outputPath: String?,
    artifactPath: String?,
    optLevel: OptimizationLevel
) -> CompilationContext {
    CompilationContext(
        options: CompilerOptions(
            moduleName: "KUU2232BigDecimalZero",
            inputs: [inputPath],
            outputPath: outputPath ?? FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path,
            emit: .executable,
            target: TargetTriple.hostDefault(),
            optLevel: optLevel,
            includeStdlib: artifactPath == nil,
            stdlibLibraryPath: artifactPath,
            allowDefaultStdlibLibrary: false
        ),
        sourceManager: SourceManager(),
        diagnostics: DiagnosticEngine(),
        interner: StringInterner()
    )
}

private enum BigDecimalZeroArtifact {
    /// Build a fresh artifact for this test without preparing the default cache.
    static let path: Result<String, Error> = Result {
        let outputBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        return try StdlibArtifactBuilder.build(
            outputBase: outputBase,
            target: TargetTriple.hostDefault()
        )
    }
}
