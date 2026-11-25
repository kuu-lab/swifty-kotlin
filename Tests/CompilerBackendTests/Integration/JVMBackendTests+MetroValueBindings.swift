#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func metroUsesLogicalValueClassKeysAcrossImportedGraphExtension() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let metro = """
            package dev.zacsweers.metro
            import kotlin.reflect.KClass
            annotation class DependencyGraph(val scope: KClass<*>) { annotation class Factory }
            annotation class GraphExtension(val scope: KClass<*>) { annotation class Factory }
            annotation class Provides
            annotation class ContributesTo(val scope: KClass<*>)
            annotation class Inject
            inline fun <reified T : Any> createGraphFactory(): T = error("intrinsic")
            """
            let provider = """
            package fixture
            import dev.zacsweers.metro.*
            @JvmInline value class Input(val text: String)
            @JvmInline value class Tag(val text: String)
            interface AppScope
            interface ScreenScope
            @GraphExtension(ScreenScope::class)
            interface Screen {
                val message: Message
                @Provides fun tag(): Tag = Tag("tag")
                @GraphExtension.Factory @ContributesTo(AppScope::class)
                interface Factory {
                    fun open(@Provides value: Input): Screen
                }
            }
            @Inject class Message(val input: Input, val tag: Tag, val raw: String) {
                fun render(): String = input.text + ":" + tag.text + ":" + raw
            }
            """
            try metro.write(to: root.appendingPathComponent("CreateGraph.kt"), atomically: true, encoding: .utf8)
            try provider.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let dependency = root.appendingPathComponent("dependency.jar")
            let compiled = try jvmTool("kotlinc", ["-jvm-target", "17", "CreateGraph.kt", "Provider.kt", "-d", dependency.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let source = """
            import dev.zacsweers.metro.*
            import fixture.*
            @DependencyGraph(AppScope::class)
            interface Graph {
                val screens: Screen.Factory
                @DependencyGraph.Factory
                interface Factory { fun create(@Provides raw: String): Graph }
            }
            fun main() {
                val graph = createGraphFactory<Graph.Factory>().create("root")
                println(graph.screens.open(Input("first")).message.render())
                println(graph.screens.open(Input("second")).message.render())
            }
            """
            let classpath = [dependency.path, stdlib.path]
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "first:tag:root\nsecond:tag:root\n")
        }
    }
}
#endif
