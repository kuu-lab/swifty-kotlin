#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func implicitJavaClassUsesTheActiveReceiver() throws {
        try withWorkspace { root in
            let source = """
            class Inspector {
                fun direct() = javaClass.simpleName
                fun sameClass() = javaClass == this.javaClass
                fun String.extension() = javaClass.simpleName
                fun wrapped() = "text".extension()
                fun shadowed(): String {
                    val javaClass = "local"
                    return javaClass
                }
            }
            fun main() {
                val inspector = Inspector()
                println(inspector.direct())
                println(inspector.sameClass())
                println(inspector.wrapped())
                println(inspector.shadowed())
            }
            """
            let (app, status, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar")
            try #require(status == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path, "MainKt"])
            #expect(run.stdout == "Inspector\ntrue\nString\nlocal\n")
        }
    }
}
#endif
