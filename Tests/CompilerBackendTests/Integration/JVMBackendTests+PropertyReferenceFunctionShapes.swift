#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func propertyReferencesMatchStructuralFunctionArguments() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = "package fixture\nclass Slot(val isLive: Boolean)"
            try provider.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("provider.jar")
            let compiled = try jvmTool("kotlinc", ["Provider.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [library.path, own.path]
            let source = """
            import fixture.Slot
            class Local(val isLive: Boolean)
            fun main() {
                println(listOf(Slot(false), Slot(true)).any(Slot::isLive))
                println(listOf(Local(false)).any(Local::isLive))
                val bound: () -> Boolean = Local(true)::isLive
                println(bound())
                val property: kotlin.reflect.KProperty1<Slot, Boolean> = Slot::isLive
                println(property.get(Slot(true)))
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "true\nfalse\ntrue\ntrue\n")
        }
    }
}
#endif
