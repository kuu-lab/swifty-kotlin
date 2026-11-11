#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func snapshotCollectionOperationsLinkPrecompiledKotlin() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
                fun main() {
                    val values = listOf(4, 9)
                    println(values.getOrNull(-1))
                    println(values.getOrNull(1))
                    println(values.getOrNull(2))
                    val nullable: Iterable<String?> = listOf("task", null)
                    println(null in nullable)
                    println("absent" in nullable)
                    val ids = values.toIntArray()
                    println((ids + 16).joinToString())
                    println((ids + intArrayOf(16, 25)).joinToString())
                    println(ids.joinToString())
                }
                """
            try source.write(to: root.appendingPathComponent("Main.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["Main.kt", "-d", "precompiled.jar"], root: root)
            let consumer = root.appendingPathComponent("precompiled.jar")
            let run = try java(["-Xverify:all", "-cp", consumer.path + ":" + stdlib.path, "MainKt"])
            #expect(run.stdout == "null\n9\nnull\ntrue\nfalse\n4, 9, 16\n4, 9, 16, 25\n4, 9\n")
        }
    }
}
#endif
