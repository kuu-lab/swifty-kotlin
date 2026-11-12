#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedPrimitiveComposeStateUsesUnboxedAccessors() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let compose = try composeJVMFixture(root, stdlib: own)
            let provider = """
            package androidx.compose.runtime
            interface MutableState<T> { var value: T }
            interface MutableFloatState : MutableState<Float> {
                var floatValue: Float
                override var value: Float
                    get() = floatValue
                    set(value) { floatValue = value }
            }
            private class State(override var floatValue: Float) : MutableFloatState
            fun create(value: Float): MutableFloatState = State(value)
            """
            try provider.write(to: root.appendingPathComponent("State.kt"), atomically: true, encoding: .utf8)
            try """
            package androidx.compose.runtime
            interface SnapshotMutationPolicy<T>
            fun <T> mutableStateOf(value: T, policy: SnapshotMutationPolicy<T>? = null): MutableState<T> =
                object : MutableState<T> { override var value: T = value }
            """.write(to: root.appendingPathComponent("SnapshotState.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("state.jar")
            let compiled = try jvmTool("kotlinc", ["State.kt", "SnapshotState.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [library.path, compose.path, own.path]
            let source = """
            import androidx.compose.runtime.create
            fun main() {
                val state = create(2.0f)
                state.floatValue += 0.5f
                println(state.floatValue)
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "2.5\n")
        }
    }
}
#endif
