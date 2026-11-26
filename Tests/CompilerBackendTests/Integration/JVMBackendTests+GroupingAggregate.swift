#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func groupingAggregateAndAggregateToMatchBothRuntimes(mode: EmitMode) throws {
        try withWorkspace { root in
            try runRuntimeParity("""
            fun main() {
                val grouping = listOf("apple", "banana", "avocado", "blueberry", "cherry")
                    .groupingBy { it.substring(0, 1) }

                println(
                    grouping.aggregate { key, accumulator: Int?, element, first ->
                        if (first) element.length else accumulator!! + element.length
                    }
                )

                val destination = mutableMapOf("z" to 1, "a" to 100)
                val returned = grouping.aggregateTo(destination) { key, accumulator: Int?, element, first ->
                    if (accumulator == null) element.length else accumulator + element.length
                }
                println(returned)
                println(returned === destination)

                val firsts = mutableListOf<String>()
                val joined = grouping.aggregate { key, accumulator: String?, element, first ->
                    if (first) firsts.add(key)
                    if (accumulator == null) element else "$accumulator+$element"
                }
                println(joined)
                println(firsts)

                println(emptyList<String>().groupingBy { it }.aggregate { _, acc: Int?, e, _ -> (acc ?: 0) + e.length })
            }
            """, expected: "{a=12, b=15, c=6}\n{z=1, a=112, b=15, c=6}\ntrue\n{a=apple+avocado, b=banana+blueberry, c=cherry}\n[a, b, c]\n{}\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func groupingAggregateToAcceptsConcreteMapDestinations(mode: EmitMode) throws {
        try withWorkspace { root in
            try runRuntimeParity("""
            fun main() {
                val grouping = listOf("apple", "banana", "avocado", "blueberry", "cherry")
                    .groupingBy { it.substring(0, 1) }

                val linked = linkedMapOf("a" to 1)
                val linkedResult = grouping.aggregateTo(linked) { _, n: Int?, e, _ -> (n ?: 0) + e.length }
                println(linkedResult)
                println(linkedResult === linked)

                val hashed = hashMapOf("z" to 5)
                println(grouping.aggregateTo(hashed) { _, n: Int?, e, first -> if (first) e.length else n!! + e.length })
            }
            """, expected: "{a=13, b=15, c=6}\ntrue\n{a=12, z=5, b=15, c=6}\n", mode: mode, root: root)
        }
    }
}
#endif
