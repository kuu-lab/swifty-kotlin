import Foundation
@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct DelegatedMemberExtensionArtifactTests {
    private let expectedOutput = "OK\nOK\nbase\ndirect:OK\nString:OK\nInt:42\nInherited:OK\nplain\n"
    private let applyReceiverExpectedOutput = "OK\nOK\n"

    @Test(arguments: [0, 2])
    func delegatedMemberExtensionsPreserveBothReceiversFromFreshArtifact(optimization: Int) throws {
        try compileAndRun(fromSource: false, optimization: optimization)
    }

    // Source O2 is blocked by KUU-2241's existing high-arity FunctionN.invoke LLVM ABI failure.
    @Test
    func delegatedMemberExtensionsPreserveBothReceiversFromSourceO0() throws {
        try compileAndRun(fromSource: true, optimization: 0)
    }

    @Test(arguments: [false, true], [0, 2])
    func delegatedMemberExtensionPropertyWorksInApplyReceiverContext(
        fromSource: Bool,
        optimization: Int
    ) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("delegated-member-extension-apply.kt").path
        try diffCaseSource("kuu_2580_member_extension_apply_receiver.kt")
            .write(toFile: input, atomically: true, encoding: .utf8)
        let output = directory.appendingPathComponent("delegated-member-extension-apply").path
        let stdlib = fromSource ? nil : try testStdlibArtifactPath()
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "DelegatedMemberExtensionApply",
            inputs: [input],
            outputPath: output,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: stdlib,
            allowDefaultStdlibLibrary: !fromSource
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == applyReceiverExpectedOutput)
    }

    private func compileAndRun(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("delegated-member-extension.kt").path
        try diffCaseSource("kuu_2373_delegated_member_extension.kt")
            .write(toFile: input, atomically: true, encoding: .utf8)
        let output = directory.appendingPathComponent("delegated-member-extension").path
        let stdlib = fromSource ? nil : try testStdlibArtifactPath()
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "DelegatedMemberExtension",
            inputs: [input],
            outputPath: output,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: stdlib,
            allowDefaultStdlibLibrary: !fromSource
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == expectedOutput)
    }
}
