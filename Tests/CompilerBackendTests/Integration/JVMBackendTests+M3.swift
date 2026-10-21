#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    func jvmTool(_ name: String, _ arguments: [String], root: URL) throws -> CommandResult {
        try CommandRunner.run(executable: CommandRunner.resolveExecutable(name, fallback: "/usr/bin/" + name), arguments: arguments, currentDirectoryPath: root.path, timeout: 60)
    }
    func javaFixture(_ root: URL) throws -> URL {
        let sources = [
            "Named": #"public interface Named { String name(); default int number() { return 9; } default long scale(long x, double n) { return x + (long)n; } static String tag() { return "named"; } }"#,
            "Counter": """
            public class Counter implements Named {
                private int value;
                public Counter(int start) { value = start; }
                public int add(int amount) { value += amount; return value; }
                public String name() { return "counter"; }
                public String toString() { return "Counter"; }
                public static int twice(int x) { return x * 2; }
                public static long twice(long x) { return x * 3; }
                public static Counter create(int x) { return new Counter(x); }
                public static Named named() { return new Counter(0); }
                public static String echo(String x) { return x; }
                public static String absent() { return null; }
                public static Object object(Object x) { return x; }
                private static int hidden() { return 7; }
                public static int array(int[] x) { return x.length; }
            }
            """,
            "Child": "public class Child extends Counter { public Child() { super(5); } }",
            "Init": """
            public class Init {
                static { System.out.println("init"); }
                public Init(int x) { System.out.println(x); }
                public Init(Init other) { System.out.println("nested"); }
                public String toString() { return "Init"; }
            }
            """,
            "Closed": "public class Closed { private Closed() {} }",
        ]
        for (name, source) in sources {
            try ("package dep;\n" + source).write(to: root.appendingPathComponent(name + ".java"), atomically: true, encoding: .utf8)
        }
        _ = try jvmTool("javac", ["--release", "8", "-d", "deps"] + sources.keys.sorted().map { $0 + ".java" }, root: root)
        _ = try jvmTool("jar", ["cf", "deps.jar", "-C", "deps", "."], root: root)
        return root.appendingPathComponent("deps.jar")
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func importsJavaConstructorsMethodsAndInterfaces(mode: EmitMode) throws {
        try withWorkspace { root in
            let dependency = try javaFixture(root)
            let source = """
            import dep.Counter as C
            import dep.Named
            import dep.Child
            fun main() {
                val c: C = C(10)
                println(c.add(3))
                println(C.twice(5))
                println(C.twice(5L))
                println(C.create(2).add(4))
                val n: Named = C.named()
                println(n.name())
                println(n.number())
                println(n.scale(4L, 2.0))
                println(Named.tag())
                println(C.echo("hello"))
                println(C.absent() == null)
                println(C.`object`(42))
                println(C.`object`(null))
                println(c.toString())
                val child = Child()
                println(child.add(2))
                println(child.equals(child))
                println(Child.twice(3))
            }
            """
            // Exercise both compressed JAR input and a directory of classfiles.
            let classpath = mode == .jvmJar ? dependency.path : root.appendingPathComponent("deps").path
            let result = try compile(source, root: root, mode: mode, classpath: [classpath])
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }
            let output = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let run = try java(["-cp", output + ":" + dependency.path, "HelloKt"])
            #expect(run.stdout == "13\n10\n15\n6\ncounter\n9\n6\nnamed\nhello\ntrue\n42\nnull\nCounter\n7\ntrue\n6\n")
        }
    }

    @Test
    func constructorAllocationPrecedesArgumentsAndKeepsVerifierFrames() throws {
        try withWorkspace { root in
            let dependency = try javaFixture(root)
            let result = try compile("""
            import dep.Init
            fun argument(): Int { println("arg"); return 7 }
            fun main() {
                val first = Init(if (true) argument() else 2)
                val nested = Init(Init(if (false) 1 else 3))
                println(first.toString())
                println(nested.toString())
                var i = 0
                while (i < 2) {
                    i++
                    Init(if (i == 1) continue else i)
                }
                while (i < 3) {
                    i++
                    Init(if (i == 3) break else i)
                }
                println(i)
                val loopArgument = Init(if (true) {
                    var j = 0
                    while (j < 2) { j++; if (j == 1) continue; break }
                    j
                } else 0)
                println(loopArgument.toString())
                var outer = 0
                while (outer < 2) {
                    var count = 0
                    do { count++ } while (if (count == 1) break else true)
                    println(count)
                    outer++
                }
            }
            """, root: root, mode: .jvmJar, classpath: [dependency.path])
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }
            let run = try java(["-cp", root.appendingPathComponent("hello.jar").path + ":" + dependency.path, "HelloKt"])
            #expect(run.stdout == "init\narg\n7\n3\nnested\nInit\nInit\n2\n3\n2\nInit\n1\n1\n")
        }
    }

    @Test
    func libraryJarIsCallableFromJavaAndOfficialKotlin() throws {
        try withWorkspace { root in
            let dependency = try javaFixture(root)
            let result = try compile("""
            package api
            import dep.Counter
            fun add(left: Int, right: Int): Int = left + right
            fun echo(text: String): String = text
            fun maybe(text: String?): String? = text
            fun platform() = Counter.echo("platform")
            fun box(number: Int): Any = number
            fun counter(): Counter = Counter(5)
            internal fun hidden(): Int = 20
            private fun secret(): Int = 30
            fun composed(`é`: Int): Int = `é`
            fun decomposed(`e\u{0301}`: Int): Int = `e\u{0301}`
            """, root: root, mode: .jvmJar, classpath: [dependency.path])
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }
            let jar = root.appendingPathComponent("hello.jar")
            let archive = try ZipArchive(data: Data(contentsOf: jar))
            #expect(archive.entries.contains { $0.name == "META-INF/JVMTest.kotlin_module" })
            let manifest = try #require(archive.entries.first { $0.name == "META-INF/MANIFEST.MF" })
            #expect(!String(decoding: try archive.contents(of: manifest), as: UTF8.self).contains("Main-Class"))
            try """
            public class JavaConsumer {
                public static void main(String[] args) {
                    System.out.println(api.HelloKt.add(20, 22));
                    System.out.println(api.HelloKt.echo("Java"));
                    System.out.println(api.HelloKt.maybe(null));
                    System.out.println(api.HelloKt.counter().add(1));
                    try { api.HelloKt.echo(null); throw new AssertionError("missing null check"); }
                    catch (NullPointerException expected) { System.out.println("null checked"); }
                }
            }
            """.write(to: root.appendingPathComponent("JavaConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", jar.path + ":" + dependency.path, "JavaConsumer.java"], root: root)
            let javaRun = try java(["-cp", root.path + ":" + jar.path + ":" + dependency.path, "JavaConsumer"])
            #expect(javaRun.stdout == "42\nJava\nnull\n6\nnull checked\n")
            try """
            import api.add
            import api.echo
            import api.maybe
            import api.platform
            import api.box
            import api.counter
            import api.composed
            import api.decomposed
            fun main() {
                println(add(right = 20, left = 22))
                println(echo(text = "Kotlin"))
                println(maybe(null))
                val nonNull: String = platform()
                println(nonNull)
                println(box(42))
                println(counter().add(1))
                println(composed(`é` = 1))
                println(decomposed(`e\u{0301}` = 2))
            }
            """.write(to: root.appendingPathComponent("Consumer.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["Consumer.kt", "-cp", jar.path + ":" + dependency.path, "-include-runtime", "-d", "consumer.jar"], root: root)
            let kotlinRun = try java(["-cp", root.appendingPathComponent("consumer.jar").path + ":" + jar.path + ":" + dependency.path, "ConsumerKt"])
            #expect(kotlinRun.stdout == "42\nKotlin\nnull\nplatform\n42\n6\n1\n2\n")
            for inaccessible in ["hidden", "secret"] {
                try "import api.\(inaccessible)\nfun use() = \(inaccessible)()".write(to: root.appendingPathComponent("Bad.kt"), atomically: true, encoding: .utf8)
                do {
                    _ = try jvmTool("kotlinc", ["Bad.kt", "-cp", jar.path, "-d", "bad.jar"], root: root)
                    Issue.record("Kotlin accessed \(inaccessible)")
                } catch CommandRunnerError.nonZeroExit(let error) {
                    #expect(error.stderr.lowercased().contains("cannot access"), "\(error.stderr)")
                }
            }
        }
    }

    @Test
    func importsOfficialKotlinClassAndGeneratedFacade() throws {
        try withWorkspace { root in
            try "package dep\nclass Multiplier(val factor: Int) { fun multiply(value: Int): Int = factor * value }".write(to: root.appendingPathComponent("Multiplier.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["Multiplier.kt", "-d", "kotlin-dep.jar"], root: root)
            #expect(try compile("package api\nfun plus(x: Int): Int = x + 1", root: root, mode: .jvmJar).0 == 0)
            let producer = root.appendingPathComponent("producer.jar")
            try FileManager.default.copyItem(at: root.appendingPathComponent("hello.jar"), to: producer)
            let dependency = root.appendingPathComponent("kotlin-dep.jar")
            let result = try compile("""
            import dep.Multiplier
            import api.HelloKt
            fun main() { println(HelloKt.plus(Multiplier(6).multiply(7))) }
            """, root: root, mode: .jvmJar, classpath: [producer.path, dependency.path])
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }
            let run = try java(["-cp", root.appendingPathComponent("hello.jar").path + ":" + producer.path + ":" + dependency.path, "HelloKt"])
            #expect(run.stdout == "43\n")
        }
    }

    @Test(arguments: ["import dep.Counter\nfun main() { Counter.hidden() }", "import dep.Closed\nfun main() { Closed() }", "import dep.Counter\nfun main() { Counter.array(1) }", "import dep.Counter\nfun main() { Counter.create(0).twice(1) }", "fun nil() = null", "fun onlyNull(x: Nothing?): Int = 1"])
    func rejectsUnsupportedForeignMembers(source: String) throws {
        try withWorkspace { root in
            let dependency = try javaFixture(root)
            let result = try compile(source, root: root, mode: .jvmJar, classpath: [dependency.path])
            #expect(result.0 == 1)
            #expect(!result.1.contains { $0.code.hasPrefix("KSWIFTK-ICE") })
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("hello.jar").path))
        }
    }

    @Test
    func platformNullFailsAtNonNullBoundary() throws {
        try withWorkspace { root in
            let dependency = try javaFixture(root)
            let result = try compile("import dep.Counter\nfun main() { val text: String = Counter.absent(); println(text) }", root: root, mode: .jvmJar, classpath: [dependency.path])
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }
            do {
                _ = try java(["-cp", root.appendingPathComponent("hello.jar").path + ":" + dependency.path, "HelloKt"])
                Issue.record("Missing platform null assertion")
            } catch CommandRunnerError.nonZeroExit(let error) {
                #expect(error.stderr.contains("NullPointerException"))
                #expect(!error.stderr.contains("VerifyError"))
            }
        }
    }

    @Test
    func classpathOrderPreservesShadowingByInaccessibleClasses() throws {
        try withWorkspace { root in
            let source = root.appendingPathComponent("Version.java")
            try "package dep; public class Version { public static int number() { return 1; } }".write(to: source, atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["--release", "8", "-d", "public", source.path], root: root)
            try "package dep; class Version { public static int number() { return 2; } }".write(to: source, atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["--release", "8", "-d", "hidden", source.path], root: root)
            let first = root.appendingPathComponent("public").path, hidden = root.appendingPathComponent("hidden").path
            let visible = try JVMClasspathIndex.load([first, hidden])
            #expect(visible.classes["dep/Version"] != nil)
            let shadowed = try JVMClasspathIndex.load([hidden, first])
            #expect(shadowed.classes["dep/Version"] == nil)
        }
    }

    @Test
    func rejectsMissingOrMalformedClasspathWithoutReplacingOutput() throws {
        try withWorkspace { root in
            let output = root.appendingPathComponent("hello.jar")
            let sentinel = Data("previous".utf8)
            let broken = root.appendingPathComponent("broken/dep")
            try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
            try Data([0xCA, 0xFE, 0xBA, 0xBE]).write(to: broken.appendingPathComponent("Bad.class"))
            for name in ["missing.jar", "malformed.jar", "broken"] {
                try sentinel.write(to: output)
                if name == "malformed.jar" { try sentinel.write(to: root.appendingPathComponent(name)) }
                let result = try compile("fun main() {}", root: root, mode: .jvmJar, classpath: [root.appendingPathComponent(name).path])
                #expect(result.0 == 1)
                #expect(result.1.contains { $0.code == "KSWIFTK-JVM-0003" })
                #expect(try Data(contentsOf: output) == sentinel)
            }
        }
    }
}
#endif
