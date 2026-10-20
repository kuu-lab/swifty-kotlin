#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func deferredLocalsRejectInvalidInitializationBeforeReplacingOutput(mode: EmitMode) throws {
        let cases = [
            "fun main() { var value: Int; println(value) }",
            "fun main() { val value: Int; value = 1; value = 2 }",
            "fun read(flag: Boolean) { val value: Int; if (flag) value = 1; println(value) }",
            "fun read(flag: Boolean) { var value: Int; while (flag) { value = 1 }; println(value) }",
            "fun main() { var value: Int; value += 1 }",
            "fun main() { val value: Int; val initialize = { value = 1 }; initialize(); println(value) }",
        ]
        try withWorkspace { root in
            let output = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            if mode == .jvmClass { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
            let marker = mode == .jvmJar ? output : output.appendingPathComponent("marker")
            let original = Data("previous output".utf8)
            try original.write(to: marker)
            for source in cases {
                let result = try compile(source, root: root, mode: mode)
                #expect(result.0 != 0)
                #expect(result.1.contains { $0.severity == .error && $0.code.hasPrefix("KSWIFTK-SEMA") })
                #expect(!result.1.contains { $0.code.hasPrefix("KSWIFTK-ICE") })
                #expect(try Data(contentsOf: marker) == original)
                if mode == .jvmClass { #expect(try FileManager.default.contentsOfDirectory(atPath: output.path) == ["marker"]) }
            }
        }
    }
}
#endif
