#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func directlyCompiledSealedClassImportRetainsWhenExhaustiveness() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            package fixture
            sealed class Plan {
                object Free : Plan()
                object Paid : Plan()
            }
            """
            let (dependency, providerExit, providerDiagnostics) = try m22Build(
                root: root, sources: [("Provider.kt", provider)], name: "dependency.jar", classpath: [stdlib.path]
            )
            try #require(providerExit == 0, "\(providerDiagnostics.map(\.message))")
            let consumer = """
            import fixture.Plan
            fun render(plan: Plan): String = when (plan) {
                Plan.Free -> "free"
                Plan.Paid -> "paid"
            }
            fun main() { println(render(Plan.Paid)) }
            """
            let classpath = [dependency.path, stdlib.path]
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Consumer.kt", consumer)], name: "app.jar", classpath: classpath
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "ConsumerKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "paid\n")
        }
    }
}
#endif
