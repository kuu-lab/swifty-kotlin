#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedExtensionsPreserveOperatorAndInfixModifiers() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            package fixture
            import kotlin.reflect.KProperty

            class State<T>(val value: T)
            class Plain
            fun state(): State<String> = State("ready")
            operator fun <T> State<T>.getValue(receiver: Any?, property: KProperty<*>): T = value
            fun Plain.getValue(receiver: Any?, property: KProperty<*>): String = "plain"
            infix fun <T> State<T>.append(suffix: String): String = value.toString() + suffix
            fun <T> State<T>.appendPlain(suffix: String): String = value.toString() + suffix
            """
            try provider.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("provider.jar")
            let compiled = try jvmTool("kotlinc", ["Provider.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [library.path, own.path]
            let appSource = """
            import fixture.*
            fun main() {
                val state = state()
                val value by state
                println(value.length)
                println(state append "!")
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", appSource)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "5\nready!\n")

            let rejected = """
            import fixture.*
            fun reject() {
                val value by Plain()
                println(state() appendPlain "!")
            }
            """
            let (_, rejectExit, errors) = try m22Build(root: root, sources: [("Reject.kt", rejected)], name: "reject.jar", classpath: classpath)
            #expect(rejectExit == 1)
            #expect(errors.filter { $0.severity == .error }.map(\.code).sorted() == ["KSWIFTK-SEMA-0103", "KSWIFTK-SEMA-0307"])
        }
    }
}
#endif
