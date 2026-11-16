#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func jvmSynchronizedReleasesTheMonitorForAllExits() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            import probe.Monitor
            fun early(lock: Any): Int {
                synchronized(lock) { return 13 }
                return 0
            }

            fun main() {
                val lock = Any()
                println(synchronized(lock) { Monitor.holds(lock) })
                println(Monitor.holds(lock))
                try {
                    synchronized(lock) { throw IllegalStateException("test") }
                } catch (failure: IllegalStateException) {
                    println(failure.message)
                }
                println(Monitor.holds(lock))
                println(early(lock))
                println(Monitor.holds(lock))
            }
            """
            let dependency = root.appendingPathComponent("jdk").path
            try """
            package probe;
            public class Monitor {
                public static boolean holds(Object lock) { return Thread.holdsLock(lock); }
            }
            """.write(to: root.appendingPathComponent("Monitor.java"), atomically: true, encoding: .utf8)
            let javac = try jvmTool("javac", ["--release", "8", "-d", dependency, "Monitor.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            let classpath = [stdlib.path, dependency]
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "true\nfalse\ntest\nfalse\n13\nfalse\n")
        }
    }
}
#endif
