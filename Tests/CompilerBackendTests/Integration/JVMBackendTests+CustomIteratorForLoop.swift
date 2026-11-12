#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func forLoopUsesResolvedIteratorConventionForNonIterableReceivers(mode: EmitMode) throws {
        let source = """
        class Values {
            var iteratorCalls = 0
            operator fun iterator(): Iterator<Int> {
                iteratorCalls += 1
                return listOf(1, 2, 3).iterator()
            }
        }

        class Cursor(private val values: List<Int>) {
            private var index = 0
            operator fun hasNext(): Boolean = index < values.size
            operator fun next(): Int = values[index++]
        }

        class CursorValues {
            var iteratorCalls = 0
            operator fun iterator(): Cursor {
                iteratorCalls += 1
                return Cursor(listOf(2, 3, 4))
            }
        }

        class EmptyValues {
            var iteratorCalls = 0
            operator fun iterator(): Iterator<Int> {
                iteratorCalls += 1
                return emptyList<Int>().iterator()
            }
        }

        class CountingIterable : Iterable<Int> {
            var iteratorCalls = 0
            override fun iterator(): Iterator<Int> {
                iteratorCalls += 1
                return listOf(4, 5).iterator()
            }
        }

        fun sum(values: Values): Int {
            var total = 0
            for (value in values) total += value
            return total
        }

        fun sumEmpty(values: EmptyValues): Int {
            var total = 0
            for (value in values) total += value
            return total
        }

        fun sumCursor(values: CursorValues): Int {
            var total = 0
            for (value in values) total += value
            return total
        }

        fun main() {
            val values = Values()
            println(sum(values))
            println(values.iteratorCalls)

            val cursorValues = CursorValues()
            println(sumCursor(cursorValues))
            println(cursorValues.iteratorCalls)

            val empty = EmptyValues()
            println(sumEmpty(empty))
            println(empty.iteratorCalls)

            val iterable = CountingIterable()
            var iterableTotal = 0
            for (value in iterable) iterableTotal += value
            println(iterableTotal)
            println(iterable.iteratorCalls)

            var arrayTotal = 0
            for (value in intArrayOf(6, 7, 8)) arrayTotal += value
            println(arrayTotal)
        }
        """
        let expected = "6\n1\n9\n1\n0\n1\n9\n1\n21\n"

        try withWorkspace { root in
            try runM11(source, expected: expected, mode: mode, root: root)

            let runtime = try m11Runtime()
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let consumerSource = root.appendingPathComponent("JavaConsumer.java")
            try """
            public final class JavaConsumer {
                public static void main(String[] args) {
                    Values values = new Values();
                    int total = HelloKt.sum(values);
                    if (total != 6 || values.getIteratorCalls() != 1) {
                        throw new AssertionError(total + ":" + values.getIteratorCalls());
                    }
                    CursorValues cursorValues = new CursorValues();
                    int cursorTotal = HelloKt.sumCursor(cursorValues);
                    if (cursorTotal != 9 || cursorValues.getIteratorCalls() != 1) {
                        throw new AssertionError(cursorTotal + ":" + cursorValues.getIteratorCalls());
                    }
                    System.out.println("consumer-ok");
                }
            }
            """.write(to: consumerSource, atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", artifact.path + ":" + runtime, consumerSource.path, "-d", root.path], root: root)
            let consumer = try java(["-cp", root.path + ":" + artifact.path + ":" + runtime, "JavaConsumer"])
            #expect(consumer.exitCode == 0)
            #expect(consumer.stdout == "consumer-ok\n")
            #expect(consumer.stderr.isEmpty)
        }
    }

    @Test
    func rejectsForLoopWhenResolvedIteratorLacksRequiredOperators() throws {
        try withWorkspace { root in
            let result = try compile("""
            class Invalid {
                operator fun iterator(): Int = 1
            }
            fun main() {
                for (value in Invalid()) println(value)
            }
            """, root: root, mode: .jvmJar)

            #expect(result.0 != 0)
            #expect(result.1.contains {
                $0.code == "KSWIFTK-SEMA-0172" && $0.message.contains("hasNext()")
            })
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("hello.jar").path))
        }
    }
}
#endif
