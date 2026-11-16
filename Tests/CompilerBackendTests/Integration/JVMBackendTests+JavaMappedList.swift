#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func javaListSubinterfacesShareKotlinListNominal() throws {
        try withWorkspace { root in
            try """
            package fixture;
            public interface Items<T> extends java.util.List<T> {}
            """.write(to: root.appendingPathComponent("Items.java"), atomically: true, encoding: .utf8)
            try """
            package fixture;
            public final class Strings extends java.util.AbstractList<String> implements Items<String> {
                public int size() { return 1; }
                public String get(int index) { return "ok"; }
                public static Items<String> value() { return new Strings(); }
            }
            """.write(to: root.appendingPathComponent("Strings.java"), atomically: true, encoding: .utf8)
            let classes = root.appendingPathComponent("classes").path
            let javac = try jvmTool("javac", ["--release", "8", "-d", classes, "Items.java", "Strings.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            let (app, status, diagnostics) = try m22Build(
                root: root,
                sources: [("Main.kt", """
                import fixture.Items
                import fixture.Strings
                import java.util.*
                fun first(items: Items<String>): String = items[0]
                fun asList(items: Items<String>): List<String> = items
                fun main() {
                    val items = Strings.value()
                    println(first(items))
                    println(asList(items)[0])
                }
                """)],
                name: "app.jar", classpath: [classes]
            )
            try #require(status == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + classes, "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "ok\nok\n")
        }
    }
}
#endif
