@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    @Test(arguments: [true, false])
    func javaObjectTypeMapsPrimitiveKClasses(fromSource: Bool) throws {
        let source = """
        fun main() {
            println(Int::class.javaPrimitiveType!!.canonicalName)
            println(Int::class.javaObjectType.canonicalName)
            println(Int::class.javaObjectType.simpleName)
            println(Int::class.javaObjectType.name)
            println(Int::class.javaObjectType.toString())
            println(Int::class.javaObjectType.kotlin == Int::class)
            println(String::class.javaObjectType === String::class.java)
        }
        """
        let artifactPath = fromSource ? nil : try Self.buildStdlibArtifact()
        let optimization = try #require(OptimizationLevel(rawValue: 0))

        try withTemporaryFile(contents: source) { input in
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: output) }

            let options = CompilerOptions(
                moduleName: "KUU3324JavaObjectType",
                inputs: [input],
                outputPath: output,
                emit: .executable,
                target: CompilerTestSupport.defaultTargetTriple(),
                optLevel: optimization,
                includeStdlib: fromSource,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))

            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0, "Execution stderr: \(result.stderr)")
            #expect(result.stderr.isEmpty)
            #expect(result.stdout == "int\njava.lang.Integer\nInteger\njava.lang.Integer\nclass java.lang.Integer\ntrue\ntrue\n")
        }
    }
}
