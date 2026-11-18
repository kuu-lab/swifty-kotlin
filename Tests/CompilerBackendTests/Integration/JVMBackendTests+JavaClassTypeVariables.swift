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
}
#endif
