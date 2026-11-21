#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importsGeneratedJavaClassesAndConstructorsInTheSamePackage() throws {
        try withWorkspace { root in
            try """
            package fixture;
            final class GeneratedFactory extends Factory implements Factory.Contract {
                GeneratedFactory() {}
                public int value() { return 42; }
                public static Factory.Contract builder() { return new GeneratedFactory(); }
            }
            """.write(to: root.appendingPathComponent("GeneratedFactory.java"), atomically: true, encoding: .utf8)
            try """
            package fixture;
            public final class Entry {
                Entry(int value) {}
                private Entry(String value) {}
            }
            """.write(to: root.appendingPathComponent("Entry.java"), atomically: true, encoding: .utf8)
            try """
            package fixture;
            public abstract class Factory {
                public interface Contract {}
            }
            """.write(to: root.appendingPathComponent("Factory.java"), atomically: true, encoding: .utf8)
            let dependency = root.appendingPathComponent("dependency")
            let javac = try jvmTool("javac", ["--release", "8", "-d", dependency.path, "GeneratedFactory.java", "Entry.java", "Factory.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            for name in ["Factory.class", "Factory$Contract.class"] {
                try FileManager.default.removeItem(at: dependency.appendingPathComponent("fixture").appendingPathComponent(name))
            }
            let factory = ("Factory.kt", "package fixture\nabstract class Factory { interface Contract }")
            let main = """
            package fixture
            fun main() {
                val factory: Factory = GeneratedFactory()
                val contract: Factory.Contract = GeneratedFactory.builder()
                println(GeneratedFactory().value())
                Entry(3)
            }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [factory, ("Main.kt", main)], name: "app.jar", classpath: [dependency.path]
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + dependency.path, "fixture.MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "42\n")

            let packageMarker = ("Marker.kt", "package fixture\nfun marker() = 0")
            let rejected = [
                "package unrelated\nfun bad() = fixture.GeneratedFactory()",
                "package unrelated\nfun bad() = fixture.Entry(3)",
                "package fixture\nfun bad() = Entry(\"private\")"
            ]
            for (index, source) in rejected.enumerated() {
                let (_, failure, errors) = try m22Build(
                    root: root, sources: [factory, packageMarker, ("Bad.kt", source)],
                    name: "bad\(index).jar", classpath: [dependency.path]
                )
                #expect(failure != 0, "\(source)")
                #expect(errors.contains { $0.severity == .error }, "\(source)")
            }
        }
    }
}
#endif
