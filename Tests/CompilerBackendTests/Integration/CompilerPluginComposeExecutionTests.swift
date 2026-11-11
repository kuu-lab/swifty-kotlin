@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite(.serialized)
struct CompilerPluginComposeExecutionTests {

    @Test
    func composeComposerParameterPropagatesAtRuntime() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let runtimeSource = """
        package androidx.compose.runtime

        @Target(
            AnnotationTarget.FUNCTION,
            AnnotationTarget.TYPE,
            AnnotationTarget.TYPE_PARAMETER,
            AnnotationTarget.PROPERTY,
            AnnotationTarget.PROPERTY_GETTER
        )
        annotation class Composable

        @Target(AnnotationTarget.CLASS)
        annotation class Stable

        interface Composer {
            fun record(tag: String)
        }

        val currentComposer: Composer?
            @Composable get() = null
        """

        let mainSource = """
        package com.example

        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.Composer
        import androidx.compose.runtime.Stable
        import androidx.compose.runtime.currentComposer

        @Stable
        class FakeComposer : Composer {
            val events = mutableListOf<String>()
            override fun record(tag: String) {
                events.add(tag)
            }
        }

        @Composable
        fun Leaf(label: String) {
            currentComposer?.record("leaf:" + label)
        }

        @Composable
        inline fun Container(content: @Composable () -> Unit) {
            currentComposer?.record("enter")
            content()
            currentComposer?.record("exit")
        }

        @Composable
        fun Screen(name: String) {
            Container {
                Leaf(name)
            }
        }

        @Suppress("COMPOSABLE_INVOCATION")
        fun render(composer: Composer) {
            Screen("Compose")
        }

        fun main() {
            val composer = FakeComposer()
            render(composer)
            for (event in composer.events) {
                println(event)
            }
        }
        """

        let rtPath = directory.appendingPathComponent("compose_runtime.kt").path
        let mainPath = directory.appendingPathComponent("main.kt").path
        let outputPath = directory.appendingPathComponent("compose_exec_out").path
        try runtimeSource.write(toFile: rtPath, atomically: true, encoding: .utf8)
        try mainSource.write(toFile: mainPath, atomically: true, encoding: .utf8)

        let options = CompilerOptions(
            moduleName: "ComposeExec",
            inputs: [rtPath, mainPath],
            outputPath: outputPath,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: .O0,
            includeStdlib: false,
            stdlibLibraryPath: try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: true
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))

        let result = try CommandRunner.run(executable: outputPath, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == "enter\nleaf:Compose\nexit\n")
    }
}
