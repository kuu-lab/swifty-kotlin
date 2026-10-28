@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct LibraryReflectionInitializationTests {
    @Test
    func libraryClassRegistersReflectionMembers() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = try testStdlibArtifactPath()

        func compile(_ source: String, module: String, emit: EmitMode, paths: [String] = []) throws -> String {
            let sourcePath = directory.appendingPathComponent(module + ".kt").path
            let outputPath = directory.appendingPathComponent(module).path
            try source.write(toFile: sourcePath, atomically: true, encoding: .utf8)
            let options = CompilerOptions(
                moduleName: module, inputs: [sourcePath], outputPath: outputPath,
                emit: emit, searchPaths: paths, target: defaultTargetTriple(),
                stdlibLibraryPath: stdlib
            )
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options), context: module)
            return emit == .library ? outputPath + ".kklib" : outputPath
        }

        let library = try compile("package sample\nclass Example(val value: Int) { fun greet() = value }", module: "ReflectionLibrary", emit: .library)
        let executable = try compile("""
        import kotlin.reflect.full.*
        import kotlin.text.StringBuilder
        import sample.Example
        fun main() {
            val klass = Example::class
            println(klass.memberFunctions.any { it.name == "greet" })
            println(klass.memberProperties.any { it.name == "value" })
            println(klass.constructors.isNotEmpty())
            val builder = StringBuilder::class
            println(builder.memberFunctions.any { it.name == "append" })
            println(builder.memberProperties.any { it.name == "length" })
            println(builder.constructors.isNotEmpty())
        }
        """, module: "ReflectionConsumer", emit: .executable, paths: [library])
        let result = try CommandRunner.run(executable: executable, arguments: [])
        #expect(result.exitCode == 0)
        #expect(result.stdout == String(repeating: "true\n", count: 6))
    }
}
