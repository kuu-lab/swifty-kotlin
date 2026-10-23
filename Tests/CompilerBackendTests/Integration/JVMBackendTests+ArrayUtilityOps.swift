#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func arrayUtilitiesRunAgainstRepositoryStdlib(mode: EmitMode) throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixture = repository.appendingPathComponent("Scripts/diff_cases/array_utility_ops.kt")
        let expected = try String(
            contentsOf: repository.appendingPathComponent("Scripts/diff_cases/array_utility_ops.expected"),
            encoding: .utf8
        )
        let source = try String(contentsOf: fixture, encoding: .utf8)

        try withWorkspace { root in
            let implementation = repository.appendingPathComponent("Sources/CompilerCore/Stdlib/jvm/kotlin/collections/ArrayUtilities.kt")
            let implementationJar = root.appendingPathComponent("array-utilities.jar")
            // Put the repository facade before kotlin-stdlib so execution uses this implementation.
            _ = try jvmTool("kotlinc", ["-nowarn", "-Xallow-kotlin-package", implementation.path, "-d", implementationJar.path], root: root)

            let result = try compile(source, root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }
            let runtime = try m11Runtime()
            let output = mode == .jvmJar
                ? root.appendingPathComponent("hello.jar").path
                : root.appendingPathComponent("classes").path
            let execution = try java(["-cp", output + ":" + implementationJar.path + ":" + runtime, "HelloKt"])
            #expect(execution.stdout == expected)
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
