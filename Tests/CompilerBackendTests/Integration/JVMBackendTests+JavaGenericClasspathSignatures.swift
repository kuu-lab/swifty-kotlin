#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func javaGenericClasspathSignaturesPreserveSamBoundsAndRawTypes() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            package fixture;
            import java.util.Collections;
            import java.util.Map;
            import java.util.concurrent.Callable;

            public final class Contracts {
                public static final Map<String, String> IDS = Collections.singletonMap("name", "value");
                public static <T extends Number> T from(Callable<? extends T> factory) throws Exception {
                    return factory.call();
                }
                public interface Publisher<T> {}
                public static class Flow<T> implements Publisher<T> {
                    public static <T> Flow<T> of(T value) { return new Flow<T>(); }
                    public static <T> Flow<T> defer(Callable<? extends Publisher<? extends T>> factory) throws Exception {
                        factory.call();
                        return new Flow<T>();
                    }
                }
                public static class Frame {}
                public static class Item<T> {
                    public boolean same(Item other) { return false; }
                }
                public static class RefinedItem extends Item<Frame> {}
            }
            """.write(to: root.appendingPathComponent("Contracts.java"), atomically: true, encoding: .utf8)
            let dependency = root.appendingPathComponent("dependency").path
            let javac = try jvmTool("javac", ["--release", "8", "-d", dependency, "Contracts.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            let classpath = [dependency, stdlib.path]
            let source = """
            import fixture.Contracts
            import fixture.Contracts.Flow

            class Item : Contracts.RefinedItem() {
                override fun same(other: Contracts.Item<*>): Boolean = true
            }

            fun main() {
                val ids: Map<String, String> = Contracts.IDS
                println(ids["name"])
                val number: Int = Contracts.from { 42 }
                println(number)
                val flow: Flow<String> = Flow.defer { Flow.of("one") }
                println(flow != null)
                println(Item().same(Contracts.Item<String>()))
            }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "value\n42\ntrue\ntrue\n")

            let rejected = """
            import fixture.Contracts
            fun invalid() = Contracts.from<String> { "no" }
            """
            let (_, failure, errors) = try m22Build(
                root: root, sources: [("Reject.kt", rejected)], name: "reject.jar", classpath: classpath
            )
            #expect(failure != 0)
            #expect(errors.contains { $0.severity == .error })
        }
    }
}
#endif
