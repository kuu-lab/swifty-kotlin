#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func safePropertyAssignmentSkipsRightHandSideForNull() throws {
        try withWorkspace { root in
            let source = """
            class Item(var text: String)
            class Outer(val item: Item?)
            fun value(): String { println("rhs"); return "set" }
            fun outer(item: Item?): Outer { println("receiver"); return Outer(item) }
            fun write(item: Item?) { outer(item).item?.text = value() }
            fun main() {
                write(null)
                val item = Item("start")
                write(item)
                println(item.text)
            }
            """
            let (app, status, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar")
            try #require(status == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path, "MainKt"])
            #expect(run.stdout == "receiver\nreceiver\nrhs\nset\n")
        }
    }
}
#endif
