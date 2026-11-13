#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func inheritedJavaConstantsFollowInterfaceLookup() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            package fixture;
            public final class Contracts {
                public interface Left { String UNIQUE = "calendar"; String CLASH = "left"; }
                public interface Right { String CLASH = "right"; }
                public interface Sub extends Left {}
                public static final class Events implements Sub, Right { public static final String OWN = "owned"; }
                public static final class Shadow implements Left { public static final String UNIQUE = "shadow"; }
            }
            """.write(to: root.appendingPathComponent("Contracts.java"), atomically: true, encoding: .utf8)
            let dependency = root.appendingPathComponent("dependency").path
            let compiled = try jvmTool("javac", ["--release", "8", "-d", dependency, "Contracts.java"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [dependency, library.path]
            let source = """
            import fixture.Contracts.Events
            import fixture.Contracts.Shadow
            fun main() {
                println(Events.UNIQUE)
                println(Events.OWN)
                println(Shadow.UNIQUE)
            }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let result = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "calendar\nowned\nshadow\n")

            let rejected = """
            import fixture.Contracts.Events
            fun bad() = Events.CLASH
            """
            let (_, failure, errors) = try m22Build(
                root: root, sources: [("Bad.kt", rejected)], name: "bad.jar", classpath: classpath
            )
            #expect(failure != 0)
            #expect(errors.contains { $0.severity == .error })
        }
    }
}
#endif
