#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func javaPackageMembersKeepJvmPackageAccess() throws {
        try withWorkspace { root in
            try """
            package fixture;
            public class Counter {
                int value;
                int increment(int step) { return value += step; }
            }
            """.write(to: root.appendingPathComponent("Counter.java"), atomically: true, encoding: .utf8)
            let classes = root.appendingPathComponent("classes").path
            let javac = try jvmTool("javac", ["--release", "8", "-d", classes, "Counter.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            let samePackage = """
            package fixture
            fun main() {
                val counter = Counter()
                counter.value = 3
                println(counter.increment(2))
                println(counter.value)
            }
            """
            let (app, status, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", samePackage)], name: "app.jar", classpath: [classes]
            )
            try #require(status == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + classes, "fixture.MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "5\n5\n")
            let (_, invalid, _) = try m22Build(
                root: root,
                sources: [
                    ("Marker.kt", "package fixture\nclass Marker"),
                    ("Wrong.kt", "package consumer\nimport fixture.Counter\nfun main() { Counter().increment(1) }"),
                ],
                name: "wrong.jar", classpath: [classes]
            )
            #expect(invalid != 0)
        }
    }
}
#endif
