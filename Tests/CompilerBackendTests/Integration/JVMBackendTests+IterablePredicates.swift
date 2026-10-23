#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func iterablePredicatesMatchKotlinStdlib(mode: EmitMode) throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/JVMOwnStdlib")
        let source = try String(contentsOf: fixtures.appendingPathComponent("iterablePredicates.kt"), encoding: .utf8)
        let expected = try String(contentsOf: fixtures.appendingPathComponent("iterablePredicates.out"), encoding: .utf8)
        try withWorkspace { root in
            let compiled = try compile(source, root: root, mode: mode)
            try #require(compiled.0 == 0, "\(compiled.1.map(\.message))")

            let runtime = try m11Runtime()
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let candidate = try java(["-cp", artifact + ":" + runtime, "HelloKt"])
            #expect(candidate.stdout == expected)
            #expect(candidate.stderr.isEmpty)

            _ = try jvmTool("kotlinc", ["hello.kt", "-cp", runtime, "-d", "reference.jar"], root: root)
            let reference = try java(["-cp", root.appendingPathComponent("reference.jar").path + ":" + runtime, "HelloKt"])
            #expect(reference.stdout == expected)
            #expect(reference.stderr.isEmpty)
        }
    }
}
#endif
