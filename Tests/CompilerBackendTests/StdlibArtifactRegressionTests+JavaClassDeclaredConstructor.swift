@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2375: Java Class selects a no-argument constructor from source stdlib.
    @Test func testJavaClassDeclaredConstructorNoArgFromSource() throws {
        let source = """
        class Sample

        fun main() {
            Sample::class.java.getDeclaredConstructor()
            print("OK")
        }
        """
        try assertJavaClassDeclaredConstructorProgram(
            source,
            moduleName: "JavaClassDeclaredConstructorNoArgSource",
            lanes: [(nil, .O0), (nil, .O2)],
            expectedOutput: "OK"
        )
    }

    /// KUU-2375: Java Class selects a no-argument constructor from a fresh stdlib artifact.
    @Test func testJavaClassDeclaredConstructorNoArgFromArtifact() throws {
        let source = """
        class Sample

        fun main() {
            Sample::class.java.getDeclaredConstructor()
            print("OK")
        }
        """
        let artifact = try testStdlibArtifactPath()
        try assertJavaClassDeclaredConstructorProgram(
            source,
            moduleName: "JavaClassDeclaredConstructorNoArgArtifact",
            lanes: [(artifact, .O0), (artifact, .O2)],
            expectedOutput: "OK"
        )
    }

    /// Keep the existing Java Class member working across stdlib surfaces and optimization levels.
    @Test func testJavaClassDesiredAssertionStatusControlFromSourceAndArtifact() throws {
        let source = """
        class Sample

        fun main() {
            Sample::class.java.desiredAssertionStatus()
            print("OK")
        }
        """
        let artifact = try testStdlibArtifactPath()
        try assertJavaClassDeclaredConstructorProgram(
            source,
            moduleName: "JavaClassDesiredAssertionStatusControl",
            lanes: [(nil, .O0), (nil, .O2), (artifact, .O0), (artifact, .O2)],
            expectedOutput: "OK"
        )
    }

    /// KUU-2375: Enum lookup matches the JVM name, ordinal, and declared String parameters.
    @Test func testJavaClassDeclaredConstructorEnumJvmParametersFromSource() throws {
        let source = """
        enum class A(val OK: String) {
            A("OK")
        }

        fun main() {
            val constructor: java.lang.reflect.Constructor<A> =
                A::class.java.getDeclaredConstructor(String::class.java, Int::class.java, String::class.java)
            print("OK")
        }
        """
        try assertJavaClassDeclaredConstructorProgram(
            source,
            moduleName: "JavaClassDeclaredConstructorEnumSource",
            lanes: [(nil, .O0)],
            expectedOutput: "OK"
        )
    }

    /// KUU-2375: Enum lookup matches the JVM name, ordinal, and declared String parameters.
    @Test func testJavaClassDeclaredConstructorEnumJvmParametersFromArtifact() throws {
        let source = """
        enum class A(val OK: String) {
            A("OK")
        }

        fun main() {
            val constructor: java.lang.reflect.Constructor<A> =
                A::class.java.getDeclaredConstructor(String::class.java, Int::class.java, String::class.java)
            print("OK")
        }
        """
        let artifact = try testStdlibArtifactPath()
        try assertJavaClassDeclaredConstructorProgram(
            source,
            moduleName: "JavaClassDeclaredConstructorEnumArtifact",
            lanes: [(artifact, .O0), (artifact, .O2)],
            expectedOutput: "OK"
        )
    }
}

private func assertJavaClassDeclaredConstructorProgram(
    _ source: String,
    moduleName: String,
    lanes: [(library: String?, level: OptimizationLevel)],
    expectedOutput: String
) throws {
    let compiler = try javaClassDeclaredConstructorCompilerPath()
    for (library, level) in lanes {
        try withTemporaryFile(contents: source) { path in
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: output) }
            var compileArguments = library.map { ["--no-stdlib", "--stdlib-library", $0] }
                ?? ["--stdlib-from-source"]
            compileArguments.append(contentsOf: ["-O\(level.rawValue)", "-m", moduleName, "-o", output, path])
            do {
                _ = try CommandRunner.run(executable: compiler, arguments: compileArguments, timeout: 300)
            } catch {
                throw JavaClassDeclaredConstructorCompilationFailure(
                    compiler: compiler,
                    diagnostics: "cwd=\(FileManager.default.currentDirectoryPath)\n"
                        + "arguments=\(compileArguments)\n\(error)"
                )
            }
            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stderr.isEmpty)
            #expect(result.stdout == expectedOutput)
        }
    }
}

private func javaClassDeclaredConstructorCompilerPath() throws -> String {
    let fileManager = FileManager.default
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    var candidates: [String] = []
    if let productsDirectory = ProcessInfo.processInfo.environment["BUILT_PRODUCTS_DIR"] {
        candidates.append(URL(fileURLWithPath: productsDirectory).appendingPathComponent("kswiftc").path)
    }
    candidates.append(packageRoot.appendingPathComponent(".build/out/Products/Debug/kswiftc").path)
    candidates.append(packageRoot.appendingPathComponent(".build/debug/kswiftc").path)
    if let compiler = candidates.first(where: fileManager.isExecutableFile(atPath:)) {
        return compiler
    }
    throw JavaClassDeclaredConstructorCompilationFailure(
        compiler: candidates.joined(separator: ", "),
        diagnostics: "No executable kswiftc product was found."
    )
}

private struct JavaClassDeclaredConstructorCompilationFailure: LocalizedError {
    let compiler: String
    let diagnostics: String

    var errorDescription: String? {
        "KUU-2375 kswiftc failed at \(compiler): \(diagnostics)"
    }
}
