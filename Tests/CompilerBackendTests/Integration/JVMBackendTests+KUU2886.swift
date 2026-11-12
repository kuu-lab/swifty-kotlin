#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func kuu2886VarargCanAppearAlongsideOtherParameters(mode: EmitMode) throws {
        try withWorkspace { root in
            let source = #"""
            fun f(x: Int, vararg rest: String) = "$x:${rest.size}"
            fun g(vararg xs: Int, last: Int) = xs.size + last
            fun main() {
                println(f(1, "a", "b"))
                println(f(1, *arrayOf("c", "d")))
                println(f(1))
                println(g(1, 2, last = 3))
                println(g(last = 4))
            }
            """#
            let result = try compile(source, root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            let execution = try java(mode == .jvmJar
                ? ["-jar", root.appendingPathComponent("hello.jar").path]
                : ["-cp", root.appendingPathComponent("classes").path, "HelloKt"])
            #expect(execution.stdout == "1:2\n1:2\n1:0\n5\n4\n")
            #expect(execution.stderr.isEmpty)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func kuu4543VarargAccVarargsFlagMatchesPhysicalLastParameter(mode: EmitMode) throws {
        try withWorkspace { root in
            let result = try compile(#"""
            fun trailing(vararg values: Int, last: Int): Int = values.size + last
            fun terminal(x: Int, vararg values: String): Int = values.size + x
            fun main() {}
            """#, root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")

            let artifact = mode == .jvmJar
                ? root.appendingPathComponent("hello.jar").path
                : root.appendingPathComponent("classes").path
            let consumer = root.appendingPathComponent("JavaConsumer.java")
            let consumerClasses = root.appendingPathComponent("consumer")
            try FileManager.default.createDirectory(at: consumerClasses, withIntermediateDirectories: true)
            try """
            public class JavaConsumer {
                public static void main(String[] args) {
                    System.out.println(HelloKt.trailing(new int[] {1, 2}, 3));
                    System.out.println(HelloKt.terminal(4, "a", "b"));
                }
            }
            """.write(to: consumer, atomically: true, encoding: .utf8)
            let compilation = try javac(["--release", "8", "-cp", artifact, "-d", consumerClasses.path, consumer.path])
            #expect(compilation.exitCode == 0, "\(compilation.stderr)")
            let execution = try java(["-cp", consumerClasses.path + ":" + artifact, "JavaConsumer"])
            #expect(execution.stdout == "5\n6\n")
            #expect(execution.stderr.isEmpty)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func kuu4543SuspendVarargOmitsAccVarargs(mode: EmitMode) throws {
        try withWorkspace { root in
            let result = try compile("suspend fun collect(vararg values: Int): Int = values.size\nfun main() {}", root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            let artifact = mode == .jvmJar
                ? root.appendingPathComponent("hello.jar").path
                : root.appendingPathComponent("classes").path
            let description = try javap(["-v", "-classpath", artifact, "HelloKt"])
            #expect(description.stdout.contains("collect"))
            #expect(description.stdout.contains("kotlin.coroutines.Continuation"))
            #expect(!description.stdout.contains("ACC_VARARGS"))
        }
    }
}
#endif
