#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func bundledJVMComparisonHelpers(mode: EmitMode) throws {
        try withWorkspace { root in
            let repositoryRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let comparisonsDirectory = repositoryRoot
                .appendingPathComponent("Sources/CompilerCore/Stdlib/jvm/kotlin/comparisons")
            let collectionsDirectory = repositoryRoot
                .appendingPathComponent("Sources/CompilerCore/Stdlib/jvm/kotlin/collections")
            let comparisons = try String(
                contentsOf: comparisonsDirectory.appendingPathComponent("Comparisons.kt"),
                encoding: .utf8
            )
            let factories = try String(
                contentsOf: comparisonsDirectory.appendingPathComponent("ComparisonFactories.kt"),
                encoding: .utf8
            )
            let comparisonsWith = try String(
                contentsOf: collectionsDirectory.appendingPathComponent("ComparisonsWith.kt"),
                encoding: .utf8
            )
            let runtime = try m11Runtime()

            let source = """
            fun main() {
                println(compareValues(3, 3))
                val comparator = compareBy<String> { it.length }.thenBy { it }
                println(comparator.compare("bb", "ba"))
                val sorted = java.util.ArrayList<String>()
                sorted.add("bb")
                sorted.add("a")
                java.util.Collections.sort(sorted, comparator)
                println(sorted)
                println(maxOf(1, 5, 3))
                println(minOf("x", "y"))
                println(maxOf(0.0 / 0.0, 1.0))
                println(compareValuesBy("a", "bb", { value: String -> value.length }))
                println(maxOf("x", "y", comparator = reverseOrder<String>()))
                println(minOf("x", "y", comparator = reverseOrder<String>()))
                val numbers = java.util.ArrayList<Int>()
                numbers.add(1)
                numbers.add(5)
                numbers.add(3)
                println(numbers.maxOfWith(naturalOrder<Int>()) { it })
                println(numbers.minOfWith(naturalOrder<Int>()) { it })
                println(java.util.ArrayList<Int>().maxOfWithOrNull(naturalOrder<Int>()) { it })
            }
            """
            let app = try m22Build(
                root: root,
                sources: [
                    ("Comparator.kt", "package kotlin\nfun interface Comparator<T> : java.util.Comparator<T>"),
                    ("Comparisons.kt", comparisons),
                    ("ComparisonFactories.kt", factories),
                    ("ComparisonsWith.kt", comparisonsWith),
                    ("Main.kt", source),
                ],
                name: mode == .jvmJar ? "app.jar" : "classes",
                mode: mode,
                classpath: runtime.components(separatedBy: ":")
            )
            let errors = app.2.filter { $0.severity == .error }.map { diagnostic in
                "\(diagnostic.code)@\(diagnostic.primaryRange?.start.offset ?? -1): \(diagnostic.message)"
            }
            try #require(app.1 == 0, "\(errors)")

            let execution = try java(["-cp", app.0.path + ":" + runtime, "MainKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "0\n1\n[a, bb]\n5\nx\nNaN\n-1\nx\ny\n5\n1\nnull\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
