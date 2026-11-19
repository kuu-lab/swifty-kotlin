#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    /// `java.lang.ref.Reference<T>.get()` erases to `Object` in the classfile;
    /// the classpath stub must keep the class type variable so that
    /// `WeakReference<String>.get()` resolves to `String` (KUU-4612).
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func weakReferenceGetPreservesClassTypeArgument(mode: EmitMode) throws {
        try withWorkspace { root in
            let source = """
            import java.lang.ref.WeakReference

            fun main() {
                val typed: WeakReference<String> = WeakReference("typed")
                val value: String? = typed.get()
                println(value?.length)
                val payload = "hello"
                val inferred = WeakReference(payload)
                println(inferred.get()?.length)
                typed.clear()
                println(typed.get() == null)
            }
            """
            let result = try compile(source, root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }

            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let appArguments = mode == .jvmJar
                ? ["-jar", artifact.path]
                : ["-cp", artifact.path, "HelloKt"]
            let execution = try java(appArguments)
            #expect(execution.exitCode == 0, "\(execution.stderr)")
            #expect(execution.stdout == "5\n5\ntrue\n")
            #expect(execution.stderr.isEmpty)
        }
    }

    /// A bounded class type variable (`Box<T extends Number>`) erases to its
    /// bound in the descriptor, so the stub must keep the erased bound rather
    /// than the unbounded type parameter for parameter binding to match.
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func boundedClassTypeVariableKeepsErasedBinding(mode: EmitMode) throws {
        try withWorkspace { root in
            let javaSource = """
            package dep;
            public class Box<T extends Number> {
                private T value;
                public Box() {}
                public Box(T initial) { this.value = initial; }
                public void put(T value) { this.value = value; }
                public T get() { return value; }
            }
            """
            try javaSource.write(to: root.appendingPathComponent("Box.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["--release", "8", "-d", "deps", "Box.java"], root: root)
            _ = try jvmTool("jar", ["cf", "deps.jar", "-C", "deps", "."], root: root)
            let dependency = mode == .jvmJar
                ? root.appendingPathComponent("deps.jar").path
                : root.appendingPathComponent("deps").path
            let source = """
            import dep.Box

            fun main() {
                val b = Box<Int>()
                b.put(41)
                println(b.get())
                val c = Box<Int>(7)
                println(c.get())
            }
            """
            let result = try compile(source, root: root, mode: mode, classpath: [dependency])
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }

            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-cp", artifact + ":" + dependency, "HelloKt"])
            #expect(execution.exitCode == 0, "\(execution.stderr)")
            #expect(execution.stdout == "41\n7\n")
            #expect(execution.stderr.isEmpty)
        }
    }

    /// Methods inherited from a hidden parent keep the erased signature: the
    /// parent's type variables belong to a different scope than the child's,
    /// so copying the Signature attribute across the owner rewrite would
    /// resolve them against unrelated child type parameters.
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func hiddenParentTypeVariablesDoNotLeakIntoChildStub(mode: EmitMode) throws {
        try withWorkspace { root in
            let javaSource = """
            package dep;
            interface Hidden<T> { T read(); }
            public interface Visible<T> extends Hidden<String> {}
            """
            try javaSource.write(to: root.appendingPathComponent("Visible.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["--release", "8", "-d", "deps", "Visible.java"], root: root)
            _ = try jvmTool("jar", ["cf", "deps.jar", "-C", "deps", "."], root: root)
            let dependency = mode == .jvmJar
                ? root.appendingPathComponent("deps.jar").path
                : root.appendingPathComponent("deps").path
            let source = """
            import dep.Visible

            class Impl : Visible<Int> {
                override fun read(): Any = "hello"
            }

            fun main() {
                val v: Visible<Int> = Impl()
                println(v.read())
            }
            """
            let result = try compile(source, root: root, mode: mode, classpath: [dependency])
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }

            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-cp", artifact + ":" + dependency, "HelloKt"])
            #expect(execution.exitCode == 0, "\(execution.stderr)")
            #expect(execution.stdout == "hello\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
