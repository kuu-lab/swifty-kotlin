@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite(.serialized)
struct CompilerPluginLombokExecutionTests {

    @Test
    func lombokAccessorsConstructorsBuilderToStringEqualsAndHashCodeExecuteAtRuntime() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let stubsSource = """
        package lombok

        enum class AccessLevel {
            PUBLIC, PROTECTED, PACKAGE, PRIVATE, NONE
        }

        annotation class Getter(val value: AccessLevel = AccessLevel.PUBLIC)
        annotation class Setter(val value: AccessLevel = AccessLevel.PUBLIC)
        annotation class With(val value: AccessLevel = AccessLevel.PUBLIC)
        annotation class ToString(
            val includeFieldNames: Boolean = true,
            val onlyExplicitlyIncluded: Boolean = false
        )
        annotation class EqualsAndHashCode(
            val onlyExplicitlyIncluded: Boolean = false
        )
        annotation class AllArgsConstructor(
            val access: AccessLevel = AccessLevel.PUBLIC,
            val staticName: String = ""
        )
        annotation class Builder(
            val builderClassName: String = "",
            val builderMethodName: String = "builder",
            val buildMethodName: String = "build",
            val setterPrefix: String = ""
        )
        """

        let mainSource = """
        package com.example

        import lombok.AllArgsConstructor
        import lombok.Builder
        import lombok.EqualsAndHashCode
        import lombok.Getter
        import lombok.Setter
        import lombok.ToString
        import lombok.With

        @Getter
        @Setter
        @With
        @ToString
        @EqualsAndHashCode
        @AllArgsConstructor
        @Builder
        class User {
            var name: String = ""
            var age: Int = 0
        }

        fun main() {
            val u1 = User("Alice", 30)
            println(u1.getName())
            println(u1.getAge())
            u1.setAge(31)
            println(u1.getAge())

            val u2 = u1.withAge(40)
            println(u2.getName())
            println(u2.getAge())
            println(u1.getAge())

            val u3 = User.builder().name("Alice").age(31).build()
            println(u3.toString())
            println(u1 == u3)
            println(u1 == u2)
            println(u1.hashCode() == u3.hashCode())
        }
        """

        let stubsPath = directory.appendingPathComponent("lombok_stubs.kt").path
        let inputPath = directory.appendingPathComponent("lombok_exec.kt").path
        let outputPath = directory.appendingPathComponent("lombok_exec_out").path
        try stubsSource.write(toFile: stubsPath, atomically: true, encoding: .utf8)
        try mainSource.write(toFile: inputPath, atomically: true, encoding: .utf8)

        let options = CompilerOptions(
            moduleName: "LombokExec",
            inputs: [stubsPath, inputPath],
            outputPath: outputPath,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: .O0,
            includeStdlib: false,
            stdlibLibraryPath: try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: true
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))

        let result = try CommandRunner.run(executable: outputPath, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        let expected = [
            "Alice",
            "30",
            "31",
            "Alice",
            "40",
            "31",
            "User(name=Alice, age=31)",
            "true",
            "false",
            "true",
        ].joined(separator: "\n") + "\n"
        #expect(result.stdout == expected)
    }
}
