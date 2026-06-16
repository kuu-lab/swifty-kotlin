@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    // STDLIB-IO-PATH-FN-011: Path.createSymbolicLinkPointingTo end-to-end execution test
    func testCodegenPathCreateSymbolicLinkPointingToCreatesLinkAndIsReadable() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let targetURL = rootURL.appendingPathComponent("target.txt")
        let linkURL = rootURL.appendingPathComponent("link.txt")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try Data("hello symlink".utf8).write(to: targetURL)

        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.createSymbolicLinkPointingTo
        import kotlin.io.path.readText

        fun main() {
            val target = Path("\(targetURL.path)")
            val link = Path("\(linkURL.path)")
            link.createSymbolicLinkPointingTo(target)
            println(link.readText())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "PathCreateSymbolicLink",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "hello symlink\n")
        }
    }
}
