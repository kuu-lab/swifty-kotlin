#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func elvisOnNonNullPrimitiveSkipsFallback() throws {
        try withWorkspace { root in
            let source = """
            fun left(): Boolean { println("left"); return true }
            fun right(): Boolean { println("right"); return false }
            fun maybe(value: Boolean?): Boolean = value ?: right()
            fun main() {
                println(left() ?: right())
                println(maybe(null))
                println(maybe(true))
            }
            """
            let (app, status, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar")
            try #require(status == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path, "MainKt"])
            #expect(run.stdout == "left\ntrue\nright\nfalse\ntrue\n")
        }
    }
}
#endif
