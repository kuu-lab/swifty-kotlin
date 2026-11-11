@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite(.serialized)
struct CompilerPluginAssignmentExecutionTests {

    @Test
    func assignmentPluginExecutesOverloadedAssignAtRuntime() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = """
        package com.example

        annotation class ValueContainer

        @ValueContainer
        class IntProperty(var value: Int) {
            fun assign(newValue: Int) {
                value = newValue
            }
        }

        class Task {
            val count = IntProperty(1)
        }

        fun main() {
            val localProp = IntProperty(10)
            localProp = 15

            val task = Task()
            task.count = 27

            println(localProp.value + task.count.value)
        }
        """

        let inputPath = directory.appendingPathComponent("assignment_exec.kt").path
        let outputPath = directory.appendingPathComponent("assignment_exec_out").path
        try source.write(toFile: inputPath, atomically: true, encoding: .utf8)

        let options = CompilerOptions(
            moduleName: "AssignmentPluginExec",
            inputs: [inputPath],
            outputPath: outputPath,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: .O0,
            frontendFlags: ["plugin:org.jetbrains.kotlin.assignment:annotation=com.example.ValueContainer"],
            includeStdlib: false,
            stdlibLibraryPath: try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: true
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))

        let result = try CommandRunner.run(executable: outputPath, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "42")
    }
}
