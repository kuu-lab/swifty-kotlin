#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func setOperatorsRetainSetTypeAndIterationOrder(mode: EmitMode) throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/JVMOwnStdlib")
        let source = try String(contentsOf: fixtures.appendingPathComponent("setOperatorOverloads.kt"), encoding: .utf8)
        let expected = try String(contentsOf: fixtures.appendingPathComponent("setOperatorOverloads.out"), encoding: .utf8)
        try withWorkspace { root in
            let library = try ownStdlibRuntime()
            let result = try compile(source, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-Xverify:all", "-cp", artifact + ":" + library.path, "HelloKt"])
            #expect(execution.stdout == expected)
            #expect(execution.stderr.isEmpty)
            _ = try jvmTool("kotlinc", ["hello.kt", "-d", "official.jar"], root: root)
            let foreign = try java(["-Xverify:all", "-cp", root.appendingPathComponent("official.jar").path + ":" + library.path, "HelloKt"])
            #expect(foreign.stdout == expected)
            #expect(foreign.stderr.isEmpty)
        }
    }
}
#endif
