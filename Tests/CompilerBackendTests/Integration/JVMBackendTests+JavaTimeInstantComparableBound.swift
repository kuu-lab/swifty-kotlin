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
}
#endif
