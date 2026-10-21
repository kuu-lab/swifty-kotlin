#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func floatingPredicatesPreserveIEEEAndNullableContracts(mode: EmitMode) throws {
        try withWorkspace { root in
            let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/JVMOwnStdlib")
            let source = try String(contentsOf: fixtures.appendingPathComponent("floatingPredicateBoundaries.kt"), encoding: .utf8)
            let expected = try String(contentsOf: fixtures.appendingPathComponent("floatingPredicateBoundaries.out"), encoding: .utf8)
            try runRuntimeParity(source, expected: expected, mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func floatingPredicatesAcceptPrimitiveGenericUpperBounds(mode: EmitMode) throws {
        try withWorkspace { root in
            try runRuntimeParity("""
            fun <T : Double> doubleValue(value: T): Boolean = value.isInfinite()
            fun <T : Float> floatValue(value: T): Boolean = value.isFinite()
            fun main() {
                println(doubleValue(Double.NEGATIVE_INFINITY))
                println(floatValue(Float.MIN_VALUE))
            }
            """, expected: "true\ntrue\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func floatingPredicatesPreserveUserExtensionAndMemberPriority(mode: EmitMode) throws {
        try withWorkspace { root in
            try runRuntimeParity("""
            fun Double.isInfinite(): Boolean = false
            fun Float.isFinite(): Boolean = false
            class Custom { fun isInfinite(): Boolean = true }
            fun main() {
                println(Double.POSITIVE_INFINITY.isInfinite())
                println(1.0f.isFinite())
                println(Custom().isInfinite())
                val value: Double? = Double.POSITIVE_INFINITY
                println(value?.isInfinite())
            }
            """, expected: "false\nfalse\ntrue\nfalse\n", mode: mode, root: root)
        }
    }
}
#endif
