#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedCollectionDiamondKeepsSourceOverrideChecks() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let collection = """
            package java.util;
            public interface Collection<E> extends Iterable<E> {
                default java.util.stream.Stream<E> stream() { return null; }
            }
            """
            try collection.write(to: root.appendingPathComponent("Collection.java"), atomically: true, encoding: .utf8)
            let platform = try jvmTool("javac", ["--release", "8", "-d", "platform", "Collection.java"], root: root)
            try #require(platform.exitCode == 0, "\(platform.stderr)")

            let producer = """
            package fixture
            interface Group<E> {
                interface Builder<E> : MutableCollection<E>
            }
            interface Sequence<E> {
                interface Builder<E> : MutableList<E>, Group.Builder<E>
            }
            private class Rows : Sequence.Builder<String>, MutableList<String> by arrayListOf("session")
            fun builder(): Sequence.Builder<String> = Rows()
            """
            try producer.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let compiled = try jvmTool("kotlinc", ["Provider.kt", "-d", "provider.jar"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let libraries = [root.appendingPathComponent("provider.jar").path, own.path]
            let classpath = [root.appendingPathComponent("platform").path] + libraries

            let source = """
            import fixture.builder
            fun main() { println(builder()[0]) }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Consumer.kt", source)], name: "app.jar", classpath: classpath
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + libraries).joined(separator: ":"), "ConsumerKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "session\n")

            let conflict = """
            interface Left { fun count(): Int = 1 }
            interface Right { fun count(): Int = 2 }
            interface Conflict : Left, Right
            """
            let (_, invalidExit, invalidDiagnostics) = try m22Build(
                root: root, sources: [("Conflict.kt", conflict)], name: "conflict.jar", classpath: classpath
            )
            #expect(invalidExit != 0)
            #expect(invalidDiagnostics.filter { $0.severity == .error }.map(\.code) == ["KSWIFTK-SEMA-0171"])
        }
    }
}
#endif
