import Foundation
@testable import CompilerCore
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

    @Test
    func delegatedInterfaceExtensionPropertyReadWriteRuns() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("delegated-extension-property.kt").path
        try """
        interface Base { var Int.foo: String }
        class Impl : Base {
            var value: String = "OK"
            override var Int.foo: String
                get() = value
                set(v) { value = v }
        }
        class D : Base by Impl() {
            fun read(x: Int) = x.foo
            fun write(x: Int, value: String) { x.foo = value }
        }
        fun main() {
            val d = D()
            println(d.read(1))
            d.write(1, "updated")
            println(d.read(1))
        }
        """.write(toFile: input, atomically: true, encoding: .utf8)
        let output = directory.appendingPathComponent("delegated-extension-property").path
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "DelegatedExtensionProperty",
            inputs: [input],
            outputPath: output,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: .O0,
            stdlibLibraryPath: try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: true
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == "OK\nupdated\n")
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
