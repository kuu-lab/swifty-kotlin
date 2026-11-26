#if canImport(Testing)
import CompilerCore
import Foundation
@testable import KSwiftKCLI
import Testing

extension JVMIncludeRuntimeTests {
    @Test
    func charDirectionalityEnumApiRunsFromBundledJar() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("kswiftk-char-directionality-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let input = root.appendingPathComponent("CharDirectionalityMain.kt")
        try """
        fun main() {
            println('a'.directionality.name + ":" + CharDirectionality.WHITESPACE.ordinal)
            println('\\u0378'.directionality)
            for (c in listOf('\\u2066', '\\u2069')) {
                try { println(c.directionality.name) } catch (t: IllegalArgumentException) { println(t.message) }
            }
            println(CharDirectionality.valueOf("WHITESPACE") == CharDirectionality.WHITESPACE)
            println(enumValues<CharDirectionality>().size)
        }
        """.write(to: input, atomically: true, encoding: .utf8)

        let runnableJAR = root.appendingPathComponent("char-directionality.jar")
        let arguments = ["--emit", "jar", "-m", "KSwiftKStdlib", input.path, "-include-runtime", "-o", runnableJAR.path]
        try #require(CLICompilerService.shared.run(args: arguments) == 0)

        let java = CommandRunner.resolveExecutable("java", fallback: "/usr/bin/java")
        let result = try CommandRunner.run(executable: java, arguments: ["-Xverify:all", "-jar", runnableJAR.path], timeout: 20)
        #expect(result.stdout == "LEFT_TO_RIGHT:13\nUNDEFINED\nDirectionality #19 is not defined.\nDirectionality #22 is not defined.\ntrue\n20\n")
        #expect(result.stderr.isEmpty)
    }
}
#endif
