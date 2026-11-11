#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: ["composeCollectionABI", "coroutineInterceptionABI", "mutablePropertyReferenceABI"])
    func precompiledComposeRuntimeContractsUseRepositoryStdlib(_ name: String) throws {
        let library = try ownStdlibLibrary()
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/JVMOwnStdlib/\(name).kt")
        try withWorkspace { root in
            let artifact = root.appendingPathComponent("app.jar")
            _ = try jvmTool("kotlinc", ["-no-reflect", "-Xjdk-release=8", "-jvm-default=disable", fixture.path, "-d", artifact.path], root: root)
            let facade = name.prefix(1).uppercased() + name.dropFirst() + "Kt"
            let result = try java(["-Xverify:all", "-cp", artifact.path + ":" + library.path, facade])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "ok\n")
        }
    }

    @Test
    func repositoryDequeIsAvailableToJVMSource() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
                fun main() {
                    val queue = ArrayDeque<String>()
                    queue.addLast("right")
                    queue.addFirst("left")
                    val list: MutableList<String> = queue
                    println(queue.removeFirst())
                    println(list.removeAt(0))
                }
                """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Deque.kt", source)], name: "app.jar", classpath: [library.path])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let result = try java(["-Xverify:all", "-cp", app.path + ":" + library.path, "DequeKt"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "left\nright\n")
        }
    }
}
#endif
