@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

/// STDLIB-ARTIFACT-001: shared stdlib artifact (.kklib) is correctly consumed
/// by a user module. This is a regression test for the `uuid_basic` shared-path
/// failure where imported globals such as `Uuid.Companion.NIL` were not declared
/// in the consumer module, causing `kk_array_get_inbounds` to receive a null
/// array pointer.
final class StdlibArtifactRegressionTests: XCTestCase {

    private static let sharedArtifactLock = NSLock()
    nonisolated(unsafe) private static var sharedArtifactPath: String?

    private static func buildStdlibArtifact() throws -> String {
        sharedArtifactLock.lock()
        defer { sharedArtifactLock.unlock() }

        if let cached = sharedArtifactPath {
            return cached
        }

        let artifactBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .path
        let ctx = makeCompilationContext(
            inputs: [],
            moduleName: "KSwiftKStdlib",
            emit: .library,
            outputPath: artifactBase,
            includeStdlib: true,
            stdlibOnly: true
        )
        try runToKIR(ctx)
        try LoweringPhase().run(ctx)
        try CodegenPhase().run(ctx)

        let artifactPath = artifactBase + ".kklib"
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: artifactPath),
            "stdlib artifact directory should be emitted"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: artifactPath + "/manifest.json"),
            "stdlib artifact should contain manifest.json"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: artifactPath + "/metadata.bin"),
            "stdlib artifact should contain metadata.bin"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: artifactPath + "/objects"),
            "stdlib artifact should contain objects directory"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: artifactPath + "/inline-kir"),
            "stdlib artifact should contain inline-kir directory"
        )

        sharedArtifactPath = artifactPath
        return artifactPath
    }

    func testUuidBasicSharedPathPrintsOk() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        @file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

        import kotlin.uuid.Uuid

        fun main() {
            val uuidStr = "550e8400-e29b-41d4-a716-446655440000"
            val nilStr = "00000000-0000-0000-0000-000000000000"

            val parsed = Uuid.parse(uuidStr)
            println("parse roundtrip: ${parsed.toString() == uuidStr}")

            val nil = Uuid.NIL
            println("nil string: ${nil.toString() == nilStr}")
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "parse roundtrip: true\nnil string: true\n")
        }
    }

    /// STDLIB-ARTIFACT-002: `java.math.BigInteger` constructor and throwing
    /// instance methods work through the shared stdlib artifact. The String
    /// constructor is a runtime factory (`kk_biginteger_fromString`) and must
    /// not receive an implicit `this`; `divide`/`modInverse`/`modPow` carry
    /// the `outThrown` channel and must be emitted as throwing calls.
    func testBigIntegerFactoryAndThrowingMethodsSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        import java.math.BigInteger

        fun main() {
            val a = BigInteger("100")
            val b = BigInteger("200")
            val sum = a.add(b)
            val quotient = b.divide(a)
            val modInv = BigInteger("3").modInverse(BigInteger("11"))
            val modPow = BigInteger("3").modPow(BigInteger("4"), BigInteger("7"))
            println("${sum.toString()} ${quotient.toString()} ${modInv.toString()} ${modPow.toString()}")
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "300 2 4 4\n")
        }
    }
}
