#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func bundledStdlibCollectionAggregates(mode: EmitMode) throws {
        try withWorkspace { root in
            let runtime = try m11Runtime().components(separatedBy: ":")[0]
            let source = #"""
            fun main() {
                val values: Iterable<Int> = listOf(3, 1, 2)
                println(values.maxOrNull())
                println(values.minOrNull())
                println(values.count { it > 1 })
                val collection: Collection<Int> = listOf(3, 1, 2)
                println(collection.maxOrNull())
                println(collection.minOrNull())
                println(collection.count { it > 1 })
                println(emptyList<Int>().maxOrNull())
                println(emptyList<Int>().minOrNull())
                println(listOf("pear", "apple").maxOrNull())
                println(listOf("pear", "apple").minOrNull())
                println(listOf(3.5, 1.25).maxOrNull())
                println(listOf(3.5, 1.25).minOrNull())
                println(listOf(3.5f, 1.25f).maxOrNull())
                println(listOf(3.5f, 1.25f).minOrNull())
            }
            """#
            let compiled = try compile(source, root: root, mode: mode, classpath: [runtime])
            try #require(compiled.0 == 0, "\(compiled.1.map(\.message))")
            let app = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let candidate = try java(["-cp", app + ":" + runtime, "HelloKt"])

            _ = try jvmTool("kotlinc", ["hello.kt", "-cp", runtime, "-d", "reference.jar"], root: root)
            let reference = try java(["-cp", root.appendingPathComponent("reference.jar").path + ":" + runtime, "HelloKt"])
            #expect(candidate.stdout == reference.stdout)
            #expect(candidate.stderr.isEmpty)
        }
    }
}
#endif
