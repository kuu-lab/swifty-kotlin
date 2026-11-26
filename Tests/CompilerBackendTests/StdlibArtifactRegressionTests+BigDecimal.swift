@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    @Test(arguments: [false, true])
    func testBigDecimalFullyQualifiedConstructorAcrossStdlibSurfaces(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try BigDecimalZeroArtifact.path.get() : nil
        let source = """
        fun main() {
            val integer = java.math.BigInteger("1")
            val decimal = java.math.BigDecimal("1.5")
        }
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
            }
            #expect(!context.diagnostics.hasError, "Unexpected diagnostics: \(context.diagnostics.diagnostics)")
        }
    }

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
            }
            let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.map(\.code) == ["KSWIFTK-SEMA-0014"])
            #expect(errors.first?.message == "Val cannot be reassigned.")
        }
    }

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

    @Test(arguments: [0, 2])
    func testBigDecimalRemUnaryMinusIncDecOperatorsThroughFreshStdlibArtifact(optLevelRawValue: Int) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optLevelRawValue))
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        import java.math.BigDecimal

        var stored = BigDecimal("1.0")

        fun main() {
            val a = BigDecimal("1.10")
            val b = BigDecimal("2.2")
            println(a % b)
            println(BigDecimal("7.5") % BigDecimal("2"))
            println(-a)
            var x = BigDecimal("1.0")
            println(x++)
            println(x)
            println(++x)
            println(x--)
            println(--x)
            println(stored++)
            println(++stored)
            println(stored--)
            println(stored)
            println(a == BigDecimal("1.10"))
            println(a == BigDecimal("1.1"))
            println(a.equals("1.10"))
            println(a.hashCode())
            println(BigDecimal("-1.10").hashCode())
        }
        """
        let expected = """
        1.10
        1.5
        -1.10
        1.0
        2.0
        3.0
        3.0
        1.0
        1.0
        3.0
        3.0
        2.0
        true
        false
        false
        3412
        -3408

        """

        try withTemporaryFile(contents: source) { inputPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: outputBase) }
            let context = try runCodegenPipeline(
                inputPath: inputPath,
                moduleName: "BigDecimalOperators_\(optLevel.rawValue)",
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
    static let path: Result<String, Error> = Result {
        let outputBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        return try StdlibArtifactBuilder.build(
            outputBase: outputBase,
            target: TargetTriple.hostDefault()
        )
    }
}
