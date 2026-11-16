#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func javaGenericOverloadsContextualizeEmptyCollectionFactories() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            package fixture;
            public class Tools {
                public static <T> T copy(T value) { return value; }
                public static <T> T copy(Class<T> token) { return null; }
            }
            """.write(to: root.appendingPathComponent("Tools.java"), atomically: true, encoding: .utf8)
            let classes = root.appendingPathComponent("classes").path
            let result = try jvmTool("javac", ["--release", "8", "-d", classes, "Tools.java"], root: root)
            try #require(result.exitCode == 0, "\(result.stderr)")
            let (app, status, diagnostics) = try m22Build(
                root: root,
                sources: [("Main.kt", """
                import fixture.Tools.*
                fun main() {
                    val map: Map<Int, String> = copy(mutableMapOf())
                    val list: List<String> = copy(listOf())
                    val type: String? = copy(String::class.java)
                    println(map.size)
                    println(list.size)
                    println(type)
                }
                """)],
                name: "app.jar", classpath: [own.path, classes]
            )
            try #require(status == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + own.path + ":" + classes, "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "0\n0\nnull\n")
        }
    }
}
#endif
