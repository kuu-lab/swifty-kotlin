#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedInfixMemberKeepsOwnerTypeParameter() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            package fixture
            class Provided<T>(val value: T)
            class Local<T> {
                infix fun provides(value: T): Provided<T> = Provided(value)
                fun providePlain(value: String): String = value
            }
            fun local(): Local<String> = Local()
            fun read(value: Provided<String>): String = value.value
            """
            try provider.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("provider.jar")
            let compiled = try jvmTool("kotlinc", ["Provider.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [library.path, own.path]
            let source = """
            import fixture.*
            fun main() { println(read(local() provides "DroidKaigi")) }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "DroidKaigi\n")

            let rejected = """
            import fixture.local
            fun reject() { local() providePlain "DroidKaigi" }
            """
            let (_, rejectExit, errors) = try m22Build(root: root, sources: [("Reject.kt", rejected)], name: "reject.jar", classpath: classpath)
            #expect(rejectExit == 1)
            #expect(errors.filter { $0.severity == .error }.map(\.code) == ["KSWIFTK-SEMA-0307"])
        }
    }
}
#endif
