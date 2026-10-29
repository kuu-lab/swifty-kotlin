import Foundation
import Testing
@testable import CompilerCore

@Suite
struct JavaLangMathTests {
    @Test(arguments: [0, 2])
    func commonMathAndIntegerHelpersAreAvailable(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourcePath = directory.appendingPathComponent("consumer.kt").path
        let outputPath = directory.appendingPathComponent("consumer").path
        let source = """
        fun main() {
            println(java.lang.Math.E > 2.7)
            println(Math.PI == kotlin.math.PI)
            println(Math.abs(-5) == 5 && Math.abs(-6L) == 6L)
            println(Math.max(1, 2) == 2 && Math.min(1L, 2L) == 1L)
            println(Math.max(1.0f, 2.0f) == 2.0f && Math.min(1.0, 2.0) == 1.0)
            println(Math.sqrt(4.0) == 2.0 && Math.pow(2.0, 3.0) == 8.0)
            println(Math.sin(0.0) == 0.0 && Math.cbrt(27.0) == 3.0)
            println(Math.round(2.5f) == 3 && Math.round(2.5) == 3L)
            println(Math.rint(2.5) == 2.0 && Math.rint(-2.5) == -2.0)
            println(Math.getExponent(1.0) == 0 && Math.getExponent(0.0f) == -127)
            println(Math.copySign(1.0, -0.0) < 0.0 && Math.nextAfter(1.0, 2.0) > 1.0)
            println(Math.scalb(1.5, 3) == 12.0 && Math.fma(2.0, 3.0, 4.0) == 10.0)
            println(Math.addExact(20, 22) == 42 && Math.multiplyExact(6L, 7) == 42L)
            println(Math.multiplyHigh(-2L, 3L) == -1L)
            println(Math.floorDiv(-4, 3) == -2 && Math.floorMod(-4L, 3) == 2)
            println(Math.clamp(5, 1, 4) == 4)
            println(Math.random() >= 0.0 && Math.random() < 1.0)
            println(Math.TAU == Math.PI * 2.0)
            println(kotlin.math.abs(Math.asinh(1.0) - 0.881373587019543) < 1e-15)
            println(Math.ceilDiv(-4, 3) == -1 && Math.ceilMod(-4L, 3) == -1)
            println(Math.floorDivExact(-4, 3) == -2 && Math.ceilDivExact(-4, 3) == -1)
            println(Math.divideExact(42, 2) == 21 && Math.powExact(3, 4) == 81)
            println(Math.unsignedPowExact(-1, 1) == -1 && Math.unsignedMultiplyExact(2L, 3L) == 6L)
            println(Math.unsignedMultiplyHigh(-1L, 2L) == 1L && Math.clamp(9L, 1, 7) == 7)
        }
        """
        try source.write(toFile: sourcePath, atomically: true, encoding: .utf8)

        let options = CompilerOptions(
            moduleName: "KUU3342Math",
            inputs: [sourcePath],
            outputPath: outputPath,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: false
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))

        let result = try CommandRunner.run(executable: outputPath, arguments: [])
        #expect(result.exitCode == 0, "stderr: \(result.stderr)")
        #expect(result.stdout == Array(repeating: "true", count: 24).joined(separator: "\n") + "\n")
        #expect(result.stderr.isEmpty, "stderr: \(result.stderr)")
    }
}
