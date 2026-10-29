@testable import CompilerCore
import Foundation
import Testing

@Suite(.serialized)
struct PrimitiveIdentityEqualityTests {
    @Test(arguments: [false, true], [0, 2])
    func boxedBooleanSingletonIdentity(useArtifact: Bool, optimization: Int) throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 4 { root.deleteLastPathComponent() }
        let source = try String(contentsOf: root.appendingPathComponent(
            "Scripts/diff_cases/boxed_boolean_identity.kt"
        ), encoding: .utf8)
        if useArtifact {
            _ = try testStdlibArtifactPath()
        }
        try assertKotlinOutput(
            source,
            moduleName: "BoxedBooleanIdentity",
            expected: """
            true
            true
            false
            true
            true
            true
            true
            false
            true
            true
            true
            true
            false
            true
            false
            """ + "\n",
            optLevel: optimization == 0 ? .O0 : .O2,
            allowDefaultStdlibLibrary: useArtifact
        )
    }

    @Test(arguments: [false, true])
    func matchesJVMPrimitiveAndBoxedIdentity(useArtifact: Bool) throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 4 { root.deleteLastPathComponent() }
        let source = try String(contentsOf: root.appendingPathComponent(
            "Scripts/diff_cases/primitive_identity_equality.kt"
        ), encoding: .utf8)
        // Expected output from Kotlin 2.3.10/JVM. In particular, non-null
        // Int identity has no boxing-cache boundary and NaN is not identical.
        try assertKotlinOutput(
            source,
            moduleName: "PrimitiveIdentityEquality",
            expected: """
            true
            true
            true
            false
            true
            true
            true
            false
            false
            true
            true
            false
            false
            true
            true
            false
            false
            true
            true
            false
            false
            true
            true
            false
            true
            false
            false
            true
            true
            false
            false
            true
            false
            true
            false
            true
            false
            true
            true
            false
            true
            false
            """ + "\n",
            allowDefaultStdlibLibrary: useArtifact
        )
    }
}
