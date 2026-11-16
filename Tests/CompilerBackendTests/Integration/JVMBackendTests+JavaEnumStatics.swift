#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedJavaEnumUsesPhysicalValuesAndValueOf() throws {
        try withWorkspace { root in
            try """
            package fixture;
            enum Topic { NONE, HARDWARE }
            """.write(to: root.appendingPathComponent("Topic.java"), atomically: true, encoding: .utf8)
            let classes = root.appendingPathComponent("classes").path
            let javac = try jvmTool("javac", ["--release", "8", "-d", classes, "Topic.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            let (app, status, diagnostics) = try m22Build(
                root: root,
                sources: [("Main.kt", """
                package fixture
                fun main() {
                    println(Topic.values().size)
                    println(Topic.valueOf("HARDWARE") == Topic.HARDWARE)
                    println(Topic.values()[0] == Topic.NONE)
                }
                """)],
                name: "app.jar", classpath: [classes]
            )
            try #require(status == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + classes, "fixture.MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "2\ntrue\ntrue\n")
        }
    }
}
#endif
