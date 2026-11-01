#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    // KUU-3983: a compile-time constant String `+` or template folds into the
    // interned literal — `ldc` — so `===` observes the shared instance, while
    // a runtime concatenation keeps its fresh non-interned String.
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func constantStringConcatenationFoldsToInternedLiteral(mode: EmitMode) throws {
        let source = """
        const val C = "cd"
        val plainVal = "ab"
        object O { const val OC = "oc" }
        fun box(): Any = "abc"
        fun main() {
            println("ab" + "c" === "abc")
            println("a" + 'b' === "ab")
            println("a" + 5 === "a5")
            println("a" + true === "atrue")
            println("" + null === "null")
            println("x" + "y" + "z" === "xyz")
            println("a" + 1.5 === "a1.5")
            println("a" + 1.5f === "a1.5")
            println("x" + C === "xcd")
            println("x" + O.OC === "xoc")
            println("p" + "${5}" === "p5")
            val dyn = "ab" + "c"
            println(dyn === "abc")
            println(box() === dyn)
            println("a".plus("b") === "ab")
            println('a' + "bc" === "abc")
            println('a'.plus("bc") === "abc")
            val rt = "ab"
            println(rt + "c" === "abc")
            println("x" + plainVal === "xab")
            var v = "ab"
            println("x" + v === "xab")
            println("intern" === "intern")
        }
        """
        try withWorkspace { root in
            let result = try compile(source, root: root, mode: mode)
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let artifact = mode == .jvmJar
                ? root.appendingPathComponent("hello.jar").path
                : root.appendingPathComponent("classes").path
            let execution = mode == .jvmJar
                ? try java(["-jar", artifact])
                : try java(["-cp", artifact, "HelloKt"])
            #expect(
                execution.stdout == "true\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\nfalse\nfalse\nfalse\nfalse\nfalse\ntrue\n",
                "\(execution.stdout)"
            )
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
