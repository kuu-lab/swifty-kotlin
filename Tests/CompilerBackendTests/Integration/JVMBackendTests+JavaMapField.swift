#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func javaMapFieldAcceptsReadOnlyAssignmentAndKeepsMutableReads() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            package fixture;
            public class Store {
                public java.util.Map<String, Integer> entries = new java.util.LinkedHashMap<>();
            }
            """.write(to: root.appendingPathComponent("Store.java"), atomically: true, encoding: .utf8)
            let classes = root.appendingPathComponent("classes").path
            let javac = try jvmTool("javac", ["--release", "8", "-d", classes, "Store.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            let (app, status, diagnostics) = try m22Build(
                root: root,
                sources: [("Main.kt", """
                import fixture.Store
                fun main() {
                    val store = Store()
                    val assigned: Map<String, Int> = mutableMapOf()
                    store.entries = assigned
                    store.entries.put("one", 1)
                    println(assigned["one"])
                }
                """)],
                name: "app.jar", classpath: [own.path, classes]
            )
            try #require(status == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + own.path + ":" + classes, "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "1\n")
        }
    }
}
#endif
