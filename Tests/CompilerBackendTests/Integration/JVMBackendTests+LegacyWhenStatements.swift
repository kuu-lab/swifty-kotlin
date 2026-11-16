#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func legacyWhenFlagAllowsDiscardedIncompleteWhenOnly() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            sealed class Result { object Ready : Result(); object Pending : Result() }
            fun observe(callback: (Result) -> Unit) {
                callback(Result.Pending)
                callback(Result.Ready)
            }
            fun main() {
                observe { result -> when (result) { is Result.Ready -> println("ready") } }
                when (false) { true -> error("unexpected true") }
                println("done")
            }
            """
            let defaultMode = try compile(source, root: root, mode: .jvmJar, classpath: [stdlib.path])
            #expect(defaultMode.0 != 0)
            #expect(defaultMode.1.contains { $0.code == "KSWIFTK-SEMA-0071" })

            let flags = [CompilerOptions.legacyNonExhaustiveWhenFlag]
            let legacy = try compile(source, root: root, mode: .jvmJar, flags: flags, classpath: [stdlib.path])
            try #require(legacy.0 == 0, "\(legacy.1.map(\.message))")
            let app = root.appendingPathComponent("hello.jar")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + stdlib.path, "HelloKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "ready\ndone\n")

            let expression = """
            sealed class Result { object Ready : Result(); object Pending : Result() }
            fun value(result: Result): Int = when (result) { is Result.Ready -> 1 }
            """
            let rejected = try compile(expression, root: root, mode: .jvmJar, flags: flags, classpath: [stdlib.path])
            #expect(rejected.0 != 0)
            #expect(rejected.1.contains { $0.code == "KSWIFTK-SEMA-0071" })
        }
    }
}
#endif
