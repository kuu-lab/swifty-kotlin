#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func javaTimeInstantSatisfiesComparableBound() throws {
        try withWorkspace { root in
            let source = """
            class Box<T : Comparable<T>?>(val v: T?)
            fun main() {
                val b = Box(java.time.Instant.now())
                println(b.v)
            }
            """
            let (exitCode, diagnostics) = try compile(source, root: root, mode: .jvmJar)
            #expect(exitCode == 0, "\(diagnostics.map(\.message))")

            let execution = try java(["-jar", root.appendingPathComponent("hello.jar").path])
            #expect(execution.exitCode == 0, "\(execution.stderr)")
            #expect(execution.stdout.contains("T"))
            #expect(execution.stdout.hasSuffix("Z\n"))
        }
    }

    @Test
    func javaComparableWildcardSignatureKeepsErasedSupertype() throws {
        try withWorkspace { root in
            try """
            package fixture;
            import java.util.List;
            public class Lower implements Comparable<List<? super String>> {
                @Override public int compareTo(List<? super String> other) { return 0; }
            }
            """.write(to: root.appendingPathComponent("Lower.java"), atomically: true, encoding: .utf8)
            let compiled = try jvmTool("javac", ["-d", "java-classes", "Lower.java"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")

            let source = """
            import fixture.Lower
            fun main() {
                val lower: Lower? = null
                println(lower == null)
            }
            """
            let classpath = [root.appendingPathComponent("java-classes").path]
            let (exitCode, diagnostics) = try compile(source, root: root, mode: .jvmJar, classpath: classpath)
            try #require(exitCode == 0, "\(diagnostics.map(\.message))")

            let execution = try java(["-jar", root.appendingPathComponent("hello.jar").path])
            #expect(execution.exitCode == 0, "\(execution.stderr)")
            #expect(execution.stdout == "true\n")
        }
    }

    @Test
    func javaComparableSignatureSurvivesEarlierWildcardSupertype() throws {
        try withWorkspace { root in
            try """
            package fixture;
            public interface Marker<T> {}
            """.write(to: root.appendingPathComponent("Marker.java"), atomically: true, encoding: .utf8)
            try """
            package fixture;
            import java.util.List;
            public class WildcardFirst implements Marker<List<?>>, Comparable<WildcardFirst> {
                @Override public int compareTo(WildcardFirst other) { return 0; }
                @Override public String toString() { return "wildcard"; }
            }
            """.write(to: root.appendingPathComponent("WildcardFirst.java"), atomically: true, encoding: .utf8)
            let compiled = try jvmTool("javac", ["-d", "java-classes", "Marker.java", "WildcardFirst.java"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")

            let source = """
            import fixture.WildcardFirst
            fun <T : Comparable<T>> identity(value: T): T = value
            fun main() {
                println(identity(WildcardFirst()))
            }
            """
            let classpath = [root.appendingPathComponent("java-classes").path]
            let (exitCode, diagnostics) = try compile(source, root: root, mode: .jvmJar, classpath: classpath)
            try #require(exitCode == 0, "\(diagnostics.map(\.message))")

            let execution = try java(["-cp", root.appendingPathComponent("hello.jar").path + ":" + classpath.joined(separator: ":"), "HelloKt"])
            #expect(execution.exitCode == 0, "\(execution.stderr)")
            #expect(execution.stdout == "wildcard\n")
        }
    }
}
#endif
