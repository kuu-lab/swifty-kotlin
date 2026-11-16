#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func primitiveRangeBoundsResolveAgainstOwnJvmStdlib() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            fun main() {
                println((-1).coerceAtLeast(1))
                println(3L.coerceAtMost(1L))
                println(4.toByte().coerceAtMost(2.toByte()))
                println((-4).toShort().coerceAtLeast((-2).toShort()))
                println(1.5f.coerceAtMost(1.0f))
                println(Double.NaN.coerceAtLeast(0.0).isNaN())
                println(1.0 / (-0.0).coerceAtLeast(0.0))
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [own.path])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + own.path, "MainKt"])
            #expect(run.stdout == "1\n1\n2\n-2\n1.0\ntrue\n-Infinity\n")
        }
    }
}
#endif
