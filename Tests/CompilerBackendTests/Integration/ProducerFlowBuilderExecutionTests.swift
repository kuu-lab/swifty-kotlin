import Foundation
@testable import CompilerBackend
@testable import CompilerCore
import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct ProducerFlowBuilderExecutionTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func fixture(_ suffix: String) throws -> String {
        try String(contentsOf: repository.appendingPathComponent(
            "Scripts/diff_cases/kotlinx_coroutines_flow_builder_inference.\(suffix)"), encoding: .utf8)
    }

    @Test(arguments: [false, true], [0, 2])
    func inferredFlowTypesExecuteLikePublishedCoroutines(fromSource: Bool, optimization: Int) throws {
        try withDirectory { directory in
            let input = directory.appendingPathComponent("flow.kt").path
            let output = directory.appendingPathComponent("flow").path
            try fixture("kt").write(toFile: input, atomically: true, encoding: .utf8)
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
                moduleName: "ProducerFlowBuilder", inputs: [input], outputPath: output, emit: .executable,
                target: defaultTargetTriple(), optLevel: try #require(OptimizationLevel(rawValue: optimization)),
                stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(), allowDefaultStdlibLibrary: !fromSource
            )))
            try expectFixtureOutput(output)
        }
    }

    @Test(arguments: [0, 2])
    func separateLibraryPreservesInferredTypesAndCapturedBuilder(optimization: Int) throws {
        try withDirectory { directory in
            let stdlib = try testStdlibArtifactPath()
            let level = try #require(OptimizationLevel(rawValue: optimization))
            let source = try fixture("kt")
            let boundary = try #require(source.range(of: "fun main() = runBlocking {"))
            let producer = directory.appendingPathComponent("producer.kt").path
            let library = directory.appendingPathComponent("FlowProducer").path
            try ("package producer\n" + String(source[..<boundary.lowerBound]))
                .write(toFile: producer, atomically: true, encoding: .utf8)
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
                moduleName: "FlowProducer", inputs: [producer], outputPath: library, emit: .library,
                target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
            )))
            let consumer = directory.appendingPathComponent("consumer.kt").path
            let output = directory.appendingPathComponent("consumer").path
            let consumerMain = String(source[boundary.lowerBound...]).replacingOccurrences(of: "fun main() = runBlocking {", with: """
            fun main() = runBlocking {
                val consumerSlot = buildSlot { put("consumer") }
                val typedSlot: Slot<String> = consumerSlot
                val consumerDerived = buildDerived { this.put(11) }
                val typedDerived: DerivedSlot<Int> = consumerDerived
                val consumerMember = buildMember { Marker().put("member-consumer") }
                val typedMember: MemberSink<String> = consumerMember
                println(typedSlot.items)
                println(typedDerived.items)
                println(typedMember.items)
            """)
            try ("import producer.*\nimport kotlinx.coroutines.*\nimport kotlinx.coroutines.flow.*\n"
                + consumerMain).write(toFile: consumer, atomically: true, encoding: .utf8)
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
                moduleName: "FlowConsumer", inputs: [consumer], outputPath: output, emit: .executable,
                searchPaths: [library + ".kklib"], target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
            )))
            try expectFixtureOutput(output, prefix: "[consumer]\n[11]\n[member-consumer]\n")
        }
    }

    @Test(arguments: [false, true], [0, 2])
    func userOverloadInCoroutinesPackageRunsWithRegularABI(fromLibrary: Bool, optimization: Int) throws {
        try withDirectory { directory in
            let stdlib = try testStdlibArtifactPath()
            let level = try #require(OptimizationLevel(rawValue: optimization))
            let producer = directory.appendingPathComponent("custom.kt").path
            let library = directory.appendingPathComponent("CustomFlow").path
            try """
            package kotlinx.coroutines.flow
            class LocalSink<T>(var value: T) { fun put(value: T) { this.value = value } }
            fun <T> channelFlow(seed: T, block: LocalSink<T>.() -> Unit): T {
                val sink = LocalSink(seed)
                sink.block()
                return sink.value
            }
            """.write(toFile: producer, atomically: true, encoding: .utf8)
            if fromLibrary {
                try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
                    moduleName: "CustomFlow", inputs: [producer], outputPath: library, emit: .library,
                    target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
                )))
            }
            let consumer = directory.appendingPathComponent("custom-consumer.kt").path
            let output = directory.appendingPathComponent("custom-consumer").path
            try """
            import kotlinx.coroutines.flow.channelFlow
            fun main() {
                val captured = 3
                println(channelFlow(7) { put(captured + 8) })
            }
            """.write(toFile: consumer, atomically: true, encoding: .utf8)
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
                moduleName: "CustomFlowConsumer", inputs: fromLibrary ? [consumer] : [producer, consumer],
                outputPath: output, emit: .executable, searchPaths: fromLibrary ? [library + ".kklib"] : [],
                target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
            )))
            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "11\n")
        }
    }

    private func expectFixtureOutput(_ output: String, prefix: String = "") throws {
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == prefix + (try fixture("expected")))
    }

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}
