#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func intArraySliceArrayMatchesOfficialAndGeneratedStdlib(mode: EmitMode) throws {
        let source = """
        private fun observeBoundary(values: IntArray, range: IntRange, label: String) {
            try {
                values.sliceArray(range)
                println("$label:accepted")
            } catch (error: ArrayIndexOutOfBoundsException) {
                println("$label:start")
            } catch (error: IndexOutOfBoundsException) {
                println("$label:end")
            }
        }

        fun main() {
            val values = intArrayOf(1, 2, 3)
            println(values.sliceArray(0..2).contentToString())
            println(values.sliceArray(1..2).contentToString())
            println(values.sliceArray(2..1).contentToString())
            println(values.sliceArray(4..3).contentToString())
            println(IntArray(0).sliceArray(0..-1).contentToString())
            observeBoundary(values, -1..1, "negative")
            observeBoundary(values, 0..3, "past-end")
        }
        """
        let expected = """
        [1, 2, 3]
        [2, 3]
        []
        []
        []
        negative:start
        past-end:end

        """
        try withWorkspace { root in
            try runRuntimeParity(source, expected: expected, mode: mode, root: root)
        }
    }

    @Test
    func intArraySliceArrayExposesJavaFacade() throws {
        let library = try ownStdlibRuntime()
        try withWorkspace { root in
            let source = """
            public final class SliceArrayConsumer {
                public static void main(String[] args) {
                    int[] values = new int[] {1, 2, 3};
                    System.out.println(java.util.Arrays.toString(
                        kotlin.collections.ArraysKt.sliceArray(values, new kotlin.ranges.IntRange(1, 2))));
                    System.out.println(java.util.Arrays.toString(
                        kotlin.collections.ArraysKt.sliceArray(values, new kotlin.ranges.IntRange(2, 1))));
                    try {
                        kotlin.collections.ArraysKt.sliceArray(values, new kotlin.ranges.IntRange(0, 3));
                        System.out.println("past-end:accepted");
                    } catch (IndexOutOfBoundsException error) {
                        System.out.println("past-end:rejected");
                    }
                }
            }
            """
            let consumer = root.appendingPathComponent("SliceArrayConsumer.java")
            try source.write(to: consumer, atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["--release", "8", "-cp", library.path, consumer.path], root: root)
            let execution = try java(["-cp", root.path + ":" + library.path, "SliceArrayConsumer"])
            #expect(execution.stdout == "[2, 3]\n[]\npast-end:rejected\n")
            #expect(execution.stderr.isEmpty)
        }
    }

    @Test
    func intArraySliceArrayRejectsNonRangeArgument() throws {
        try withWorkspace { root in
            let result = try compile("fun main() { intArrayOf(1, 2, 3).sliceArray(1) }", root: root, mode: .jvmJar)
            #expect(result.0 != 0)
            #expect(result.1.contains { $0.severity == .error })
        }
    }
}
#endif
