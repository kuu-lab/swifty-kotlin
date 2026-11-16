#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func concreteJavaMapDefaultUsesItsKotlinExtensionContract() throws {
        try withWorkspace { root in
            let source = """
            import java.util.HashMap
            fun main() {
                val map = HashMap<Int, String>()
                map.put(1, "stored")
                println(map.getOrElse(1, { "unexpected" }))
                println(map.getOrElse(2, { "missing" }))
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar")
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path, "MainKt"])
            #expect(run.stdout == "stored\nmissing\n")
        }
    }
}
#endif
