#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func expectActualDeclarationsCompileForTheJVMTarget() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let common = """
            package mpp

            internal expect fun platformName(prefix: String): String
            internal expect val separator: String
            expect class Clock() {
                fun now(): Long
            }

            fun describe(): String = platformName("jvm") + separator + Clock().now()

            fun main() { println(describe()) }
            """
            let platform = """
            package mpp

            internal actual fun platformName(prefix: String): String = prefix + "-android"
            internal actual val separator: String = ":"
            actual class Clock actual constructor() {
                actual fun now(): Long = 42L
            }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Common.kt", common), ("Platform.kt", platform)], name: "app.jar",
                classpath: [own.path]
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + own.path, "mpp.CommonKt"])
            #expect(run.stdout == "jvm-android:42\n", "\(run.stderr)")
        }
    }
}
#endif
