#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func javaClassTokenDeterminesImportedMethodResultType() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            package fixture;

            public final class Services {
                public interface Signal {}

                public static final class Alarm implements Signal {
                    public String ring() { return "ring"; }
                }

                public <T> T getService(Class<T> serviceType) {
                    return serviceType.cast(new Alarm());
                }

                public <T extends Signal> T castService(String value, Class<T> type) {
                    if (!value.equals("alarm")) throw new IllegalArgumentException();
                    return type.cast(new Alarm());
                }
            }
            """
            try provider.write(to: root.appendingPathComponent("Services.java"), atomically: true, encoding: .utf8)
            let dependency = root.appendingPathComponent("deps")
            let compiled = try jvmTool("javac", ["--release", "8", "-d", dependency.path, "Services.java"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [dependency.path, own.path]
            let source = """
            import fixture.Services
            fun main() {
                val services = Services()
                val alarm = services.getService(Services.Alarm::class.java)
                println(alarm.ring())
                println(services.castService("alarm", Services.Alarm::class.java).ring())
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "ring\nring\n")
        }
    }
}
#endif
