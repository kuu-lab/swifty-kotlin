#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func jvmParameterSuppressDoesNotRequireAnAnnotationClass() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            @Target(AnnotationTarget.VALUE_PARAMETER)
            @Retention(AnnotationRetention.RUNTIME)
            annotation class Keep

            fun greet(@Suppress("UNUSED_PARAMETER") ignored: String, @Keep name: String): String = "Hello " + name

            fun main() {
                println(greet("unused", "DroidKaigi"))
            }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [stdlib.path]
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let classpath = app.path + ":" + stdlib.path
            let bytecode = try javap(["-v", "-classpath", classpath, "MainKt"])
            #expect(bytecode.stdout.contains("RuntimeVisibleParameterAnnotations:"))
            #expect(bytecode.stdout.contains("LKeep;"))
            #expect(!bytecode.stdout.contains("Lkotlin/Suppress;"))
            let run = try java(["-Xverify:all", "-cp", classpath, "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "Hello DroidKaigi\n")
        }
    }
}
#endif
