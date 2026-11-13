#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func objectArrayLastIndexAndDoubleCoerceInLinkPrecompiledKotlin() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
                fun main() {
                    println(emptyArray<String>().lastIndex)
                    println(arrayOf("a", "b").lastIndex)
                    println((-10.0).coerceIn(-2.5, 3.0))
                    println(1.5.coerceIn(-2.5, 3.0))
                    println(10.0.coerceIn(-2.5, 3.0))
                    println(Double.NaN.coerceIn(-2.5, 3.0).isNaN())
                    try {
                        println(1.0.coerceIn(3.0, -2.5))
                    } catch (failure: IllegalArgumentException) {
                        println("empty range")
                    }
                }
                """
            try source.write(to: root.appendingPathComponent("Main.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["Main.kt", "-d", "precompiled.jar"], root: root)
            let consumer = root.appendingPathComponent("precompiled.jar")
            let run = try java(["-Xverify:all", "-cp", consumer.path + ":" + stdlib.path, "MainKt"])
            #expect(run.stdout == "-1\n1\n-2.5\n1.5\n3.0\ntrue\nempty range\n")
        }
    }
}
#endif
