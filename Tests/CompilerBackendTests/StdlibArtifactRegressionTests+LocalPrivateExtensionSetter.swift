@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2416: local classes can call a private member-extension setter from its owner.
    @Test(arguments: [true, false], [0, 2])
    func testLocalClassWritesPrivateMemberExtensionProperty(fromSource: Bool, optimization: Int) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optimization))
        let artifactPath = fromSource ? nil : try Self.buildStdlibArtifact()
        let source = """
        class A {
            var result = "Fail"

            private var Int.foo: String
                get() = result
                private set(value) {
                    result = value
                }

            fun run(): String {
                class O {
                    fun run() {
                        42.foo = "OK"
                    }
                }
                O().run()
                return (-42).foo
            }
        }

        fun box(): String = A().run()

        class Owner {
            var result = "FAIL"

            private var Int.value: String
                get() = result
                private set(value) {
                    result = value
                }

            fun run(): String {
                class Local {
                    fun write() { 42.value = "OK" }
                }
                Local().write()
                return (-42).value
            }

            fun directWrite(): String {
                42.value = "OK"
                return (-42).value
            }
        }

        fun minimumBox(): String = Owner().run()

        var publicResult = "FAIL"
        var Int.publicValue: String
            get() = publicResult
            set(value) { publicResult = value }

        fun publicExtensionControl(): String {
            class Local { fun write() { 42.publicValue = "OK" } }
            Local().write()
            return publicResult
        }

        fun main() {
            println(box())
            println(minimumBox())
            println(Owner().directWrite())
            println(publicExtensionControl())
        }
        """

        try withTemporaryFile(contents: source) { inputPath in
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: output) }
            let options = CompilerOptions(
                moduleName: "LocalPrivateExtensionSetter",
                inputs: [inputPath],
                outputPath: output,
                emit: .executable,
                target: CompilerTestSupport.defaultTargetTriple(),
                optLevel: optLevel,
                includeStdlib: fromSource,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            let ctx = CompilationContext(
                options: options,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try assertNoDiagnosticErrors(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: output, arguments: [], timeout: 10)
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "OK\nOK\nOK\nOK\n")
            #expect(result.stderr.isEmpty)
        }
    }
}
