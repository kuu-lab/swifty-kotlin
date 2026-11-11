#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func unitParametersAndArrayValuesUseJvmObjects() throws {
        try withWorkspace { root in
            let source = """
            fun accept(value: Unit): Int { return 42 }
            fun sameUnit(value: Unit): Boolean = value === Unit
            fun unitCount(vararg values: Unit): Int = values.size
            fun returnsUnit(): Unit = Unit
            fun main() {
                println(accept(Unit))
                println(sameUnit(Unit))
                val values: Array<Unit> = arrayOf(Unit, Unit)
                println(values.size)
                println(values[0] === Unit)
                println(values[1] === Unit)
                println(unitCount(Unit, Unit))
                returnsUnit()
            }
            """
            let runtime = try m11Runtime()
            let compiled = try compile(source, root: root, mode: .jvmJar)
            try #require(compiled.0 == 0, "\(compiled.1.map(\.message))")

            let artifact = root.appendingPathComponent("hello.jar")
            let candidate = try java(["-cp", artifact.path + ":" + runtime, "HelloKt"])
            let expected = "42\ntrue\n2\ntrue\ntrue\n2\n"
            #expect(candidate.stdout == expected)
            #expect(candidate.stderr.isEmpty)

            _ = try jvmTool("kotlinc", ["hello.kt", "-cp", runtime, "-d", "reference.jar"], root: root)
            let reference = try java(["-cp", root.appendingPathComponent("reference.jar").path + ":" + runtime, "HelloKt"])
            #expect(reference.stdout == candidate.stdout)
            #expect(reference.stderr.isEmpty)

            let bytecode = try javap(["-classpath", artifact.path + ":" + runtime, "-s", "-c", "HelloKt"])
            #expect(bytecode.stdout.contains("accept(kotlin.Unit);"))
            #expect(!bytecode.stdout.contains("accept(void);"))
            #expect(bytecode.stdout.contains("descriptor: (Lkotlin/Unit;)I"))
            #expect(bytecode.stdout.contains("descriptor: ([Lkotlin/Unit;)I"))
            #expect(bytecode.stdout.contains("void returnsUnit();\n    descriptor: ()V"))
            #expect(bytecode.stdout.contains("anewarray") && bytecode.stdout.contains("class kotlin/Unit"))
        }
    }
}
#endif
