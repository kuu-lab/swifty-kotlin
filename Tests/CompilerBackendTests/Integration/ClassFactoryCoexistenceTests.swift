@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite(.serialized)
struct ClassFactoryCoexistenceTests {
    @Test
    func classAndFactoryResolveAcrossLibraryAndDeclarationOrders() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = try testStdlibArtifactPath()
        let classDeclaration = "class Foo(val x: Int) { fun tag() = \"C\" }"
        let factoryDeclaration = "fun Foo() = 0"
        let consumer = """
        fun main() {
            println(dup.Foo(3).x)
            println(dup.Foo())
            println(dup.Foo(4).tag())
        }
        """

        func compile(_ source: String, module: String, emit: EmitMode, paths: [String] = []) throws -> String {
            let sourcePath = directory.appendingPathComponent(module + ".kt").path
            let output = directory.appendingPathComponent(module).path
            try source.write(toFile: sourcePath, atomically: true, encoding: .utf8)
            let options = CompilerOptions(
                moduleName: module, inputs: [sourcePath], outputPath: output,
                emit: emit, searchPaths: paths, target: defaultTargetTriple(),
                stdlibLibraryPath: stdlib
            )
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options), context: module)
            return emit == .library ? output + ".kklib" : output
        }

        func check(_ source: String, module: String, paths: [String] = []) throws {
            let executable = try compile(source, module: module, emit: .executable, paths: paths)
            let result = try CommandRunner.run(executable: executable, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stdout == "3\n0\nC\n")
        }

        let classLibrary = try compile("package dup\n" + classDeclaration, module: "ClassLib", emit: .library)
        let factoryLibrary = try compile("package dup\n" + factoryDeclaration, module: "FactoryLib", emit: .library)
        try check(consumer, module: "ClassFirst", paths: [classLibrary, factoryLibrary])
        try check(consumer, module: "FactoryFirst", paths: [factoryLibrary, classLibrary])
        for (index, declarations) in [
            classDeclaration + "\n" + factoryDeclaration,
            factoryDeclaration + "\n" + classDeclaration,
        ].enumerated() {
            let library = try compile("package dup\n" + declarations, module: "Combined\(index)", emit: .library)
            try check(consumer, module: "CombinedConsumer\(index)", paths: [library])
            try check("package dup\n" + declarations + "\n" + consumer, module: "Source\(index)")
            try check("import dup.Foo\n" + consumer.replacingOccurrences(of: "dup.Foo", with: "Foo"),
                      module: "ImportedConsumer\(index)", paths: [library])
        }
    }
}
