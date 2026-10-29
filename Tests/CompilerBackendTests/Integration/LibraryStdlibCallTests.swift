@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite(.serialized)
struct LibraryStdlibCallTests {
    /// KUU-1969: source-backed stdlib callees need bodies in a library object,
    /// or an imported link name when the producer uses a stdlib artifact.
    @Test(arguments: [0, 2])
    func stdlibCallsLinkAcrossLibraryBoundary(optimization: Int) throws {
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = try testStdlibArtifactPath()
        // A source-mode consumer of an artifact-backed producer must still link
        // that producer's stdlib dependency without importing its metadata.
        let dependencyArchive = directory.appendingPathComponent("libStdlibDependency.a").path
        let dependencyObjects = LinkPhase().discoverLibraryObjects(searchPaths: [stdlib])
        try #require(!dependencyObjects.isEmpty)
        let archiveResult = try CommandRunner.run(
            executable: CommandRunner.resolveExecutable("ar", fallback: "/usr/bin/ar"),
            arguments: ["rcs", dependencyArchive] + dependencyObjects
        )
        try #require(archiveResult.exitCode == 0, "Archive stderr: \(archiveResult.stderr)")

        func compile(
            source: String, module: String, emit: EmitMode,
            fromSource: Bool, searchPaths: [String] = [], linkStdlibDependency: Bool = false
        ) throws -> String {
            let sourcePath = directory.appendingPathComponent(module + ".kt").path
            let output = directory.appendingPathComponent(module).path
            try source.write(toFile: sourcePath, atomically: true, encoding: .utf8)
            let options = CompilerOptions(
                moduleName: module, inputs: [sourcePath], outputPath: output,
                emit: emit, searchPaths: searchPaths,
                libraryPaths: linkStdlibDependency ? [directory.path] : [],
                linkLibraries: linkStdlibDependency ? ["StdlibDependency"] : [],
                target: defaultTargetTriple(),
                optLevel: level, includeStdlib: fromSource,
                stdlibLibraryPath: fromSource ? nil : stdlib,
                allowDefaultStdlibLibrary: false
            )
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options), context: module)
            return emit == .library ? output + ".kklib" : output
        }

        let librarySource = """
        package mylib
        fun greet(): String {
            val sb = StringBuilder()
            sb.append("hi")
            return sb.toString()
        }
        class Foo { fun bar(): Int = 42 }
        inline fun inlineSum(): Int = listOf(1, 2, 3).sum()
        @OptIn(kotlin.uuid.ExperimentalUuidApi::class)
        fun nilUuid(): String = kotlin.uuid.Uuid.NIL.toString()
        fun exercise() {
            println(greet())
            println(listOf(1, 2, 3).sum())
            check(true)
            val map = mutableMapOf<String, Int>()
            map["k"] = 3
            println(map.containsKey("k"))
            println(map["k"])
            println(intArrayOf(1, 2, 3).asList())
            var total = 0
            listOf(1, 2, 3).forEach { total += it }
            println(total)
            try { error("boom") } catch (e: IllegalStateException) { println(e.message) }
            val pair = Pair(4, 5)
            println(pair.first + pair.second)
            println(Foo().bar())
            println(listOf(1, 2).size)
            val list = mutableListOf<Int>()
            list.add(7)
            println(list.size)
            println("x" + "y")
        }
        """
        let expected = "hi\n6\ntrue\n3\n[1, 2, 3]\n6\nboom\n9\n42\n2\n1\nxy\n6\n00000000-0000-0000-0000-000000000000\n"

        for producerFromSource in [true, false] {
            let library = try compile(
                source: librarySource, module: "Library\(producerFromSource)",
                emit: .library, fromSource: producerFromSource
            )
            let metadata = try Data(contentsOf: URL(fileURLWithPath: library + "/metadata.bin"))
            #expect(!MetadataDecoder().decode(metadata).contains {
                $0.kind != .package && $0.fqName.hasPrefix("kotlin.")
            }, "Bundled stdlib declarations must not be exported as user-library API")

            for consumerFromSource in [true, false] {
                let executable = try compile(
                    source: "import mylib.*\nfun main() { exercise(); println(inlineSum()); println(nilUuid()) }",
                    module: "Consumer\(producerFromSource)\(consumerFromSource)",
                    emit: .executable, fromSource: consumerFromSource,
                    searchPaths: [library],
                    linkStdlibDependency: !producerFromSource && consumerFromSource
                )
                let result = try CommandRunner.run(executable: executable, arguments: [])
                #expect(result.exitCode == 0, "Execution stderr: \(result.stderr)")
                #expect(result.stdout == expected)
            }
        }
    }
}
