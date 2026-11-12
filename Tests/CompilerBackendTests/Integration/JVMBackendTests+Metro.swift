#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func metroCallsLinkGeneratedGraphsAndRequireArtifacts() throws {
        try withWorkspace { root in
            let sources = [
                "DependencyGraph.java": """
                package dev.zacsweers.metro;
                import java.lang.annotation.Retention;
                import java.lang.annotation.RetentionPolicy;
                @Retention(RetentionPolicy.RUNTIME)
                public @interface DependencyGraph {
                    @Retention(RetentionPolicy.RUNTIME)
                    @interface Factory {}
                }
                """,
                "CreateGraphKt.java": """
                package dev.zacsweers.metro;
                public final class CreateGraphKt {
                    public static <T> T createGraph() { throw new AssertionError(); }
                    public static <T> T createGraphFactory() { throw new AssertionError(); }
                }
                """,
                "MetroImplMarker.java": """
                package dev.zacsweers.metro.internal;
                import java.lang.annotation.Retention;
                import java.lang.annotation.RetentionPolicy;
                @Retention(RetentionPolicy.RUNTIME)
                public @interface MetroImplMarker {}
                """,
                "GraphFactoryInvokeFunctionMarker.java": """
                package dev.zacsweers.metro.internal;
                import java.lang.annotation.Retention;
                import java.lang.annotation.RetentionPolicy;
                @Retention(RetentionPolicy.RUNTIME)
                public @interface GraphFactoryInvokeFunctionMarker {}
                """,
                "Graph.java": """
                package example;
                import dev.zacsweers.metro.DependencyGraph;
                import dev.zacsweers.metro.internal.GraphFactoryInvokeFunctionMarker;
                import dev.zacsweers.metro.internal.MetroImplMarker;
                @DependencyGraph
                public interface Graph {
                    Companion Companion = new Companion();
                    String getMessage();
                    @DependencyGraph.Factory
                    interface Maker {
                        Graph make(String message);
                        @MetroImplMarker
                        final class Impl implements Maker {
                            public static final Impl INSTANCE = new Impl();
                            public Graph make(String message) { return () -> message; }
                        }
                    }
                    @DependencyGraph.Factory
                    interface Missing {}
                    final class Companion implements Maker {
                        @GraphFactoryInvokeFunctionMarker
                        public Graph invoke() { return () -> "graph"; }
                        @GraphFactoryInvokeFunctionMarker
                        public Graph make(String message) { return () -> message; }
                    }
                }
                """,
            ]
            for (filename, source) in sources {
                try source.write(to: root.appendingPathComponent(filename), atomically: true, encoding: .utf8)
            }
            let dependencies = try jvmTool(
                "javac", ["--release", "8", "-d", "dependencies"] + sources.keys.sorted(), root: root
            )
            try #require(dependencies.exitCode == 0, "\(dependencies.stderr)")
            let classpath = root.appendingPathComponent("dependencies").path
            let compiled = try compile("""
            import dev.zacsweers.metro.createGraph
            import dev.zacsweers.metro.createGraphFactory as factory
            import example.Graph

            fun main() {
                val maker: Graph.Maker = factory()
                println(maker.make("factory").message)
                println(createGraph<Graph>().message)
            }
            """, root: root, mode: .jvmJar, classpath: [classpath])
            try #require(compiled.0 == 0, "\(compiled.1.map(\.message))")
            let app = root.appendingPathComponent("hello.jar").path
            let execution = try java(["-Xverify:all", "-cp", app + ":" + classpath, "HelloKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "factory\ngraph\n")
            #expect(execution.stderr.isEmpty)

            let rejected = try compile("""
            import dev.zacsweers.metro.createGraphFactory
            import example.Graph

            fun main() {
                createGraphFactory<Graph.Missing>()
            }
            """, root: root, mode: .jvmJar, classpath: [classpath])
            #expect(rejected.0 != 0)
            #expect(rejected.1.contains {
                $0.code == "KSWIFTK-JVM-0001" && $0.message.contains("requires a concrete type and its Metro-generated JVM artifact")
            })
        }
    }
}
#endif
