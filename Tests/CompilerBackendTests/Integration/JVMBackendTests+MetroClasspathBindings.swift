#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func metroGraphResolvesQualifiedClasspathBindingsAndCachesPerGraph() throws {
        try withWorkspace { root in
            let annotations: [String: String] = [
                "DependencyGraph": """
                Class<?> scope();
                @Retention(RetentionPolicy.RUNTIME) @interface Factory {}
                """,
                "Provides": "",
                "Inject": "",
                "Qualifier": "",
                "SingleIn": "Class<?> scope();",
                "ContributesTo": "Class<?> scope(); Class<?>[] replaces() default {};",
                "ContributesBinding": "Class<?> scope(); Class<?>[] replaces() default {};",
                "ContributesIntoSet": "Class<?> scope(); Class<?>[] replaces() default {};",
                "Binds": "",
                "IntoSet": "",
                "Origin": "Class<?> value();",
                "GraphExtension": """
                Class<?> scope();
                @Retention(RetentionPolicy.RUNTIME) @interface Factory {}
                """,
            ]
            var files: [String] = []
            for (name, body) in annotations.sorted(by: { $0.key < $1.key }) {
                let path = name + ".java"
                try """
                package dev.zacsweers.metro;
                import java.lang.annotation.Retention;
                import java.lang.annotation.RetentionPolicy;
                @Retention(RetentionPolicy.RUNTIME)
                public @interface \(name) { \(body) }
                """.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)
                files.append(path)
            }
            let fixtures = [
                "CreateGraphKt.java": """
                package dev.zacsweers.metro;
                public final class CreateGraphKt {
                    public static <T> T createGraphFactory() { throw new AssertionError(); }
                }
                """,
                "MetroContribution.java": """
                package dev.zacsweers.metro.internal;
                import java.lang.annotation.*;
                @Retention(RetentionPolicy.RUNTIME)
                public @interface MetroContribution { Class<?> scope(); }
                """,
                "Library.java": """
                package fixture;
                import dev.zacsweers.metro.*;
                import dev.zacsweers.metro.internal.MetroContribution;
                import java.lang.annotation.*;
                public final class Library {
                    public static final class Scope {}
                    public static final class ChildScope {}
                    public static final class ScreenScope {}
                    @Qualifier @Retention(RetentionPolicy.RUNTIME) public @interface Qualified {}
                    @ContributesTo(scope=Scope.class)
                    public interface Providers {
                        @Provides @Qualified
                        default String qualified(String input) { return input + "!"; }
                        @Provides
                        default int size(java.util.Set<? extends Message> messages) { return messages.size(); }
                    }
                    public interface Message { String text(); }
                    @GraphExtension(scope=ChildScope.class)
                    public interface Child {
                        Message message();
                        Screen.Factory screens();
                    }
                    @GraphExtension(scope=ScreenScope.class)
                    public interface Screen {
                        long number();
                        Message message();
                        @GraphExtension.Factory @ContributesTo(scope=ChildScope.class)
                        interface Factory { Screen open(@Provides long number); }
                    }
                    @Inject @SingleIn(scope=Scope.class) @ContributesBinding(scope=Scope.class) @ContributesIntoSet(scope=Scope.class)
                    public static final class Implementation implements Message {
                        private final String text;
                        public Implementation(@Qualified String text) { this.text = text; }
                        public String text() { return text; }
                        @MetroContribution(scope=Scope.class) @Origin(Implementation.class)
                        public interface Contribution {
                            abstract class BindsMirror {
                                @Binds public abstract Message bind(Implementation value);
                                @Binds @IntoSet public abstract Message intoSet(Implementation value);
                            }
                        }
                    }
                }
                """,
            ]
            for (path, source) in fixtures.sorted(by: { $0.key < $1.key }) {
                try source.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)
                files.append(path)
            }
            let dependency = try jvmTool("javac", ["--release", "8", "-d", "deps"] + files, root: root)
            try #require(dependency.exitCode == 0, "\(dependency.stderr)")
            let classpath = root.appendingPathComponent("deps").path
            let source = """
            import dev.zacsweers.metro.*
            import fixture.Library
            @DependencyGraph(scope = Library.Scope::class)
            interface Graph {
                val message: Library.Message
                val implementation: Library.Implementation
                val count: Int
                val child: Library.Child
                @DependencyGraph.Factory
                interface Factory { fun create(@Provides input: String): Graph }
            }
            fun main() {
                val factory = createGraphFactory<Graph.Factory>()
                val first = factory.create("first")
                val second = factory.create("second")
                println(first.message.text())
                println(second.message.text())
                println(first.message === first.implementation)
                println(first.message === second.message)
                println(first.count)
                val child = first.child
                val screen = child.screens().open(19L)
                println(screen.number())
                println(screen.message() === first.message && child.message() === first.message)
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [classpath])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-cp", app.path + ":" + classpath, "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "first!\nsecond!\ntrue\nfalse\n1\n19\ntrue\n")
        }
    }
}
#endif
