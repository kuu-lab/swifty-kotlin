#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func booleanNotMemberMatchesUnaryNot() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            data class Row(val visible: Boolean)
            class Custom { fun not(): String = "custom" }
            fun negate(value: Boolean?): Boolean? = value?.not()
            fun main() {
                println(Row(false).visible.not())
                println(Row(true).visible.not())
                println(negate(true))
                println(negate(null))
                println(Custom().not())
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [own.path])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", [app.path, own.path].joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "true\nfalse\nfalse\nnull\ncustom\n")
        }
    }
}
#endif
