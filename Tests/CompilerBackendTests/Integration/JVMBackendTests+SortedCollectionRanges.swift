#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m22SortedCollectionRangeMethods(mode: EmitMode) throws {
        let source = #"""
        fun main() {
            val set: java.util.SortedSet<Int> = java.util.TreeSet<Int>()
            set.add(1)
            set.add(2)
            set.add(4)
            set.add(6)
            val subset = set.subSet(2, 5)
            println(subset.headSet(5))
            println(subset.tailSet(2))
            try {
                subset.subSet(1, 3)
                println("nested set range accepted")
            } catch (error: IllegalArgumentException) {
                println("nested set range rejected")
            }
            println(set.headSet(4))
            println(set.tailSet(4))
            println(subset)
            set.add(3)
            println(subset)
            subset.remove(3)
            println(set)
            try {
                subset.add(5)
                println("out-of-range set add accepted")
            } catch (error: IllegalArgumentException) {
                println("out-of-range set add rejected")
            }
            try {
                set.subSet(5, 2)
                println("invalid set range accepted")
            } catch (error: IllegalArgumentException) {
                println("invalid set range rejected")
            }

            val map: java.util.SortedMap<Int, String> = sortedMapOf(1 to "a", 2 to "b", 4 to "d", 6 to "f")
            println(map.headMap(4))
            println(map.tailMap(4))
            val subMap = map.subMap(2, 5)
            println(subMap.subMap(2, 5))
            try {
                subMap.subMap(1, 3)
                println("nested map range accepted")
            } catch (error: IllegalArgumentException) {
                println("nested map range rejected")
            }
            println(subMap)
            map.put(3, "c")
            println(subMap)
            subMap.remove(3)
            println(map)
            try {
                subMap.put(5, "e")
                println("out-of-range map put accepted")
            } catch (error: IllegalArgumentException) {
                println("out-of-range map put rejected")
            }
            try {
                map.subMap(5, 2)
                println("invalid map range accepted")
            } catch (error: IllegalArgumentException) {
                println("invalid map range rejected")
            }
        }
        """#
        let expected = "[2, 4]\n[2, 4]\nnested set range rejected\n[1, 2]\n[4, 6]\n[2, 4]\n[2, 3, 4]\n[1, 2, 4, 6]\nout-of-range set add rejected\ninvalid set range rejected\n{1=a, 2=b}\n{4=d, 6=f}\n{2=b, 4=d}\nnested map range rejected\n{2=b, 4=d}\n{2=b, 3=c, 4=d}\n{1=a, 2=b, 4=d, 6=f}\nout-of-range map put rejected\ninvalid map range rejected\n"

        try withWorkspace { root in
            let runtime = try m11Runtime()
            let app = try m22Build(
                root: root,
                sources: [("SortedRanges.kt", source)],
                name: mode == .jvmJar ? "sorted-ranges.jar" : "sorted-ranges-classes",
                mode: mode,
                classpath: runtime.components(separatedBy: ":")
            )
            try #require(
                app.1 == 0,
                "KSwiftK diagnostics: \(app.2.map { "\($0.code) @\($0.primaryRange?.start.offset ?? -1): \($0.message)" })"
            )
            let candidate = try java(["-cp", app.0.path + ":" + runtime, "SortedRangesKt"])
            #expect(candidate.stdout == expected)
            #expect(candidate.stderr.isEmpty)

            _ = try jvmTool("kotlinc", ["SortedRanges.kt", "-cp", runtime, "-d", "reference.jar"], root: root)
            let reference = try java(["-cp", root.appendingPathComponent("reference.jar").path + ":" + runtime, "SortedRangesKt"])
            #expect(reference.stdout == expected)
            #expect(reference.stderr.isEmpty)
        }
    }
}
#endif
