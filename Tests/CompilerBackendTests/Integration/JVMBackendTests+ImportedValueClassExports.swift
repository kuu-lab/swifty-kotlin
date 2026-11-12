#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func kotlinConsumersLinkToExportsUsingImportedValueClasses() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let dependency = "package api\n@JvmInline value class ItemId(val value: String)"
            try dependency.write(to: root.appendingPathComponent("Dependency.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("dependency.jar")
            let compiled = try jvmTool("kotlinc", ["Dependency.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")

            let source = """
            package consumer
            import api.ItemId
            fun ItemId.label(): String = "item " + value
            fun echo(id: ItemId): ItemId = id
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Labels.kt", source)], name: "labels.jar", classpath: [library.path, stdlib.path])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let caller = """
            import api.ItemId
            import consumer.echo
            import consumer.label
            fun main() { println(echo(ItemId("24")).label()) }
            """
            try caller.write(to: root.appendingPathComponent("Caller.kt"), atomically: true, encoding: .utf8)
            let classpath = [app.path, library.path].joined(separator: ":")
            let compiledCaller = try jvmTool("kotlinc", ["Caller.kt", "-classpath", classpath, "-d", "caller.jar"], root: root)
            try #require(compiledCaller.exitCode == 0, "\(compiledCaller.stderr)")
            let run = try java(["-Xverify:all", "-cp", [root.appendingPathComponent("caller.jar").path, classpath, stdlib.path].joined(separator: ":"), "CallerKt"])
            #expect(run.stdout == "item 24\n")
        }
    }
}
#endif
