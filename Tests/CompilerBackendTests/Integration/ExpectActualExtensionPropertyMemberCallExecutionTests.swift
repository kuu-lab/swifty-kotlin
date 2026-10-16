#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct ExpectActualExtensionPropertyMemberCallExecutionTests {
    @Test(arguments: [0, 2])
    func pairedExtensionPropertyMemberCallsUseTheActualGetter(optLevel: Int) throws {
        let optimization = try #require(OptimizationLevel(rawValue: optLevel))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try withTemporaryFiles(contents: [
            """
            package x
            expect abstract class B
            expect val B.n: String
            """,
            """
            package x
            actual abstract class B {
                actual override fun hashCode(): Int = n.hashCode()
                actual override fun equals(other: Any?): Boolean = n.length == 4
                actual override fun toString(): String = "base"
            }
            private val Impl: B = object : B() {}
            actual val B.n: String get() = toString()
            fun main() {
                Impl.hashCode()
                Impl.equals(Impl)
            }
            """,
        ]) { inputs in
            let output = directory.appendingPathComponent("expect-actual-extension-property-member-call").path
            let options = CompilerOptions(
                moduleName: "ExpectActualExtensionPropertyMemberCall",
                inputs: inputs,
                outputPath: output,
                emit: .object,
                target: CompilerTestSupport.defaultTargetTriple(),
                optLevel: optimization,
                includeStdlib: false,
                stdlibLibraryPath: nil,
                allowDefaultStdlibLibrary: false
            )
            try assertCompilationSucceeded(
                makeTestDriver().runForTesting(options: options),
                context: "paired extension property used as a member-call receiver in actual members"
            )

            let objectPath = output + ".o"
            let symbols = try CommandRunner.run(
                executable: CommandRunner.resolveExecutable("nm", fallback: "/usr/bin/nm"),
                arguments: ["-u", objectPath]
            )
            #expect(symbols.exitCode == 0, "nm failed: \(symbols.stderr)")

            let symbolLines = symbols.stdout.split(separator: "\n")
            let referencesBareGetter = symbolLines.contains { line in
                let fields = line.split(whereSeparator: \.isWhitespace)
                guard let symbol = fields.last else { return false }
                return symbol.drop(while: { $0 == "_" }) == "get"
            }
            #expect(!referencesBareGetter, "object references an unresolved bare _get symbol")
        }
    }
}
#endif
