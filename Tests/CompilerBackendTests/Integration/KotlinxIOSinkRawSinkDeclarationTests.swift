@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

/// Direct KUU-2612 probes for the Sink and RawSink declaration boundary.
@Suite(.serialized)
struct KotlinxIOSinkRawSinkDeclarationTests {
    // IO_API_VALIDATION_PROBE: probe:KUU-2612:sink-rawsink-native-declarations

    private let expectedOutput = """
    sink.sealed=true
    rawSink.sealed=false
    sink.isRawSink=true
    rawSink.isAutoCloseable=true
    rawSink.methods=write(Buffer,Long),flush(),close()
    """ + "\n"

    private let consumer = """
    package io.gate.consumer

    import kotlinx.io.Buffer
    import kotlinx.io.RawSink
    import kotlinx.io.Sink
    import kotlinx.io.buffered
    import kotlin.AutoCloseable

    private class UserRawSink : RawSink {
        var calls = 0

        override fun write(source: Buffer, byteCount: Long) { calls += 1 }
        override fun flush() { calls += 10 }
        override fun close() { calls += 100 }
    }

    fun main() {
        check(Sink::class.isSealed)
        check(!RawSink::class.isSealed)

        val sink: Sink = Buffer().buffered()
        val rawFromSink: RawSink = sink
        val erasedSink: Any = sink
        check(erasedSink is RawSink)

        val rawSink = UserRawSink()
        val closeable: AutoCloseable = rawSink
        val erasedRawSink: Any = closeable
        check(erasedRawSink is AutoCloseable)
        rawSink.write(Buffer(), 0L)
        rawSink.flush()
        rawSink.close()
        check(rawSink.calls == 111)

        println("sink.sealed=${Sink::class.isSealed}")
        println("rawSink.sealed=${RawSink::class.isSealed}")
        println("sink.isRawSink=${rawFromSink === sink && erasedSink is RawSink}")
        println("rawSink.isAutoCloseable=${closeable === rawSink && erasedRawSink is AutoCloseable}")
        println("rawSink.methods=write(Buffer,Long),flush(),close()")
    }
    """

    private let producer = """
    package io.gate.producer

    import kotlinx.io.Buffer
    import kotlinx.io.RawSink
    import kotlinx.io.Sink

    private class ProducerRawSink : RawSink {
        override fun write(source: Buffer, byteCount: Long) {}
        override fun flush() {}
        override fun close() {}
    }

    fun sinkAsRawSink(value: Sink): RawSink = value
    fun makeRawSink(): RawSink = ProducerRawSink()
    """

    private let producerConsumer = """
    package io.gate.consumer

    import io.gate.producer.makeRawSink
    import io.gate.producer.sinkAsRawSink
    import kotlinx.io.Buffer
    import kotlinx.io.RawSink
    import kotlinx.io.Sink
    import kotlinx.io.buffered
    import kotlin.AutoCloseable

    private class UserRawSink : RawSink {
        var calls = 0

        override fun write(source: Buffer, byteCount: Long) { calls += 1 }
        override fun flush() { calls += 10 }
        override fun close() { calls += 100 }
    }

    fun main() {
        check(Sink::class.isSealed)
        check(!RawSink::class.isSealed)

        val sink: Sink = Buffer().buffered()
        val rawFromProducer: RawSink = sinkAsRawSink(sink)
        val exportedRawSink: RawSink = makeRawSink()
        val erasedSink: Any = rawFromProducer
        check(erasedSink is RawSink)
        exportedRawSink.flush()
        exportedRawSink.close()

        val rawSink = UserRawSink()
        val closeable: AutoCloseable = rawSink
        val erasedRawSink: Any = closeable
        check(erasedRawSink is AutoCloseable)
        rawSink.write(Buffer(), 0L)
        rawSink.flush()
        rawSink.close()
        check(rawSink.calls == 111)

        println("sink.sealed=${Sink::class.isSealed}")
        println("rawSink.sealed=${RawSink::class.isSealed}")
        println("sink.isRawSink=${rawFromProducer === sink && erasedSink is RawSink}")
        println("rawSink.isAutoCloseable=${closeable === rawSink && erasedRawSink is AutoCloseable}")
        println("rawSink.methods=write(Buffer,Long),flush(),close()")
    }
    """

    @Test
    func declarationsSurviveSourceFreshKlibAndProducerConsumerAtO0AndO2() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kuu2612-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let target = CompilerTestSupport.defaultTargetTriple()
        let stdlibBase = directory.appendingPathComponent("fresh-stdlib").path
        let stdlib = try StdlibArtifactBuilder.build(outputBase: stdlibBase, target: target)
        try assertFreshKlibDeclarationMetadata(at: stdlib)

        for optimization in [0, 2] {
            let level = try #require(OptimizationLevel(rawValue: optimization))

            let sourceExecutable = try compile(
                consumer, module: "SinkRawSinkSourceO\(optimization)", emit: .executable,
                directory: directory, level: level, target: target, stdlib: nil,
                searchPaths: [], includeStdlib: true
            )
            try assertRuns(sourceExecutable, expected: expectedOutput)

            let libraryExecutable = try compile(
                consumer, module: "SinkRawSinkLibraryO\(optimization)", emit: .executable,
                directory: directory, level: level, target: target, stdlib: stdlib,
                searchPaths: [], includeStdlib: false
            )
            try assertRuns(libraryExecutable, expected: expectedOutput)

            let producerLibrary = try compile(
                producer, module: "SinkRawSinkProducerO\(optimization)", emit: .library,
                directory: directory, level: level, target: target, stdlib: stdlib,
                searchPaths: [], includeStdlib: false
            )
            let producerConsumerExecutable = try compile(
                producerConsumer, module: "SinkRawSinkProducerConsumerO\(optimization)", emit: .executable,
                directory: directory, level: level, target: target, stdlib: stdlib,
                searchPaths: [producerLibrary], includeStdlib: false
            )
            try assertRuns(producerConsumerExecutable, expected: expectedOutput)
        }
    }

    @Test
    func sealedSinkAndOpenRawSinkArePreservedAtConsumerBoundary() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kuu2612-sealed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let target = CompilerTestSupport.defaultTargetTriple()
        let stdlib = try StdlibArtifactBuilder.build(
            outputBase: directory.appendingPathComponent("fresh-stdlib").path,
            target: target
        )

        for (name, stdlibPath, includeStdlib) in [
            ("source", Optional<String>.none, true),
            ("fresh-klib", Optional(stdlib), false),
        ] {
            let input = directory.appendingPathComponent("\(name)-negative.kt").path
            let source = """
            package io.gate.external
            import kotlinx.io.Buffer
            import kotlinx.io.RawSink
            import kotlinx.io.Sink

            class UserRawSink : RawSink {
                override fun write(source: Buffer, byteCount: Long) {}
                override fun flush() {}
                override fun close() {}
            }

            class InvalidSink : Sink {
                override fun write(source: Buffer, byteCount: Long) {}
                override fun flush() {}
                override fun close() {}
            }
            """
            let options = CompilerOptions(
                moduleName: "SinkRawSinkExternal\(name)", inputs: [input], outputPath: directory.path,
                emit: .executable, target: target, includeStdlib: includeStdlib,
                stdlibLibraryPath: stdlibPath, allowDefaultStdlibLibrary: false
            )
            let context = CompilerDriver().runFrontend(
                options: options, inMemorySources: [input: Data(source.utf8)]
            ).context
            let diagnostics = context.diagnostics.diagnostics
            #expect(diagnostics.contains {
                $0.code == "KSWIFTK-SEMA-0070" && $0.message.contains("sealed subclasses must be in the same module")
            }, "Sink must reject external implementations in the \(name) view: \(diagnostics)")
            #expect(!diagnostics.contains { $0.message.contains("UserRawSink") && $0.code == "KSWIFTK-SEMA-0070" },
                    "RawSink remains implementable by an external consumer: \(diagnostics)")
        }
    }

    private func compile(
        _ source: String,
        module: String,
        emit: EmitMode,
        directory: URL,
        level: OptimizationLevel,
        target: TargetTriple,
        stdlib: String?,
        searchPaths: [String],
        includeStdlib: Bool
    ) throws -> String {
        let input = directory.appendingPathComponent(module + ".kt")
        try source.write(to: input, atomically: true, encoding: .utf8)
        let output = directory.appendingPathComponent(module).path
        let options = CompilerOptions(
            moduleName: module, inputs: [input.path], outputPath: output, emit: emit,
            searchPaths: searchPaths, target: target, optLevel: level,
            includeStdlib: includeStdlib, stdlibLibraryPath: stdlib,
            allowDefaultStdlibLibrary: false
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options), context: module)
        return emit == .library ? output + ".kklib" : output
    }

    private func assertRuns(_ executable: String, expected: String) throws {
        let result = try CommandRunner.run(executable: executable, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == expected)
        #expect(result.stderr.isEmpty)
    }

    private func assertFreshKlibDeclarationMetadata(at path: String) throws {
        let metadata = URL(fileURLWithPath: path).appendingPathComponent("metadata.bin")
        let records = MetadataDecoder().decode(try Data(contentsOf: metadata))
        let sink = try #require(records.first { $0.fqName == "kotlinx.io.Sink" })
        let rawSink = try #require(records.first { $0.fqName == "kotlinx.io.RawSink" })

        #expect(sink.kind == .interface)
        #expect(sink.visibility == .public)
        #expect(sink.isSealedClass)
        #expect(sink.superFQName == "kotlinx.io.RawSink")

        #expect(rawSink.kind == .interface)
        #expect(rawSink.visibility == .public)
        #expect(!rawSink.isSealedClass)
        #expect(rawSink.superFQName?.hasSuffix("AutoCloseable") == true)
    }
}
