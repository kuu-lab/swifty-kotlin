#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func jvmConstructorOptInDoesNotRequireAnAnnotationClass() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            @RequiresOptIn
            annotation class ExperimentalThing
            @ExperimentalThing fun marker() = "opted-in"
            class Carrier @OptIn(ExperimentalThing::class) constructor() {
                val value = "opted-in"
            }
            fun main() { println(Carrier().value) }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [library.path]
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let bytecode = try javap(["-v", "-classpath", app.path, "Carrier"])
            #expect(!bytecode.stdout.contains("Lkotlin/OptIn;"))
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + library.path, "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "opted-in\n")
        }
    }
}
#endif
