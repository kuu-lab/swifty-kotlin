#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func concurrentHashMapSupportsMutableMapViewsAndIndexedAccess(mode: EmitMode) throws {
        try withWorkspace { root in
            let library = try ownStdlibRuntime()
            let source = """
            import java.util.concurrent.ConcurrentHashMap

            fun main() {
                val m = ConcurrentHashMap<String, String>()
                m["empty"] = ""
                m["value"] = "x"
                val removed = m.values.removeAll { it.isEmpty() }
                m["k"] = "v"
                println(removed)
                println(m.values.size)
                println(m["empty"])
                println(m["k"])
                println(m.keys.contains("value"))
                println(m.keys.contains("k"))
                println(m.keys.remove("k"))
                println(m.size)
                println(m.entries.size)
                println(m["k"])
            }
            """
            let result = try compile(source, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")

            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-cp", artifact + ":" + library.path, "HelloKt"])
            #expect(execution.stdout == "true\n2\nnull\nv\ntrue\ntrue\ntrue\n1\n1\nnull\n")
            #expect(execution.stderr.isEmpty)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func concurrentHashMapIndexedReadPreservesValueType(mode: EmitMode) throws {
        try withWorkspace { root in
            let library = try ownStdlibRuntime()
            let source = """
            import java.lang.ref.WeakReference
            import java.util.concurrent.ConcurrentHashMap

            fun readString(map: ConcurrentHashMap<String, String>, token: String): String? = map[token]
            fun readInt(map: ConcurrentHashMap<String, Int>, token: String): Int? = map[token]
            fun readWeak(map: ConcurrentHashMap<String, WeakReference<String>>, token: String): String? = map[token]?.get()

            fun main() {
                val m = ConcurrentHashMap<String, String>()
                m["a"] = "x"
                println(readString(m, "a"))
                println(readString(m, "missing"))
                val n = ConcurrentHashMap<String, Int>()
                n["a"] = 42
                println(readInt(n, "a"))
                println(readInt(n, "missing"))
                val refs = ConcurrentHashMap<String, WeakReference<String>>()
                refs["r"] = WeakReference("weak")
                println(readWeak(refs, "r"))
                println(readWeak(refs, "missing"))
            }
            """
            let result = try compile(source, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")

            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-cp", artifact + ":" + library.path, "HelloKt"])
            #expect(execution.stdout == "x\nnull\n42\nnull\nweak\nnull\n")
            #expect(execution.stderr.isEmpty)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func mutableCollectionRemoveAllPredicateKeepsEqualNonMatchingElements(mode: EmitMode) throws {
        try withWorkspace { root in
            let library = try ownStdlibRuntime()
            let source = """
            fun main() {
                val xs: MutableCollection<Int> = mutableListOf(1, 1)
                var seen = 0
                val changed = xs.removeAll { ++seen == 1 }
                println(changed)
                println(xs.size)
                println(xs.contains(1))
            }
            """
            let result = try compile(source, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")

            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-cp", artifact + ":" + library.path, "HelloKt"])
            #expect(execution.stdout == "true\n1\ntrue\n")
            #expect(execution.stderr.isEmpty)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func concurrentMapCustomGetKeepsJavaSignature(mode: EmitMode) throws {
        try withWorkspace { root in
            let library = try ownStdlibRuntime()
            try """
            package dep;
            public class WeirdMap<K, V> extends java.util.concurrent.ConcurrentHashMap<K, V> {
                public int get(int key) { return key * 2; }
            }
            """.write(to: root.appendingPathComponent("WeirdMap.java"), atomically: true, encoding: .utf8)
            let dependency = root.appendingPathComponent("dependency").path
            let compiled = try jvmTool("javac", ["--release", "8", "-d", dependency, "WeirdMap.java"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let dependencyJar = root.appendingPathComponent("dependency.jar").path
            _ = try jvmTool("jar", ["cf", dependencyJar, "-C", dependency, "."], root: root)

            let source = """
            import dep.WeirdMap

            fun main() {
                val m = WeirdMap<String, String>()
                val index: Int = m.get(21)
                println(index)
            }
            """
            let classpath = [library.path, dependencyJar]
            let result = try compile(source, root: root, mode: mode, classpath: classpath)
            try #require(result.0 == 0, "\(result.1.map(\.message))")

            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-cp", ([artifact] + classpath).joined(separator: ":"), "HelloKt"])
            #expect(execution.stdout == "42\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
