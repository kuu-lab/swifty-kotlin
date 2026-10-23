#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m22MapFactoriesAndConversions(mode: EmitMode) throws {
        let source = #"""
        fun main() {
            val original = linkedMapOf("b" to 2, "a" to 1, "b" to 3)
            println(original)

            val mutableCopy = original.toMutableMap()
            mutableCopy["c"] = 4
            println(original)
            println(mutableCopy)

            val empty = mutableMapOf<String, Int>()
            println(empty.toMap())
            println(mapOf("only" to 7).toMap())
            println(original.toMap())
            println(original.toSortedMap())
            println(sortedMapOf("b" to 2, "a" to 1, "b" to 3))
        }
        """#
        let expected = "{b=3, a=1}\n{b=3, a=1}\n{b=3, a=1, c=4}\n{}\n{only=7}\n{b=3, a=1}\n{a=1, b=3}\n{a=1, b=3}\n"
        let declarationsSource = #"""
        fun exerciseMapAPI(map: Map<String, Int>, comparator: kotlin.Comparator<String>) {
            val linked: java.util.LinkedHashMap<String, Int> = linkedMapOf()
            val linkedWithPairs: java.util.LinkedHashMap<String, Int> = linkedMapOf(Pair("b", 2), Pair("a", 1))
            val sorted: java.util.SortedMap<String, Int> = sortedMapOf()
            val sortedWithPairs: java.util.SortedMap<String, Int> = sortedMapOf(Pair("b", 2), Pair("a", 1))
            val sortedWithComparator: java.util.SortedMap<String, Int> = sortedMapOf(comparator)
            val sortedWithComparatorAndPairs: java.util.SortedMap<String, Int> = sortedMapOf(comparator, Pair("b", 2))
            val mutable: MutableMap<String, Int> = map.toMutableMap()
            val snapshot: Map<String, Int> = map.toMap()
            val sortedCopy: java.util.SortedMap<String, Int> = map.toSortedMap()
            val sortedCopyWithComparator: java.util.SortedMap<String, Int> = map.toSortedMap(comparator)
        }
        """#

        try withWorkspace { root in
            let declarations = try m22Build(
                root: root,
                sources: [("surface.kt", declarationsSource)],
                name: mode == .jvmJar ? "surface.jar" : "surface-classes",
                mode: mode
            )
            try #require(
                declarations.1 == 0,
                "Bundled declaration diagnostics: \(declarations.2.map { "\($0.code): \($0.message)" })"
            )

            let runtime = try m11Runtime()
            let app = try m22Build(
                root: root,
                sources: [("hello.kt", source)],
                name: mode == .jvmJar ? "app.jar" : "classes",
                mode: mode,
                classpath: runtime.components(separatedBy: ":")
            )
            try #require(app.1 == 0, "KSwiftK diagnostics: \(app.2.map { "\($0.code) @\($0.primaryRange?.start.offset ?? -1): \($0.message)" })")
            let candidate = try java(["-cp", app.0.path + ":" + runtime, "HelloKt"])
            #expect(candidate.stdout == expected)
            #expect(candidate.stderr.isEmpty)

            _ = try jvmTool("kotlinc", ["hello.kt", "-cp", runtime, "-d", "reference.jar"], root: root)
            let reference = try java(["-cp", root.appendingPathComponent("reference.jar").path + ":" + runtime, "HelloKt"])
            #expect(reference.stdout == expected)
            #expect(reference.stderr.isEmpty)
        }
    }
}
#endif
