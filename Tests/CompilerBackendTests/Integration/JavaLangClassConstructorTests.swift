import Foundation
@testable import CompilerCore
import Testing

@Suite(.serialized)
struct JavaLangClassConstructorTests {
    @Test(arguments: [0, 2])
    func constructorLookupAndInstantiationFromFreshArtifact(optimization: Int) throws {
        try assertConstructorLookupAndInstantiation(fromSource: false, optimization: optimization)
    }

    @Test
    func constructorLookupAndInstantiationFromBundledSource() throws {
        // Source-injected O2 fails with BACKEND-1006 on baseline d084138 too, even for bare print("OK").
        try assertConstructorLookupAndInstantiation(fromSource: true, optimization: 0)
    }

    private func assertConstructorLookupAndInstantiation(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("main.kt")
        let output = directory.appendingPathComponent("constructor_lookup")
        try """
        import java.lang.reflect.Constructor

        private data class C(val status: String = "OK")
        class PublicNoArg
        class WithArgument(val value: String)
        class PrivateConstructor private constructor()

        fun box(): String {
            val defaulted: Constructor<C> = C::class.java.getConstructor()
            val noArg: Constructor<PublicNoArg> = PublicNoArg::class.java.getConstructor()
            val withArgument: Constructor<WithArgument> =
                WithArgument::class.java.getConstructor(String::class.java)

            val result = defaulted.newInstance()
            val noArgInstance = noArg.newInstance()
            val withArgumentInstance = withArgument.newInstance("OK")
            val assertionsEnabled = C::class.java.desiredAssertionStatus()
            val privateConstructorRejected = try {
                PrivateConstructor::class.java.getConstructor()
                false
            } catch (error: Throwable) {
                true
            }

            return if (
                result.status == "OK" &&
                noArgInstance is PublicNoArg &&
                withArgumentInstance.value == "OK" &&
                assertionsEnabled &&
                privateConstructorRejected &&
                defaulted is Constructor<*>
            ) {
                "OK"
            } else {
                "FAIL"
            }
        }

        fun main() { print(box()) }
        """.write(to: input, atomically: true, encoding: .utf8)

        let options = CompilerOptions(
            moduleName: "KUU2364",
            inputs: [input.path],
            outputPath: output.path,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: !fromSource
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))

        let result = try CommandRunner.run(executable: output.path, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == "OK")
        #expect(result.stderr.isEmpty, "\(result.stderr)")
    }
}
