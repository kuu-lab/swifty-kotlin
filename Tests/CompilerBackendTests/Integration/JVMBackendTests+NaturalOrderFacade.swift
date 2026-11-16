#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledNaturalOrderUsesPublicComparisonsFacade() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            fun main() {
                val comparator = naturalOrder<String>()
                println(comparator.compare("a", "b") < 0)
                println(comparator.compare("b", "a") > 0)
                println(comparator.compare("a", "a"))
            }
            """
            try source.write(to: root.appendingPathComponent("Probe.kt"), atomically: true, encoding: .utf8)
            let app = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", ["Probe.kt", "-d", app.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let bytecode = try javap(["-c", "-cp", app.path, "ProbeKt"])
            #expect(bytecode.stdout.contains("kotlin/comparisons/ComparisonsKt.naturalOrder"))
            let candidate = try java(["-cp", app.path + ":" + stdlib.path, "ProbeKt"])
            #expect(candidate.stdout == "true\ntrue\n0\n")
        }
    }
}
#endif
