#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func arrayAsIterableLinksAgainstOwnStdlibAndReadsLiveArrayValues() throws {
        let own = try ownStdlibLibrary()
        let official = try m11Runtime()
        try withWorkspace { root in
            let source = """
            fun main() {
                val array = arrayOf<String?>("first", null)
                val iterable = array.asIterable()
                println(iterable is List<*>)
                println(iterable.joinToString(","))
                val iterator = iterable.iterator()
                array[0] = "updated"
                println(iterator.next())
                println(iterable.joinToString(","))
                println(emptyArray<String>().asIterable().iterator().hasNext())
            }
            """
            try source.write(to: root.appendingPathComponent("IterableProbe.kt"), atomically: true, encoding: .utf8)
            let artifact = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", ["IterableProbe.kt", "-d", artifact.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let reference = try java(["-Xverify:all", "-cp", artifact.path + ":" + official, "IterableProbeKt"])
            try #require(reference.exitCode == 0, "\(reference.stderr)")
            let precompiled = try java(["-Xverify:all", "-cp", artifact.path + ":" + own.path, "IterableProbeKt"])
            #expect(precompiled.stdout == reference.stdout)

            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("IterableProbe.kt", source)], name: "candidate.jar", classpath: [own.path])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let candidate = try java(["-Xverify:all", "-cp", app.path + ":" + own.path, "IterableProbeKt"])
            #expect(candidate.stdout == reference.stdout)
        }
    }
}
#endif
