#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledCharRangeLinksAgainstOwnStdlib() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            fun main() {
                val letters = CharRange('a', 'c')
                val range: ClosedRange<Char> = letters
                val open: OpenEndRange<Char> = letters
                println(range.start)
                println(range.endInclusive)
                println(open.endExclusive)
                println('b' in range)
                println('d' in open)
                val cursor = letters.iterator()
                println(cursor.nextChar())
                println(cursor.next())
                val backwards = CharProgression.fromClosedRange('f', 'a', -2)
                println(backwards.last)
                println(backwards.joinToString())
                println(CharRange.EMPTY.isEmpty())
            }
            """
            try source.write(to: root.appendingPathComponent("CharRangeProbe.kt"), atomically: true, encoding: .utf8)
            let app = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", ["CharRangeProbe.kt", "-d", app.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let args = ["-Xverify:all", "-cp"]
            let reference = try java(args + [app.path + ":" + (try m11Runtime()), "CharRangeProbeKt"])
            let run = try java(args + [app.path + ":" + stdlib.path, "CharRangeProbeKt"])
            #expect(run.stdout == reference.stdout)
        }
    }
}
#endif
