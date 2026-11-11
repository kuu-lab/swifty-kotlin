@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite(.serialized)
struct CompilerPluginSamWithReceiverExecutionTests {

    @Test
    func samWithReceiverExecutesWithImplicitReceiverAtRuntime() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = """
        package com.example

        annotation class SamWithReceiver

        class Accumulator(var total: Int) {
            fun add(amount: Int) {
                total += amount
            }
        }

        @SamWithReceiver
        fun interface Configurator<T> {
            fun configure(target: T, multiplier: Int)
        }

        fun runConfig(c: Configurator<Accumulator>): Int {
            val acc = Accumulator(10)
            c.configure(acc, 3)
            return acc.total
        }

        fun main() {
            val result = runConfig { mult ->
                this.add(7 * mult)
                add(11)
            }
            println(result)
        }
        """

        let inputPath = directory.appendingPathComponent("sam_with_receiver.kt").path
        let outputPath = directory.appendingPathComponent("sam_with_receiver_out").path
        try source.write(toFile: inputPath, atomically: true, encoding: .utf8)

        let options = CompilerOptions(
            moduleName: "SamWithReceiverExec",
            inputs: [inputPath],
            outputPath: outputPath,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: .O0,
            frontendFlags: ["plugin:org.jetbrains.kotlin.samWithReceiver:annotation=com.example.SamWithReceiver"],
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
