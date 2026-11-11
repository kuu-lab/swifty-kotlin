#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func arrayWithIndexMatchesOfficialAndGeneratedStdlib(mode: EmitMode) throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repository.appendingPathComponent("Scripts/diff_cases/jvm_array_withindex.kt"),
            encoding: .utf8
        )
        let expected = """
        0:null
        1:before
        0:null 1:after
        10
        21
        32
        true
        0:9
        0:9 1:8 2:30
        1:8
        0:-128 1:127
        0:-32768 1:32767
        0:2147483648 1:-1
        0:1.5 1:-2.0
        0:2.5 1:-3.0
        0:true 1:false
        0:a 1:z
        0:4294967295
        1:1
        0:18446744073709551615
        0:4294967295 1:2
        0:18446744073709551615 1:3
        0:255 1:4
        0:65535 1:5
        false
        false
        false
        exhausted

        """
        try withWorkspace { root in
            try runRuntimeParity(source, expected: expected, mode: mode, root: root)
        }
    }

    @Test(arguments: ["", "@OptIn(ExperimentalUnsignedTypes::class)", "@ExperimentalUnsignedTypes"])
    func arrayWithIndexHonorsUnsignedOptIn(annotation: String) throws {
        try withWorkspace { root in
            let result = try compile("""
            \(annotation)
            fun indexed(values: UIntArray): Iterable<IndexedValue<UInt>> = values.withIndex()
            """, root: root, mode: .jvmJar)
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let optInDiagnostics = result.1.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }
            if annotation.isEmpty {
                #expect(optInDiagnostics.contains {
                    $0.severity == .warning && $0.message.contains("kotlin.ExperimentalUnsignedTypes")
                })
            } else {
                #expect(optInDiagnostics.isEmpty)
            }
        }
    }

    @Test
    func arrayWithIndexUsesUserDefinedExtension() throws {
        try withWorkspace { root in
            try runM11("""
            fun IntArray.withIndex(): List<IndexedValue<Int>> = listOf(IndexedValue(9, 90))

            fun main() {
                val values = intArrayOf(10, 20)
                for ((index, value) in values.withIndex()) println("$index:$value")
                val indexed = values.withIndex()
                for ((index, value) in indexed) println("$index:$value")
            }
            """, expected: "9:90\n9:90\n", mode: .jvmJar, root: root)
        }
    }
}
#endif
