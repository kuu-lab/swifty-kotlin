import Foundation
@testable import CompilerBackend
@testable import CompilerCore
import Testing

@Suite(.serialized)
struct BoundedMethodDelegationArtifactTests {
    private let expectedOutput = "impl:text\nimpl:number\nimpl:text\nimpl:number\ntext\n7\ncontrol\n9\nimpl:text\nexplicit\noverride:number\n11\nimpl:text\ninterface\noverride:number\n13\nbase:text\ninherited\nchild:number\n17\ngeneric:impl\ngeneric:impl\ngeneric:override\ngeneric:override\nmultiple:override\nmultiple:override\nany:override\nnull\nany:override\nnull\n"

    @Test(arguments: [false, true], [0, 2])
    func sourceAndStdlibArtifactDispatchToEachBound(fromSource: Bool, optimization: Int) throws {
        let level = try #require(OptimizationLevel(rawValue: optimization))
        try assertKotlinOutput(
            diffCaseSource("class_delegation_bound_overloads.kt"),
            moduleName: "BoundedDelegation", expected: expectedOutput,
            optLevel: level, allowDefaultStdlibLibrary: !fromSource
        )
    }

    @Test(arguments: [false, true], [0, 2])
    func inheritedClassImplementationBeatsAbstractInterface(fromSource: Bool, optimization: Int) throws {
        try assertKotlinOutput(
            diffCaseSource("class_delegation_inherited_bound.kt"),
            moduleName: "InheritedBoundDelegation", expected: "base:generic\n7\nbase:generic\n9\n",
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            allowDefaultStdlibLibrary: !fromSource
        )
    }

    @Test(arguments: [0, 2])
    func libraryBoundaryPreservesOverloadBoundsAndSlots(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let stdlib = try testStdlibArtifactPath()
        let source = try diffCaseSource("class_delegation_bound_overloads.kt")
        let main = try #require(source.range(of: "fun main() {"))
        let api = directory.appendingPathComponent("api.kt").path
        let library = directory.appendingPathComponent("BoundedAPI").path
        try ("package delegation.bounds\n" + source[..<main.lowerBound])
            .write(toFile: api, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "BoundedAPI", inputs: [api], outputPath: library, emit: .library,
            target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let consumer = directory.appendingPathComponent("consumer.kt").path
        let imports = """
        import delegation.bounds.*
        class ImportedDelegate(base: Bounded) : Bounded by base
        """
        let body = String(source[main.lowerBound...])
        let closingBrace = try #require(body.range(of: "}", options: .backwards))
        let extraCalls = """
            val imported = ImportedDelegate(BoundedImpl())
            println(imported.echo("imported"))
            println(imported.echo(19))
        """
        try (imports + "\n" + body[..<closingBrace.lowerBound] + extraCalls + "\n}\n")
            .write(toFile: consumer, atomically: true, encoding: .utf8)
        let output = directory.appendingPathComponent("consumer").path
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "BoundedConsumer", inputs: [consumer], outputPath: output, emit: .executable,
            searchPaths: [library + ".kklib"], target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == expectedOutput + "impl:text\nimported\nimpl:number\n19\n")

        for receiver in ["BoundedDelegate(BoundedImpl())", "ImportedDelegate(BoundedImpl())", "(BoundedImpl() as Bounded)"] {
            let invalid = imports + "\nfun main() { \(receiver).echo(true) }\n"
            let context = CompilerDriver().runFrontend(options: CompilerOptions(
                moduleName: "InvalidBoundedConsumer", inputs: [consumer], outputPath: output, emit: .executable,
                searchPaths: [library + ".kklib"], target: defaultTargetTriple(), stdlibLibraryPath: stdlib
            ), inMemorySources: [consumer: Data(invalid.utf8)]).context
            #expect(context.diagnostics.hasError, "\(receiver)")
            #expect(context.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-BOUND" || $0.code == "KSWIFTK-SEMA-0002" },
                    "\(context.diagnostics.diagnostics)")
        }
    }
}
