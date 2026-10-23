#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    func m22Build(root: URL, sources: [(String, String)] = [], name: String, mode: EmitMode = .jvmJar, stdlib: Bool = false, classpath: [String] = []) throws -> (URL, Int, [Diagnostic]) {
        var inputs: [String] = []
        for (name, source) in sources {
            let path = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try source.write(to: path, atomically: true, encoding: .utf8)
            inputs.append(path.path)
        }
        let output = root.appendingPathComponent(name)
        let options = CompilerOptions(moduleName: "M22", inputs: inputs, outputPath: output.path, emit: mode, target: .hostDefault(), stdlibOnly: stdlib, jvmClasspath: classpath)
        let result = CompilerDriver(backendPhases: makeBackendPhases).runForTesting(options: options)
        return (output, result.exitCode, result.diagnostics)
    }

    /// KUU-3045: the bundled JVM stdlib must build after honoring inherited JDK collection members.
    @Test
    func m22JvmStdlibJarBuildsWithInheritedCollectionMembers() throws {
        try withWorkspace { root in
            let library = try m22Build(root: root, name: "kswiftk-stdlib.jar", stdlib: true)
            try #require(library.1 == 0, "\(library.2.map(\.message))")
            #expect(FileManager.default.fileExists(atPath: library.0.path))
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m22RepositoryStdlibWithoutOfficialRuntime(mode: EmitMode) throws {
        try withWorkspace { root in
            let library = try m22Build(root: root, name: "kswiftk-stdlib.jar", stdlib: true)
            try #require(library.1 == 0, "\(library.2.map(\.message))")
            let again = try m22Build(root: root, name: "again.jar", stdlib: true)
            try #require(again.1 == 0)
            #expect(try Data(contentsOf: library.0) == Data(contentsOf: again.0))
            let sources = [("app/Main.kt", #"""
            import support.greeting
            fun main() {
                println(greeting())
                val pair = Pair(1, "one")
                println(pair); println(pair.copy(second = "uno")); println(pair.component1()); println(pair == Pair(1, "one"))
                println(Pair(null, null).hashCode())
                println(listOf(1, 2, 3)); println(listOf<Int>()); println(setOf(3, 1, 3)); println(setOf<Int>())
                println(mapOf("a" to 1, "b" to 2, "a" to 3)); println(mapOf<String, Int>())
                val xs = mutableListOf(1, 2); xs.add(3); xs[0] = 4; println(xs); println(xs.removeAt(1))
                val ys = mutableSetOf(2, 2, 1); ys.add(3); ys.remove(2); println(ys)
                val zs = mutableMapOf("x" to 1); zs["y"] = 2; zs["x"] = 3; println(zs); println(zs.remove("x"))
                println(listOf(elements = arrayOf(8, 9))); println(setOf(*arrayOf(4, 4, 5)))
                println(mapOf(*arrayOf(Pair("z", 7), Pair("z", 8))))
                var total = 0; for (n in listOf(1, 2, 3)) total += n; println(total)
            }
            """#), ("support/Greeting.kt", "package support\nfun greeting(): String = \"Hello World\"\n")]
            let app = try m22Build(root: root, sources: sources, name: mode == .jvmJar ? "app.jar" : "classes", mode: mode, classpath: [library.0.path])
            try #require(app.1 == 0, "\(app.2.map(\.message))")
            // Only our two artifacts are on the runtime classpath.
            let execution = try java(["-cp", app.0.path + ":" + library.0.path, "MainKt"])
            #expect(execution.stdout == "Hello World\n(1, one)\n(1, uno)\n1\ntrue\n0\n[1, 2, 3]\n[]\n[3, 1]\n[]\n{a=3, b=2}\n{}\n[4, 2, 3]\n2\n[1, 3]\n{x=3, y=2}\n3\n[8, 9]\n[4, 5]\n{z=8}\n6\n")
            #expect(execution.stderr.isEmpty)
            let archive = try ZipArchive(data: Data(contentsOf: library.0))
            let names = Set(archive.entries.map(\.name))
            #expect(names.contains("kotlin/Pair.class"))
            #expect(names.contains("kotlin/PairKt.class"))
            #expect(names.contains("kotlin/collections/MapsKt.class"))
            #expect(names.contains("kotlin/kotlin.kotlin_builtins"))
            #expect(names.contains("kotlin/sequences/SequencesKt.class"))
            let provenance = try #require(archive.entries.first { $0.name == "META-INF/kswiftk-stdlib-sources.list" })
            #expect(String(decoding: try archive.contents(of: provenance), as: UTF8.self).contains("kotlin/Pair/Pair.kt\n"))
        }
    }

    @Test
    func m22JavaAndOfficialKotlinConsumersUseOnlyOwnStdlib() throws {
        try withWorkspace { root in
            let library = try m22Build(root: root, name: "kswiftk-stdlib.jar", stdlib: true)
            try #require(library.1 == 0, "\(library.2.map(\.message))")
            let source = #"""
            import kotlin.Pair;
            import kotlin.collections.*;
            public class JavaConsumer {
                static final class Key {
                    final int n;
                    Key(int n) { this.n = n; }
                    public int hashCode() { hashes++; return n; }
                    public boolean equals(Object o) { return o instanceof Key && ((Key)o).n == n; }
                    public String toString() { return "k" + n; }
                }
                static int hashes;
                public static void main(String[] args) throws Exception {
                    kotlin.io.ConsoleKt.println("Hello World");
                    Pair<Integer,String> p = new Pair<>(1, "one");
                    System.out.println(p); System.out.println(p.component1());
                    System.out.println(p.copy(2, "two"));
                    // This calls the existing common Kotlin source, not Pair's member copy.
                    System.out.println(kotlin.PairKt.copy(p, 3, "three"));
                    System.out.println(p.equals(new Pair<>(1, "one")));
                    System.out.println(p instanceof java.io.Serializable);
                    System.out.println(Pair.class.getAnnotation(kotlin.Metadata.class).k());
                    System.out.println(CollectionsKt.class.getAnnotation(kotlin.Metadata.class).k());
                    Integer[] elements = {1,2};
                    java.util.List<Integer> xs = CollectionsKt.listOf(elements);
                    elements[0] = 4; System.out.println(xs); xs.set(1,5); System.out.println(elements[1]);
                    System.out.println(CollectionsKt.class.getMethod("listOf", Object[].class).isVarArgs());
                    System.out.println(!CollectionsKt.class.getMethod("listOf", Object.class).isVarArgs());
                    Key key = new Key(1);
                    hashes=0; SetsKt.setOf(key); System.out.println(hashes);
                    hashes=0; SetsKt.setOf(new Key[]{key}); System.out.println(hashes);
                    hashes=0; MapsKt.mapOf(new Pair<>(key,1)); System.out.println(hashes);
                    hashes=0; MapsKt.mapOf(new Pair[]{new Pair<>(key,1)}); System.out.println(hashes);
                    System.out.println(MapsKt.mapOf(new Pair[]{new Pair<>("a",1),new Pair<>("b",2),new Pair<>("a",3)}));
                    System.out.println(new Pair<>(null,null).hashCode());
                }
            }
            """#
            try source.write(to: root.appendingPathComponent("JavaConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["--release", "8", "-cp", library.0.path, "JavaConsumer.java"], root: root)
            let execution = try java(["-cp", root.path + ":" + library.0.path, "JavaConsumer"])
            #expect(execution.stdout == "Hello World\n(1, one)\n1\n(2, two)\n(3, three)\ntrue\ntrue\n1\n2\n[4, 2]\n5\ntrue\ntrue\n0\n0\n0\n1\n{a=3, b=2}\n0\n")
            #expect(execution.stderr.isEmpty)
            let consumer = #"""
            fun main() {
                println("Hello World")
                val pair: Pair<Int, String> = 1 to "one"
                println(pair.copy(second = "uno")); val (n, word) = pair; println(n); println(word)
                val list: List<Int> = listOf(1, 2, 3)
                println(list.size); println(list[1]); println(list.isEmpty())
                val set: Set<Int> = setOf(3, 1, 3); println(set.size); println(set.contains(1))
                val map: Map<String, Int> = mapOf("a" to 1, "b" to 2, "a" to 3)
                println(map.size); println(map["a"]); println("a" in map)
                val unknown: Any? = list; println((unknown as List<Int>)[0])
                val mutable: MutableList<Int> = mutableListOf(1, 2); mutable.add(3); mutable[0] = 4; println(mutable)
                val mutableSet = mutableSetOf(1, 1); mutableSet.add(2); println(mutableSet)
                val mutableMap = mutableMapOf("a" to 1); mutableMap["b"] = 2; println(mutableMap)
                for (value in list) println(value + 1)
                val values = JavaConsumer.values()
                println(listOf(*values)); println(setOf(elements = values))
                println(emptyList<Int>()); println(emptySet<Int>()); println(emptyMap<String, Int>())
                val numbers: Pair<Double?, Float?> = Pair(1.0, 2.0f)
                println(numbers.first == 1.0); println(1.0 == numbers.first); println(numbers.first == numbers.first)
                println(numbers.second == 2.0f); println(2.0f == numbers.second); println(numbers.second == numbers.second)
                val absent: Pair<Double?, Float?> = Pair(null, null)
                println(absent.first == 1.0); println(absent.second == 2.0f); println(absent.first == absent.first)
            }
            """#
            let helper = "public class JavaConsumer { public static Integer[] values() { return new Integer[]{7,8}; } }"
            try helper.write(to: root.appendingPathComponent("JavaConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["--release", "8", "JavaConsumer.java"], root: root)
            try consumer.write(to: root.appendingPathComponent("Consumer.kt"), atomically: true, encoding: .utf8)
            // Disable both implicit compiler distribution dependencies explicitly.
            _ = try jvmTool("kotlinc", ["-no-stdlib", "-no-reflect", "-cp", library.0.path + ":" + root.path, "Consumer.kt", "-d", "consumer.jar"], root: root)
            let kotlin = try java(["-cp", root.appendingPathComponent("consumer.jar").path + ":" + library.0.path + ":" + root.path, "ConsumerKt"])
            #expect(kotlin.stdout == "Hello World\n(1, uno)\n1\none\n3\n2\nfalse\n2\ntrue\n2\n3\ntrue\n1\n[4, 2, 3]\n[1, 2]\n{a=1, b=2}\n2\n3\n4\n[7, 8]\n[7, 8]\n[]\n[]\n{}\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\nfalse\nfalse\ntrue\n")
            #expect(kotlin.stderr.isEmpty)
            // A fresh compiler process must require our own built-in resources.
            let archive = try ZipArchive(data: Data(contentsOf: library.0))
            let primary = try #require(archive.entries.first { $0.name == "kotlin/PairKt.class" })
            let remaining = try archive.entries.filter { $0.name != primary.name && $0.name != "META-INF/MANIFEST.MF" && !$0.name.hasSuffix(".kotlin_builtins") }.map { ($0.name, Data(try archive.contents(of: $0))) }
            let missing = root.appendingPathComponent("without-builtins.jar")
            try JVMJarArchive.emit(className: "kotlin/PairKt", classFile: Data(try archive.contents(of: primary)), hasMain: false, classes: remaining).write(to: missing)
            do {
                _ = try jvmTool("kotlinc", ["-no-stdlib", "-no-reflect", "-cp", missing.path + ":" + root.path, "Consumer.kt", "-d", "invalid.jar"], root: root)
                Issue.record("Kotlin consumer unexpectedly resolved built-ins without our resources.")
            } catch let CommandRunnerError.nonZeroExit(result) {
                #expect(result.stderr.contains("built-in declaration"))
            }

        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m22MultipleSourcesResolveBeforeEmission(mode: EmitMode) throws {
        try withWorkspace { root in
            let sources = [("Main.kt", #"""
            import first.*
            import second.*
            fun main() { println(compute()); println(label); println(Owner().value()); println(sum(1, 2, 3)); println(items("a", "b")); println(callback()()); println(nested(arrayOf(8, 9))); println("sum=".suffixed(2, 3)); println(Owner().first(9)) }
            """#), ("First.kt", #"""
            package first
            import second.answer
            val label = "multiple sources"
            fun compute(): Int = answer() + 1
            class Owner { fun value(): Int = compute(); fun first(vararg values: Int): Int = values[0] }
            fun sum(vararg values: Int): Int { var total = 0; for (n in values) total += n; return total }
            fun <T> items(vararg values: T): T = values[1]
            fun callback(): () -> Int = { answer() }
            fun nested(vararg values: Array<Int>): Int = values[0][1]
            fun String.suffixed(vararg values: Int): String { var n = 0; for (value in values) n += value; return this + n }
            """#), ("Second.kt", "package second\nfun answer(): Int = 41\n")]
            let output = try m22Build(root: root, sources: sources, name: mode == .jvmJar ? "multi.jar" : "classes", mode: mode)
            try #require(output.1 == 0, "\(output.2.map(\.message))")
            let execution = try java(["-cp", output.0.path, "MainKt"])
            #expect(execution.stdout == "42\nmultiple sources\n42\n6\nb\n41\n9\nsum=5\n9\n")
            #expect(execution.stderr.isEmpty)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m22InvalidSecondarySourcesPreserveOutput(mode: EmitMode) throws {
        try withWorkspace { root in
            for (index, sources) in [
                [("Main.kt", "fun main() {}"), ("Other.kt", "fun bad() { synchronized(Any()) {} }")],
                [("a/Shared.kt", "fun a() = 1"), ("b/Shared.kt", "fun b() = 2")],
                [("Main.kt", "fun main() {}"), ("Other.kt", "package other\nfun main() {}")],
            ].enumerated() {
                let name = "out\(index)"
                let path = root.appendingPathComponent(name)
                let marker = mode == .jvmJar ? path : path.appendingPathComponent("marker")
                if mode == .jvmClass { try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true) }
                try Data("keep".utf8).write(to: marker)
                let output = try m22Build(root: root, sources: sources, name: name, mode: mode)
                #expect(output.1 != 0)
                #expect(!output.2.isEmpty)
                #expect(try Data(contentsOf: marker) == Data("keep".utf8))
                if mode == .jvmClass { #expect(try FileManager.default.contentsOfDirectory(atPath: path.path) == ["marker"]) }
            }
        }
    }
}
#endif
