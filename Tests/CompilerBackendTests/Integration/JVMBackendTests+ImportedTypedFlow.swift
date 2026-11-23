#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedFlowMemberAndSuspendSamKeepTheirTypeArguments() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let flow = """
            package kotlinx.coroutines.flow
            fun interface FlowCollector<in T> { suspend fun emit(value: T) }
            interface Flow<out T> { suspend fun collect(collector: FlowCollector<T>) }
            """
            let model = """
            package fixture
            import kotlinx.coroutines.flow.Flow
            import kotlinx.coroutines.flow.FlowCollector
            data class Entry(val title: String)
            class Provider {
                fun results(): Flow<Entry> = object : Flow<Entry> {
                    override suspend fun collect(collector: FlowCollector<Entry>) = collector.emit(Entry("flow"))
                }
            }
            """
            try flow.write(to: root.appendingPathComponent("Flow.kt"), atomically: true, encoding: .utf8)
            try model.write(to: root.appendingPathComponent("Model.kt"), atomically: true, encoding: .utf8)
            let dependency = root.appendingPathComponent("dependency.jar").path
            let compiled = try jvmTool("kotlinc", ["Flow.kt", "Model.kt", "-d", dependency], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [dependency, library.path]
            let source = """
            import fixture.Provider
            suspend fun main() {
                Provider().results().collect { entry -> println(entry.title) }
            }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let result = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "flow\n")
        }
    }
}
#endif
