#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func safeChainIndexedAccessSkipsIndexOnNullReceiver(mode: EmitMode) throws {
        try withWorkspace { root in
            let source = """
            var indexEvaluations = 0

            fun index(): Int {
                indexEvaluations += 1
                return 0
            }

            class Box {
                operator fun get(index: Int): Int = 40 + index
            }
            class Source(val box: Box)

            fun main() {
                val missing: Source? = null
                val nullResult = missing?.box[index()]
                println(nullResult == null)
                println(indexEvaluations)

                val present = Source(Box())
                println(present?.box[index()])
                println(indexEvaluations)
            }
            """
            let result = try compile(source, root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            let execution = try java(mode == .jvmJar
                ? ["-jar", root.appendingPathComponent("hello.jar").path]
                : ["-cp", root.appendingPathComponent("classes").path, "HelloKt"])
            #expect(execution.exitCode == 0, "\(execution.stderr)")
            #expect(execution.stdout == "true\n0\n40\n1\n")
            #expect(execution.stderr.isEmpty)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func safeChainIndexedAccessHandlesUnitTerminatedAndNested(mode: EmitMode) throws {
        try withWorkspace { root in
            let source = """
            var indexEvaluations = 0

            fun index(): Int {
                indexEvaluations += 1
                return 0
            }

            class UnitBox {
                operator fun get(i: Int): Unit { println("unit $i") }
            }
            class UnitSource(val box: UnitBox)
            class ListBox(val values: List<Int>)
            class Matrix(val rows: List<List<Int>>)

            fun unitStmt(source: UnitSource?) { source?.box[index()] }
            fun terminated(box: ListBox?): Int = box?.values[throw IllegalStateException()] ?: -1

            fun main() {
                unitStmt(null)
                unitStmt(UnitSource(UnitBox()))
                println(terminated(null))

                val missing: Matrix? = null
                println(missing?.rows[1][0] == null)
                val present = Matrix(listOf(listOf(1, 2), listOf(3, 4)))
                println(present?.rows[1][0])
                println(indexEvaluations)
            }
            """
            let result = try compile(source, root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            let execution = try java(mode == .jvmJar
                ? ["-jar", root.appendingPathComponent("hello.jar").path]
                : ["-cp", root.appendingPathComponent("classes").path, "HelloKt"])
            #expect(execution.exitCode == 0, "\(execution.stderr)")
            #expect(execution.stdout == "unit 0\n-1\ntrue\n3\n1\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
