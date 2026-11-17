#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func receiverBuilderInfersEmptyInitializerAfterSelectingOverloadByArguments() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            class Holder<T>(var value: T)
            fun <T> initial(): List<T> = emptyList()
            fun <T> buildState(initialValue: T, block: Holder<T>.() -> Unit): T = Holder(initialValue).apply(block).value
            fun <T> buildState(initialValue: T, key: String, block: Holder<T>.() -> Unit): T = Holder(initialValue).apply(block).value
            fun main() {
                val result = buildState(initialValue = initial(), key = "window") { value = listOf("feature") }
                println(result)
            }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [library.path]
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let result = try java(["-Xverify:all", "-cp", app.path + ":" + library.path, "MainKt"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "[feature]\n")
        }
    }
}
#endif
