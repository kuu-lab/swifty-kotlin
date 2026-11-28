#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func kotlinStringInternUsesJDKMethod(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            fun main() {
                val builder = StringBuilder()
                builder.append("he")
                builder.append("llo")
                val a = builder.toString()
                println(a.intern() === "hello")
                println("already".intern() === "already")
            }
            """, expected: "true\ntrue\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func kotlinStringInternCallableReferencesUseBundledRuntime(mode: EmitMode) throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let app = try m22Build(root: root, sources: [("hello.kt", """
            fun main() {
                val builder = StringBuilder()
                builder.append("he")
                builder.append("llo")
                val value = builder.toString()
                val unbound = String::intern
                println((unbound as kotlin.reflect.KFunction<*>).call(value) === "hello")
                val bound = value::intern
                println((bound as kotlin.reflect.KFunction<*>).call() === "hello")
            }
            """)], name: mode == .jvmJar ? "app.jar" : "classes", mode: mode, classpath: [library.path])
            try #require(app.1 == 0, "\(app.2.map(\.message))")
            let execution = try java(["-cp", app.0.path + ":" + library.path, "HelloKt"])
            #expect(execution.stdout == "true\ntrue\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
