#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func javaGenericArrayAndFieldRetainElementTypes() throws {
        try withWorkspace { root in
            try """
            package fixture;
            import java.lang.reflect.Array;
            import java.util.Collections;
            import java.util.List;
            public class Lookup<T> {
                public final T binding;
                public final List<Item> items = Collections.singletonList(new Item());
                public Lookup(T binding) { this.binding = binding; }
                public static class Item {
                    public String label() { return "item"; }
                }
                public static Lookup<Item> create() { return new Lookup<>(new Item()); }
                public <U> U[] spans(Class<U> klass, U value) {
                    U[] result = (U[]) Array.newInstance(klass, 1);
                    result[0] = value;
                    return result;
                }
            }
            """.write(to: root.appendingPathComponent("Lookup.java"), atomically: true, encoding: .utf8)
            let classes = root.appendingPathComponent("classes").path
            let javac = try jvmTool("javac", ["--release", "8", "-d", classes, "Lookup.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            let source = """
            import fixture.Lookup
            fun main() {
                val holder = Lookup.create()
                println(holder.binding.label())
                println(holder.items[0].label())
                val spans = holder.spans(String::class.java, "span")
                val item: String = spans[0]
                println(item)
            }
            """
            let stdlib = try ownStdlibLibrary()
            let classpath = [classes, stdlib.path]
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "item\nitem\nspan\n")
        }
    }
}
#endif
