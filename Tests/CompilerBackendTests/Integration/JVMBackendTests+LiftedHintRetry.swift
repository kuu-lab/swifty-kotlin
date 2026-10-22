#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func incompatibleLiftedListHintsStopAfterOneRetry(mode: EmitMode) throws {
        for (declaration, callee) in [
            ("fun accepts(values: Iterable<String>) {}", "accepts"),
            ("class Owner { class Nested(val values: Iterable<String>) }", "Owner.Nested"),
        ] {
            try withWorkspace { root in
                let rejected = try compile("""
                \(declaration)
                fun main() { \(callee)(listOf(1)) }
                """, root: root, mode: mode)
                #expect(rejected.0 != 0)
                #expect(rejected.1.contains { $0.severity == .error && ($0.code.hasPrefix("KSWIFTK-SEMA") || $0.code.hasPrefix("KSWIFTK-TYPE")) })
                #expect(!rejected.1.contains { $0.code.hasPrefix("KSWIFTK-ICE") })
                let output = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
                #expect(!FileManager.default.fileExists(atPath: output.path))
                let accepted = try compile("""
                \(declaration)
                fun main() { \(callee)(listOf("one", "two")) }
                """, root: root, mode: mode)
                #expect(accepted.0 == 0, "\(accepted.1.map(\.message))")
            }
        }
    }
}
#endif
