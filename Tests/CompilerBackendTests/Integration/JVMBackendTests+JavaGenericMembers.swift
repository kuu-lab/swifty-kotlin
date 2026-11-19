#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func javaGenericMemberReturnAndSamPreserveTypeArguments() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            package fixture;
            public final class Tasks {
                public interface Listener<T> { void accept(T value); }
                public static final class Task<T> {
                    private final T value;
                    public Task(T value) { this.value = value; }
                    public void listen(Listener<? super T> receiver) { receiver.accept(value); }
                }
                public static final class Item { public String getTitle() { return "resolved"; } }
                public static Task<Item> task() { return new Task<>(new Item()); }
                public static String choose(boolean flag) { return "primitive"; }
                public static String choose(Boolean flag) { return flag == null ? "nullable" : "boxed"; }
            }
            """.write(to: root.appendingPathComponent("Tasks.java"), atomically: true, encoding: .utf8)
            let dependency = root.appendingPathComponent("dependency").path
            let compiled = try jvmTool("javac", ["--release", "8", "-d", dependency, "Tasks.java"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [dependency, library.path]
            let source = """
            import fixture.Tasks
            fun main() = Tasks.task().listen { item -> println(item.title) }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let result = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "resolved\n")
        }
    }
}
#endif
