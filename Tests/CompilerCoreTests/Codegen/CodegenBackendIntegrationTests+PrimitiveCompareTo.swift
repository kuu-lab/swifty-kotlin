@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    /// An explicit `.compareTo()` member call on a primitive `Comparable` type
    /// must lower to `kk_primitive_compareTo` instead of emitting an undefined
    /// external `_compareTo` reference (which previously failed to link).
    ///
    /// Covers Int both directly and inside a `(Int, Int) -> Int` lambda, plus
    /// Long, Double (direct and inside a lambda), and Boolean. Each result is
    /// the sign of the comparison (-1/0/1), matching kotlinc / the JDK
    /// `Integer.compare` / `Long.compare` / `Double.compare` semantics.
    func testCodegenCompilesPrimitiveCompareTo() throws {
        let source = """
        fun main() {
            // Int — direct member call
            println(10.compareTo(20))
            println(20.compareTo(10))
            println(7.compareTo(7))
            // Int — inside a (Int, Int) -> Int lambda
            val cmpInt: (Int, Int) -> Int = { x, y -> x.compareTo(y) }
            println(cmpInt(30, 5))
            // Long
            println(100L.compareTo(200L))
            // Double — direct and inside a (Double, Double) -> Int lambda
            println(2.5.compareTo(1.5))
            val cmpDouble: (Double, Double) -> Int = { x, y -> x.compareTo(y) }
            println(cmpDouble(1.0, 9.0))
            // Boolean (false < true)
            println(false.compareTo(true))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "PrimitiveCompareTo",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "-1\n1\n0\n1\n-1\n1\n-1\n-1\n")
        }
    }
}
