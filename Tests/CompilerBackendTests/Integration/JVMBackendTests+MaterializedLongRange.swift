#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func jvmForLoopReadsMaterializedLongRangeFromRepositoryStdlib() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            fun main() {
                val range = Long.MAX_VALUE - 1L..Long.MAX_VALUE
                for (value in range) println(value)
                val empty = Long.MAX_VALUE..0L
                for (value in empty) error("empty range yielded " + value)
            }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [stdlib.path]
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + stdlib.path, "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "9223372036854775806\n9223372036854775807\n")
        }
    }
}
#endif
