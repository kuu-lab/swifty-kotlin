#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func explicitBackingFieldKeepsStorageTypeBehindPublicProperty(mode: EmitMode) throws {
        let source = #"""
        class Holder {
            val values: List<Int>
                field = mutableListOf<Int>()
            val arrayValues: List<Int>
                field: ArrayList<Int> = arrayListOf<Int>()

            fun add(value: Int) {
                values.add(value)
                this.arrayValues.add(value)
            }
        }
        fun main() {
            val holder = Holder()
            holder.add(3)
            println(holder.values.size)
            println(holder.arrayValues.size)
        }
        """#
        try withWorkspace { root in
            try runM11(source, expected: "1\n1\n", mode: mode, root: root)

            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let inspection = try javap(["-v", "-p", "-classpath", artifact, "Holder"])
            #expect(inspection.stdout.contains("private final java.util.ArrayList<java.lang.Integer> arrayValues;"))
            #expect(inspection.stdout.contains("Ljava/util/ArrayList<Ljava/lang/Integer;>;"))
            #expect(inspection.stdout.contains("public final java.util.List<java.lang.Integer> getArrayValues();"))
            #expect(inspection.stdout.contains("descriptor: ()Ljava/util/List;"))
            #expect(inspection.stderr.isEmpty)
        }
    }

    @Test
    func invalidExplicitBackingFieldTypesAreRejected() throws {
        let invalidSources = [
            """
            class Holder {
                val values: List<Int>
                    field: MutableList<Int> = mutableListOf<String>()
            }
            fun main() {}
            """,
            """
            class Holder {
                val values: List<Int>
                    field: String = "bad"
            }
            fun main() {}
            """,
            """
            class Holder {
                val values: List<Int>
                    field = mutableListOf<Int>()
            }
            fun main() {
                val holder = Holder()
                holder.values.add(4)
            }
            """,
        ]
        try withWorkspace { root in
            for (index, source) in invalidSources.enumerated() {
                let caseRoot = root.appendingPathComponent("invalid-\(index)", isDirectory: true)
                try FileManager.default.createDirectory(at: caseRoot, withIntermediateDirectories: true)
                let result = try compile(source, root: caseRoot, mode: .jvmJar)
                let diagnostics = result.1.map { "\($0.severity) \($0.code): \($0.message)" }
                #expect(result.0 == 1, "case \(index): \(diagnostics)")
                #expect(result.1.contains { $0.severity == .error }, "case \(index): \(diagnostics)")
                #expect(!result.1.contains { $0.code == "KSWIFTK-JVM-0001" }, "case \(index): \(diagnostics)")
                #expect(!FileManager.default.fileExists(atPath: caseRoot.appendingPathComponent("hello.jar").path))

                try source.write(to: caseRoot.appendingPathComponent("Invalid.kt"), atomically: true, encoding: .utf8)
                do {
                    _ = try jvmTool("kotlinc", ["Invalid.kt", "-d", "reference.jar"], root: caseRoot)
                    Issue.record("kotlinc accepted invalid explicit backing field case \(index)")
                } catch CommandRunnerError.nonZeroExit(let error) {
                    #expect(error.exitCode != 0, "case \(index)")
                }
            }
        }
    }
}
#endif
