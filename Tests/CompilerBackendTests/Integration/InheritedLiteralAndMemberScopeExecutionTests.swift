@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import TestStdlibCache
import Testing

@Suite(.serialized)
struct InheritedLiteralAndMemberScopeExecutionTests {
    private func fixture(_ name: String) throws -> Data {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        return try Data(contentsOf: root.appendingPathComponent(name))
    }

    private func stdlib() throws -> String {
        TestStdlibCache.shared.prepare()
        let path = try #require(CompilerOptions.defaultStdlibLibraryPath)
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        let data = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        let manifest = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        try #require(manifest["moduleName"] as? String == "KSwiftKStdlib")
        try #require(manifest["stdlibManifestHash"] as? String == BundledStdlib.manifestHash())
        try #require(manifest["kotlinLanguageVersion"] as? String == "2.3.10")
        return path
    }

    @Test(arguments: [false, true], [0, 2])
    func sourceAndLibraryExecutionKeepOverloadAndReceiverPriority(library: Bool, optimization: Int) throws {
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let artifact = library ? try stdlib() : nil
        let source = try fixture("Scripts/diff_cases/inherited_literal_member_scope.kt")
        let expected = try fixture("Scripts/diff_cases/inherited_literal_member_scope.expected")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var completed = false
        defer {
            if completed {
                try? FileManager.default.removeItem(at: directory)
            } else {
                print("KUU-1771 failed artifacts retained at \(directory.path)")
            }
        }
        let input = directory.appendingPathComponent("Contract.kt")
        try source.write(to: input)
        try expected.write(to: directory.appendingPathComponent("execution.expected"))
        let executable = directory.appendingPathComponent("contract")
        let options = CompilerOptions(
            moduleName: "KUU1771Contract", inputs: [input.path], outputPath: executable.path,
            emit: .executable, target: TargetTriple.hostDefault(), optLevel: level,
            stdlibLibraryPath: artifact, allowDefaultStdlibLibrary: false
        )
        try #require(options.stdlibLibraryPath == artifact)
        try #require(options.includeStdlib == !library)
        let compilation = makeTestDriver().runForTesting(options: options)
        try String(describing: compilation).write(
            to: directory.appendingPathComponent("consumer-compilation.txt"), atomically: true, encoding: .utf8
        )
        try assertCompilationSucceeded(compilation)
        let result = try CommandRunner.run(executable: executable.path, arguments: [], timeout: 15)
        try result.stdout.write(to: directory.appendingPathComponent("execution.stdout"), atomically: true, encoding: .utf8)
        try result.stderr.write(to: directory.appendingPathComponent("execution.stderr"), atomically: true, encoding: .utf8)
        try #require(result.exitCode == 0, "\(result.stderr)")
        try #require(Data(result.stdout.utf8) == expected)
        try #require(try Data(contentsOf: input) == source)
        completed = true
    }

    @Test(arguments: [0, 2])
    func independentProducerAndConsumerPreserveImportedMemberContracts(optimization: Int) throws {
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let artifact = try stdlib()
        let source = try fixture("Scripts/diff_cases/inherited_literal_member_scope.kt")
        let consumer = try fixture("Scripts/compiler_fixtures/overload_scope/LibraryConsumer.kt")
        let expected = try fixture("Scripts/compiler_fixtures/overload_scope/LibraryConsumer.expected")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var completed = false
        defer {
            if completed {
                try? FileManager.default.removeItem(at: directory)
            } else {
                print("KUU-1771 failed artifacts retained at \(directory.path)")
            }
        }
        let producerPath = directory.appendingPathComponent("Producer.kt")
        try source.write(to: producerPath)
        let output = directory.appendingPathComponent("producer")
        let producerOptions = CompilerOptions(
            moduleName: "KUU1771Producer", inputs: [producerPath.path], outputPath: output.path,
            emit: .library, target: TargetTriple.hostDefault(), optLevel: level,
            stdlibLibraryPath: artifact, allowDefaultStdlibLibrary: false
        )
        try #require(producerOptions.inputs == [producerPath.path])
        try #require(producerOptions.stdlibLibraryPath == artifact)
        try #require(!producerOptions.includeStdlib)
        let producerCompilation = makeTestDriver().runForTesting(options: producerOptions)
        try String(describing: producerCompilation).write(
            to: directory.appendingPathComponent("producer-compilation.txt"), atomically: true, encoding: .utf8
        )
        try assertCompilationSucceeded(producerCompilation)
        let producerArtifact = output.appendingPathExtension("kklib")
        let manifest = try #require(JSONSerialization.jsonObject(
            with: Data(contentsOf: producerArtifact.appendingPathComponent("manifest.json"))
        ) as? [String: Any])
        try #require(manifest["moduleName"] as? String == "KUU1771Producer")
        let metadata = try String(contentsOf: producerArtifact.appendingPathComponent("metadata.bin"), encoding: .utf8)
        try #require(MetadataDecoder().decode(metadata).contains { $0.fqName == "collisioncontract.BaseReader.read" })
        let input = directory.appendingPathComponent("Consumer.kt")
        try consumer.write(to: input)
        try expected.write(to: directory.appendingPathComponent("execution.expected"))
        let frontend = makeCompilationContext(
            inputs: [input.path], searchPaths: [producerArtifact.path],
            stdlibLibraryPath: artifact, allowDefaultStdlibLibrary: false
        )
        try runSema(frontend)
        try String(describing: frontend.diagnostics.diagnostics).write(
            to: directory.appendingPathComponent("consumer-sema.txt"), atomically: true, encoding: .utf8
        )
        try #require(!frontend.diagnostics.hasError, "\(frontend.diagnostics.diagnostics)")
        let ast = try #require(frontend.ast)
        let sema = try #require(frontend.sema)
        let reads = ast.arena.exprs.enumerated().compactMap { index, expr -> ExprID? in
            guard case let .memberCall(_, name, _, _, _) = expr,
                  frontend.interner.resolve(name) == "read" else { return nil }
            let id = ExprID(rawValue: Int32(index))
            guard let range = ast.arena.exprRange(id),
                  frontend.sourceManager.path(of: range.start.file) == input.path,
                  sema.bindings.callBinding(for: id) != nil else { return nil }
            return id
        }
        try #require(reads.count == 1)
        let read = try #require(reads.first)
        let binding = try #require(sema.bindings.callBinding(for: read))
        try String(describing: binding).write(
            to: directory.appendingPathComponent("consumer-binding.txt"), atomically: true, encoding: .utf8
        )
        let imported = try #require(sema.symbols.symbol(binding.chosenCallee))
        try #require(imported.flags.contains(.importedLibrary))
        try #require(imported.fqName.map(frontend.interner.resolve) == ["collisioncontract", "BaseReader", "read"])
        let importedSignature = try #require(sema.symbols.functionSignature(for: imported.id))
        try #require(importedSignature.parameterTypes.count == 2)
        try #require(importedSignature.parameterTypes[1] == sema.types.longType)
        try #require(importedSignature.returnType == sema.types.longType)

        let rejected = directory.appendingPathComponent("Rejected.kt")
        let rejectedSource = try fixture("Scripts/compiler_fixtures/overload_scope/LibraryConsumerRejected.kt")
        try rejectedSource.write(to: rejected)
        let rejectedFrontend = makeCompilationContext(
            inputs: [rejected.path], searchPaths: [producerArtifact.path],
            stdlibLibraryPath: artifact, allowDefaultStdlibLibrary: false
        )
        try runSema(rejectedFrontend)
        try String(describing: rejectedFrontend.diagnostics.diagnostics).write(
            to: directory.appendingPathComponent("rejected-sema.txt"), atomically: true, encoding: .utf8
        )
        let errors = rejectedFrontend.diagnostics.diagnostics.filter { $0.severity == .error }
        try #require(errors.count == 1)
        try #require(errors.first?.code == "KSWIFTK-SEMA-0002")
        let executable = directory.appendingPathComponent("consumer")
        let options = CompilerOptions(
            moduleName: "KUU1771Consumer", inputs: [input.path], outputPath: executable.path,
            emit: .executable, searchPaths: [producerArtifact.path], target: TargetTriple.hostDefault(),
            optLevel: level, stdlibLibraryPath: artifact, allowDefaultStdlibLibrary: false
        )
        try #require(options.inputs == [input.path])
        try #require(options.stdlibLibraryPath == artifact)
        try #require(!options.includeStdlib)
        let compilation = makeTestDriver().runForTesting(options: options)
        try String(describing: compilation).write(
            to: directory.appendingPathComponent("consumer-compilation.txt"), atomically: true, encoding: .utf8
        )
        try assertCompilationSucceeded(compilation)
        let result = try CommandRunner.run(executable: executable.path, arguments: [], timeout: 15)
        try result.stdout.write(to: directory.appendingPathComponent("execution.stdout"), atomically: true, encoding: .utf8)
        try result.stderr.write(to: directory.appendingPathComponent("execution.stderr"), atomically: true, encoding: .utf8)
        try #require(result.exitCode == 0, "\(result.stderr)")
        try #require(Data(result.stdout.utf8) == expected)
        try #require(try Data(contentsOf: producerPath) == source)
        try #require(try Data(contentsOf: input) == consumer)
        try #require(try Data(contentsOf: rejected) == rejectedSource)
        completed = true
    }
}
