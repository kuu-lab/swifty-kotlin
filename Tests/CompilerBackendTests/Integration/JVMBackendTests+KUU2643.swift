#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func kuu2643ActualReadLineStrictUsesImportedJvmClasspathApi() throws {
        try withWorkspace { root in
            let repository = kuu2643RepositoryRoot()
            let support = repository.appendingPathComponent("Tests/CompilerBackendTests/Fixtures/KUU2643")
            let apiJar = try kuu2643JvmApiJar(root: root, support: support)
            let implementation = try kuu2643ReadLineStrictDeclaration(repository: repository)
                .replacingOccurrences(of: "readLineStrict", with: "readLineStrictActual")
                .replacingOccurrences(of: "package kotlinx.io\n", with: "package kotlinx.io\nclass EOFException : RuntimeException()\n\n")
            let artifact = try m22Build(
                root: root,
                sources: [("kotlinx/io/ReadLineStrict.kt", implementation)],
                name: "read-line-strict-classpath-classes",
                mode: .jvmClass,
                classpath: [apiJar.path]
            )
            try #require(artifact.1 == 0, "\(artifact.2.map(\.message))")

            let harness = support.appendingPathComponent("ReadLineStrictClasspathHarness.java")
            let harnessClasses = root.appendingPathComponent("classpath-harness-classes", isDirectory: true)
            try FileManager.default.createDirectory(at: harnessClasses, withIntermediateDirectories: true)
            _ = try jvmTool(
                "javac",
                ["--release", "8", "-classpath", artifact.0.path + ":" + apiJar.path,
                 "-d", harnessClasses.path, harness.path],
                root: root
            )
            let execution = try java([
                "-cp", harnessClasses.path + ":" + artifact.0.path + ":" + apiJar.path,
                "ReadLineStrictClasspathHarness"
            ])
            #expect(execution.stdout == "KUU-2643 imported JVM classpath PASS\n")
            #expect(execution.stderr.isEmpty)
        }
    }

    @Test
    func kuu2643ActualReadLineStrictCompilesAndRunsWithItsDefaultBridge() throws {
        try withWorkspace { root in
            let repository = kuu2643RepositoryRoot()
            let support = repository.appendingPathComponent("Tests/CompilerBackendTests/Fixtures/KUU2643")
            let classes = root.appendingPathComponent("support-classes", isDirectory: true)
            try FileManager.default.createDirectory(at: classes, withIntermediateDirectories: true)

            let supportSource = try String(contentsOf: support.appendingPathComponent("Source.kt"), encoding: .utf8)
            let implementation = try kuu2643ReadLineStrictDeclaration(repository: repository)
            let artifact = try m22Build(
                root: root,
                sources: [("kotlinx/io/Source.kt", supportSource), ("kotlinx/io/Utf8.kt", implementation)],
                name: "read-line-strict-classes",
                mode: .jvmClass
            )
            try #require(artifact.1 == 0, "\(artifact.2.map(\.message))")
            let classFile = try Data(contentsOf: artifact.0.appendingPathComponent("kotlinx/io/Utf8Kt.class"))
            #expect(Array(classFile.prefix(4)) == [0xCA, 0xFE, 0xBA, 0xBE])

            let abi = try jvmTool("javap", ["-p", "-s", "-classpath", artifact.0.path, "kotlinx.io.Utf8Kt"], root: root)
            #expect(abi.stdout.contains("readLineStrict$default"))
            #expect(abi.stdout.contains("(Lkotlinx/io/Source;JILjava/lang/Object;)Ljava/lang/String;"))

            let javaHarness = support.appendingPathComponent("ReadLineStrictHarness.java")
            _ = try jvmTool(
                "javac",
                ["--release", "8", "-classpath", artifact.0.path, "-d", classes.path,
                 javaHarness.path],
                root: root
            )
            let execution = try java(["-cp", classes.path + ":" + artifact.0.path, "ReadLineStrictHarness"])
            #expect(execution.stdout == "KUU-2643 actual Source.readLineStrict PASS\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}

private func kuu2643JvmApiJar(root: URL, support: URL) throws -> URL {
    let apiSources = support.appendingPathComponent("JvmApi", isDirectory: true)
    let classes = root.appendingPathComponent("jvm-api-classes", isDirectory: true)
    try FileManager.default.createDirectory(at: classes, withIntermediateDirectories: true)
    let javaFiles = ["Buffer.java", "Source.java", "SourcesKt.java", "Utf8Kt.java"]
        .map { apiSources.appendingPathComponent($0).path }
    _ = try JVMBackendTests().jvmTool(
        "javac", ["--release", "8", "-d", classes.path] + javaFiles, root: root
    )
    let jar = root.appendingPathComponent("kotlinx-io-api.jar")
    _ = try JVMBackendTests().jvmTool("jar", ["cf", jar.path, "-C", classes.path, "."], root: root)
    return jar
}

private func kuu2643RepositoryRoot(file: StaticString = #filePath) -> URL {
    var root = URL(fileURLWithPath: file.description)
    for _ in 0..<4 { root.deleteLastPathComponent() }
    return root
}

private func kuu2643ReadLineStrictDeclaration(repository: URL) throws -> String {
    let path = repository.appendingPathComponent("Sources/CompilerCore/Stdlib/kotlinx/io/Utf8.kt")
    let source = try String(contentsOf: path, encoding: .utf8)
    let declarationStart = try #require(source.range(of: "public fun Source.readLineStrict(limit: Long = Long.MAX_VALUE): String {"))
    let declarationEnd = try #require(source.range(of: "\n// Pinned 0.9.1 validation/streaming helpers", range: declarationStart.lowerBound..<source.endIndex))
    let declaration = source[declarationStart.lowerBound..<declarationEnd.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
    return "package kotlinx.io\n\n\(declaration)\n"
}
#endif
