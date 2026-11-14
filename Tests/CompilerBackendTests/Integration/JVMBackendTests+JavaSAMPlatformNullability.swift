#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func javaSAMCallbacksPreservePlatformNullability() throws {
        try withWorkspace { root in
            try """
            package fixture;
            public interface Listener<T> {
                void onEvent(T value, Events error);
            }
            """.write(to: root.appendingPathComponent("Listener.java"), atomically: true, encoding: .utf8)
            try """
            package fixture;
            public class Events {
                public void subscribe(Listener<Events> listener) {
                    listener.onEvent(this, null);
                    listener.onEvent(null, this);
                }
                public void subscribeFlag(Listener<Boolean> listener) {
                    listener.onEvent(true, null);
                    listener.onEvent(false, null);
                }
                @Override public String toString() { return "ready"; }
            }
            """.write(to: root.appendingPathComponent("Events.java"), atomically: true, encoding: .utf8)
            let classes = root.appendingPathComponent("classes").path
            let javac = try jvmTool("javac", ["--release", "8", "-d", classes, "Events.java", "Listener.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            let source = """
            import fixture.Events
            fun main() {
                Events().subscribe { value, error ->
                    if (error != null) {
                        println("offline")
                        println(value == null)
                    } else {
                        println(value)
                    }
                }
                Events().subscribeFlag { flag, _ ->
                    println(if (flag) "yes" else "no")
                }
            }
            """
            let (app, status, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [classes])
            try #require(status == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + classes, "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "ready\noffline\ntrue\nyes\nno\n")
        }
    }
}
#endif
