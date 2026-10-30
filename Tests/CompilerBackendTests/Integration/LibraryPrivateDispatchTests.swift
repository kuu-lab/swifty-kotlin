@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite(.serialized)
struct LibraryPrivateDispatchTests {
    /// KUU-2019: hidden final helpers have no exported vtable entries in a consumer.
    @Test(arguments: [0, 2])
    func parserPrivateHelpersAcrossLibraryBoundary(optimization: Int) throws {
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = try testStdlibArtifactPath()
        let librarySource = """
        package fixture
        open class ArgParser(val name: String) {
            private fun inspectRequiredAndDefaultUsage() { println(name) }
            private fun value(): Int = 7
            internal fun internalValue(): Int = 9
            fun parse(args: Array<out String>) = parse(args.asList())
            protected fun parse(args: List<String>) {
                inspectRequiredAndDefaultUsage()
                val iterator = args.listIterator()
                try {
                    while (iterator.hasNext()) println(iterator.next())
                } catch (e: IllegalStateException) {
                    println(e.message)
                }
                println(this.value())
                println(this?.value())
                println((this::value)())
                println(internalValue())
                println(label())
            }
            open fun label(): String = "base"
        }
        class Child : ArgParser("child") {
            override fun label(): String = "override"
        }
        fun makeParser(): ArgParser = ArgParser("factory")
        """
        let consumerSource = """
        import fixture.*
        fun main() {
            ArgParser("empty").parse(arrayOf())
            makeParser().parse(arrayOf("one", "two"))
            Child().parse(arrayOf("three"))
            println("done")
        }
        """

        func compile(source: String, module: String, emit: EmitMode, searchPaths: [String] = []) throws -> String {
            let sourcePath = directory.appendingPathComponent(module + ".kt").path
            let output = directory.appendingPathComponent(module).path
            try source.write(toFile: sourcePath, atomically: true, encoding: .utf8)
            let options = CompilerOptions(
                moduleName: module, inputs: [sourcePath], outputPath: output,
                emit: emit, searchPaths: searchPaths, target: defaultTargetTriple(),
                optLevel: level, stdlibLibraryPath: stdlib
            )
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options), context: module)
            return emit == .library ? output + ".kklib" : output
        }

        let library = try compile(source: librarySource, module: "ParserLibrary", emit: .library)
        let metadata = try Data(contentsOf: URL(fileURLWithPath: library + "/metadata.bin"))
        #expect(!MetadataDecoder().decode(metadata).contains {
            $0.fqName == "fixture.ArgParser.inspectRequiredAndDefaultUsage"
                || $0.fqName == "fixture.ArgParser.value"
                || $0.fqName == "fixture.ArgParser.internalValue"
        })
        let expected = "empty\n7\n7\n7\n9\nbase\nfactory\none\ntwo\n7\n7\n7\n9\nbase\nchild\nthree\n7\n7\n7\n9\noverride\ndone\n"
        for (module, source, paths) in [
            ("Consumer", consumerSource, [library]),
            ("Monolithic", librarySource + "\n" + consumerSource.replacingOccurrences(of: "import fixture.*\n", with: ""), []),
        ] {
            let executable = try compile(source: source, module: module, emit: .executable, searchPaths: paths)
            let result = try CommandRunner.run(executable: executable, arguments: [])
            #expect(result.exitCode == 0, "Execution stderr: \(result.stderr)")
            #expect(result.stdout == expected)
        }
    }
}
