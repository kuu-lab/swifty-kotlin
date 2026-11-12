#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m11MultiIndexOperatorsPreserveEvaluationOrderAndJavaABI(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            var events = ""
            var receiverCount = 0

            class Grid {
                var total = 0

                operator fun get(row: Int, column: Int): Int {
                    events = events + "G"
                    return row * 10 + column
                }

                operator fun get(index: Int): Int {
                    events = events + "g"
                    return index + 100
                }

                operator fun set(row: Int, column: Int, value: Int) {
                    events = events + "S"
                    total = row + column + value
                }

                operator fun set(index: Int, value: Int) {
                    events = events + "s"
                    total = index + value
                }
            }

            val sharedGrid = Grid()

            fun grid(): Grid {
                receiverCount += 1
                events = events + "R"
                return sharedGrid
            }

            fun rowIndex(): Int {
                events = events + "1"
                return 1
            }

            fun columnIndex(): Int {
                events = events + "2"
                return 2
            }

            fun assignedValue(): Int {
                events = events + "V"
                return 3
            }

            fun main() {
                events = ""
                receiverCount = 0
                println(grid()[rowIndex(), columnIndex()])
                println(events)
                println(receiverCount)

                events = ""
                receiverCount = 0
                grid()[rowIndex(), columnIndex()] = assignedValue()
                println(events)
                println(receiverCount)
                println(sharedGrid.total)

                events = ""
                receiverCount = 0
                println(grid()[rowIndex()])
                println(events)
                println(receiverCount)

                events = ""
                receiverCount = 0
                grid()[rowIndex()] = assignedValue()
                println(events)
                println(receiverCount)
                println(sharedGrid.total)
            }
            """, expected: "12\nR12G\n1\nR12VS\n1\n6\n101\nR1g\n1\nR1Vs\n1\n4\n", mode: mode, root: root)

            let runtime = try m11Runtime()
            let artifact = mode == .jvmJar
                ? root.appendingPathComponent("hello.jar").path
                : root.appendingPathComponent("classes").path
            let reference = root.appendingPathComponent("reference.jar").path
            let javaSource = """
            public class JavaConsumer {
                public static void main(String[] args) {
                    Grid target = new Grid();
                    System.out.println(target.get(3, 4));
                    target.set(1, 2, 3);
                    System.out.println(target.getTotal());
                }
            }
            """
            let javaSourcePath = root.appendingPathComponent("JavaConsumer.java")
            try javaSource.write(to: javaSourcePath, atomically: true, encoding: .utf8)

            let candidateConsumer = root.appendingPathComponent("candidate-consumer")
            try FileManager.default.createDirectory(at: candidateConsumer, withIntermediateDirectories: true)
            _ = try javac(["-classpath", artifact + ":" + runtime, "-d", candidateConsumer.path, javaSourcePath.path])
            let candidateRun = try java(["-classpath", candidateConsumer.path + ":" + artifact + ":" + runtime, "JavaConsumer"])
            #expect(candidateRun.stdout == "34\n6\n")
            #expect(candidateRun.stderr.isEmpty)

            let referenceConsumer = root.appendingPathComponent("reference-consumer")
            try FileManager.default.createDirectory(at: referenceConsumer, withIntermediateDirectories: true)
            _ = try javac(["-classpath", reference + ":" + runtime, "-d", referenceConsumer.path, javaSourcePath.path])
            let referenceRun = try java(["-classpath", referenceConsumer.path + ":" + reference + ":" + runtime, "JavaConsumer"])
            #expect(referenceRun.stdout == candidateRun.stdout)
            #expect(referenceRun.stderr.isEmpty)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m11MultiIndexOperatorArityMismatchIsRejectedBySema(mode: EmitMode) throws {
        try withWorkspace { root in
            let result = try compile("""
            class Grid {
                operator fun get(row: Int): Int = row
            }
            fun main() { println(Grid()[1, 2]) }
            """, root: root, mode: mode)

            #expect(result.0 != 0)
            #expect(!result.1.contains { $0.code == "KSWIFTK-JVM-0001" }, "\(result.1.map(\.message))")
            #expect(result.1.contains { $0.severity == .error }, "\(result.1.map(\.message))")
        }
    }

    @Test
    func m11MalformedMultiIndexSyntaxIsRejected() throws {
        try withWorkspace { root in
            let result = try compile("""
            class Grid {
                operator fun get(row: Int, column: Int): Int = row + column
            }
            fun main() { println(Grid()[1,, 2]) }
            """, root: root, mode: .jvmJar)

            #expect(result.0 != 0)
            #expect(result.1.contains { $0.code == "KSWIFTK-JVM-0001" })
        }
    }
}
#endif
