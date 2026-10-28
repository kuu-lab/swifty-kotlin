import Foundation
@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct GenericMethodDelegationArtifactTests {
    private var expectedOutput: String {
        "7\ninferred\n9\n11\nbound\nexplicit\ninterface\nsecond\n13\ntext:overload\ntext:interface overload\ngeneric\n18\n19\nshadow\nOK\n"
    }

    @Test(arguments: [false, true], [0, 2])
    func sourceAndStdlibArtifactPreserveGenericCalls(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("generic.kt").path
        try diffCaseSource("class_delegation_generic_methods.kt").write(toFile: input, atomically: true, encoding: .utf8)
        let output = directory.appendingPathComponent("generic").path
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "GenericDelegation", inputs: [input], outputPath: output, emit: .executable,
            target: defaultTargetTriple(), optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(), allowDefaultStdlibLibrary: !fromSource
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == expectedOutput)
    }

    @Test(arguments: [0, 2])
    func importedInterfacesAndExportedForwardersPreserveBinders(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let stdlib = try testStdlibArtifactPath()
        let source = try diffCaseSource("class_delegation_generic_methods.kt")
        let main = try #require(source.range(of: "fun main() {"))
        let api = directory.appendingPathComponent("api.kt").path
        let library = directory.appendingPathComponent("GenericAPI").path
        try ("package delegation.generics\n" + source[..<main.lowerBound])
            .write(toFile: api, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "GenericAPI", inputs: [api], outputPath: library, emit: .library,
            target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let consumer = directory.appendingPathComponent("consumer.kt").path
        let extraDeclarations = """
        import delegation.generics.*
        class ImportedDelegate(base: Echo) : Echo by base
        class ImportedGeneric<C>(base: Child<C>) : Child<C> by base
        class ImportedGenericArgImpl : A<Int> {
            override fun foo(t: Int): String = if (t == 42) "OK" else "Fail $t"
        }
        """
        let extraCalls = """
            println(ImportedDelegate(EchoImpl()).echo(23))
            println(ImportedGeneric<CharSequence>(ChildImpl<CharSequence>()).choose<String>("imported"))
            println(Derived(ImportedGenericArgImpl()).foo(42))
        """
        let mainBody = String(source[main.lowerBound...])
        let closingBrace = try #require(mainBody.range(of: "}", options: .backwards))
        try (extraDeclarations + "\n" + mainBody[..<closingBrace.lowerBound] + extraCalls + "\n}\n")
            .write(toFile: consumer, atomically: true, encoding: .utf8)
        let output = directory.appendingPathComponent("consumer").path
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "GenericConsumer", inputs: [consumer], outputPath: output, emit: .executable,
            searchPaths: [library + ".kklib"], target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == expectedOutput + "23\nimported\nOK\n")

        for receiver in ["GenericDelegate<CharSequence>(ChildImpl<CharSequence>())", "ImportedGeneric<CharSequence>(ChildImpl<CharSequence>())"] {
            let invalid = extraDeclarations + "\nfun main() { \(receiver).choose<Int>(7) }\n"
            let context = CompilerDriver().runFrontend(options: CompilerOptions(
                moduleName: "InvalidGenericConsumer", inputs: [consumer], outputPath: output, emit: .executable,
                searchPaths: [library + ".kklib"], target: defaultTargetTriple(), stdlibLibraryPath: stdlib
            ), inMemorySources: [consumer: Data(invalid.utf8)]).context
            #expect(context.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-TYPE-0001" },
                    "\(context.diagnostics.diagnostics)")
        }
    }
}
