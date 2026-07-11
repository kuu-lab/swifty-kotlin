@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    /// A class with two constructors where the first-declared one delegates
    /// via `this(...)` to the second used to resolve back to itself instead
    /// of its sibling, because KIR lowering picked the delegation target by
    /// taking the first FQ-name match without excluding the constructor
    /// being lowered. That caused infinite self-recursion at runtime. This
    /// case needs no import alias or cross-package name collision to
    /// reproduce -- overload/self selection was the actual bug.
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
            XCTAssertEqual(
                result.exitCode, 0,
                "Compilation failed. Diagnostics: \(result.diagnostics.map { "\($0.code): \($0.message)" })"
            )

            // Bounded timeout: a regression here is an infinite recursion
            // that would otherwise hang the test run indefinitely.
            let runResult = try CommandRunner.run(executable: outputBase, arguments: [], timeout: 30)
            let normalizedStdout = runResult.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "42\n")
        }
    }

    /// Reproduces the originally reported shape of the bug: two classes
    /// sharing the simple name `Widget` in different packages, one
    /// aliased-imported into the other, with a delegating constructor whose
    /// delegation argument constructs the aliased sibling. The alias turned
    /// out to be a red herring (see the sibling-overload test above for the
    /// real mechanism), but this case pins down the exact user-facing
    /// scenario that surfaced the bug during the KSP-466 migration.
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
            XCTAssertEqual(
                result.exitCode, 0,
                "Compilation failed. Diagnostics: \(result.diagnostics.map { "\($0.code): \($0.message)" })"
            )

            let runResult = try CommandRunner.run(executable: outputBase, arguments: [], timeout: 30)
            let normalizedStdout = runResult.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "42\n")
        }
    }
}
