#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendConstructorDelegationTests {

    @Test
    func testCodegenConstructorDelegationSelectsSiblingOverloadNotItself() throws {
        let source = """
        class Box {
            val total: Int

            constructor(seed: Int) : this(seed, 0)

            constructor(a: Int, b: Int) {
                total = a + b
            }
        }

        fun main() {
            println(Box(42).total)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let fm = FileManager.default
            let outputBase = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            defer { try? fm.removeItem(atPath: outputBase) }

            let options = makeTestOptions(
                moduleName: "ConstructorDelegationSelfRecursionGuard",
                inputs: [path],
                outputPath: outputBase,
                emit: .executable
            )
            let result = makeTestDriver().runForTesting(options: options)
            #expect(
                result.exitCode == 0,
                "Compilation failed. Diagnostics: \(result.diagnostics.map { "\($0.code): \($0.message)" })"
            )

            let runResult = try CommandRunner.run(executable: outputBase, arguments: [], timeout: 30)
            let normalizedStdout = runResult.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "42\n")
        }
    }

    @Test
    func testCodegenConstructorDelegationResolvesAliasedCrossPackageSiblingName() throws {
        let alphaSource = """
        package alpha

        class Widget(val tag: Int)
        """
        let betaSource = """
        package beta

        import alpha.Widget as AliasedWidget

        class Widget {
            val inner: AliasedWidget

            constructor(seed: Int) : this(AliasedWidget(seed))

            constructor(w: AliasedWidget) {
                inner = w
            }
        }
        """
        let mainSource = """
        import beta.Widget

        fun main() {
            val w = Widget(42)
            println(w.inner.tag)
        }
        """

        try withTemporaryFiles(contents: [alphaSource, betaSource, mainSource]) { paths in
            let fm = FileManager.default
            let outputBase = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            defer { try? fm.removeItem(atPath: outputBase) }

            let options = makeTestOptions(
                moduleName: "ConstructorDelegationAliasedCrossPackageSiblingName",
                inputs: paths,
                outputPath: outputBase,
                emit: .executable
            )
            let result = makeTestDriver().runForTesting(options: options)
            #expect(
                result.exitCode == 0,
                "Compilation failed. Diagnostics: \(result.diagnostics.map { "\($0.code): \($0.message)" })"
            )

            let runResult = try CommandRunner.run(executable: outputBase, arguments: [], timeout: 30)
            let normalizedStdout = runResult.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "42\n")
        }
    }
}
#endif
