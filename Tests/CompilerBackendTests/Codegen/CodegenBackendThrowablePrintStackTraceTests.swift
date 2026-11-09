#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

private func normalizeThrowableStderr(_ stderr: String) -> String {
    stderr
        .replacingOccurrences(of: "\r\n", with: "\n")
        .components(separatedBy: "\n")
        .filter { line in
            !(line.hasPrefix("warning: direct reference to protected function ")
                && line.contains(" may break pointer equality"))
        }
        .joined(separator: "\n")
}

@Suite
struct CodegenBackendThrowablePrintStackTraceTests {

    @Test
    func testCodegenThrowablePrintStackTraceWritesToStandardError() throws {
        let source = """
        package traces

        class CustomRuntimeException : RuntimeException()

        fun main() {
            RuntimeException("stack message").printStackTrace()
            IndexOutOfBoundsException("index message").printStackTrace()
            CustomRuntimeException().printStackTrace()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ThrowablePrintStackTraceRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStderr = normalizeThrowableStderr(result.stderr)
            #expect(result.stdout == "")
            let lines = normalizedStderr.split(separator: "\n").map(String.init)
            let headers = lines.filter { !$0.hasPrefix("\tat ") }
            #expect(headers == [
                "java.lang.RuntimeException: stack message",
                "java.lang.IndexOutOfBoundsException: index message",
                "traces.CustomRuntimeException",
            ])
            for header in headers {
                let index = try #require(lines.firstIndex(of: header))
                #expect(index + 1 < lines.count)
                #expect(lines[index + 1].hasPrefix("\tat "))
            }
        }
    }

    @Test
    func testStackTraceToStringIncludesSavedFramesAndQualifiedHeaders() throws {
        let source = """
        package traces

        class CustomException : RuntimeException("custom")
        class RenderedException : RuntimeException() {
            override fun toString(): String = "rendered exception"
        }

        fun main() {
            val e = IllegalStateException("e")
            val trace = e.stackTraceToString()
            println(trace.startsWith("java.lang.IllegalStateException: e\\n\\tat "))
            println(trace == e.stackTraceToString())
            println(RuntimeException().stackTraceToString().startsWith("java.lang.RuntimeException\\n\\tat "))
            println(CustomException().stackTraceToString().startsWith("traces.CustomException: custom\\n\\tat "))
            println(RenderedException().stackTraceToString().startsWith("rendered exception\\n\\tat "))
            e.initCause(IllegalArgumentException("cause"))
            e.addSuppressed(RuntimeException("suppressed"))
            val chained = e.stackTraceToString()
            // JVM printEnclosedStackTrace layout (KUU-4322): Suppressed:
            // captions indent one tab deeper than their parent and their
            // frames carry the same indent; Caused by: keeps the parent indent.
            println(chained.contains("\\tSuppressed: java.lang.RuntimeException: suppressed\\n\\t\\tat "))
            println(chained.contains("Caused by: java.lang.IllegalArgumentException: cause\\n\\tat "))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ThrowableStackTraceToString",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.stdout == String(repeating: "true\n", count: 7))
            #expect(normalizeThrowableStderr(result.stderr).isEmpty)
        }
    }

    @Test
    func testStackTraceUsesJvmStyleKotlinFrames() throws {
        let source = """
        package stack_traces

        fun myFunc() {
            throw Exception("boom")
        }

        fun main() {
            try { myFunc()
            } catch (e: Exception) {
                println(e.stackTraceToString())
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let fileName = URL(fileURLWithPath: path).lastPathComponent
            let facadeName = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent + "Kt"
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ThrowableJvmStyleStackTrace",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let lines = result.stdout.split(separator: "\n").map(String.init)
            #expect(lines.first == "java.lang.Exception: boom")
            #expect(lines.contains("\tat stack_traces.\(facadeName).myFunc(\(fileName):4)"))
            #expect(lines.contains("\tat stack_traces.\(facadeName).main(\(fileName):8)"))
            #expect(!result.stdout.contains("0x"))
            #expect(!result.stdout.contains("$s"))
            #expect(normalizeThrowableStderr(result.stderr).isEmpty)
        }
    }

    /// KUU-4320: circular suppressed/cause graphs must not recurse without
    /// bound — JVM `printEnclosedStackTrace` collapses any revisit (true
    /// cycle or diamond) to "[CIRCULAR REFERENCE: ...]" and
    /// `stackTraceToString` does the same.
    @Test
    func testStackTraceToStringDetectsCircularSuppressedAndCauseReferences() throws {
        let source = """
        class MyException(msg: String) : Exception(msg)

        fun main() {
            val a = MyException("a")
            val b = MyException("b")
            a.addSuppressed(b)
            b.addSuppressed(a)
            val mutual = a.stackTraceToString()
            println(mutual.contains("Suppressed: MyException: b"))
            println(mutual.contains("[CIRCULAR REFERENCE: MyException: a]"))

            val c = MyException("c")
            val d = MyException("d")
            c.initCause(d)
            d.initCause(c)
            val caused = c.stackTraceToString()
            println(caused.contains("Caused by: MyException: d"))
            println(caused.contains("[CIRCULAR REFERENCE: MyException: c]"))

            // Diamond: `shared` is reachable through two suppressed branches;
            // the JVM's global dejaVu reports the second visit as circular.
            val root = MyException("root")
            val s1 = MyException("s1")
            val s2 = MyException("s2")
            val shared = MyException("shared")
            s1.addSuppressed(shared)
            s2.addSuppressed(shared)
            root.addSuppressed(s1)
            root.addSuppressed(s2)
            val diamond = root.stackTraceToString()
            println(diamond.contains("Suppressed: MyException: shared"))
            println(diamond.contains("[CIRCULAR REFERENCE: MyException: shared]"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ThrowableCircularStackTraceToString",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.stdout == String(repeating: "true\n", count: 6))
            #expect(normalizeThrowableStderr(result.stderr).isEmpty)
        }
    }

    /// KUU-4322: `stackTraceToString` follows `printEnclosedStackTrace` —
    /// `Suppressed:` captions indent one tab deeper than their parent
    /// (accumulating with nesting), `Caused by:` keeps the parent's indent,
    /// and frame tails shared with the enclosing trace collapse into a
    /// `\t... N more` line. Assigned `stackTrace` elements make the shared
    /// suffix deterministic; the expected block is the JVM output verbatim.
    @Test
    func testStackTraceToStringUsesJvmEnclosedTraceFormat() throws {
        let source = """
        class NoTrace(msg: String) : Exception(msg, null, true, false)

        fun ste(cls: String, m: String, f: String, l: Int) = StackTraceElement(cls, m, f, l)

        fun main() {
            val deep = IllegalStateException("deep-sup")
            val mid = RuntimeException("mid", NullPointerException("mid-cause"))
            mid.addSuppressed(deep)
            val outer = Exception("outer", IllegalArgumentException("outer-cause"))
            outer.addSuppressed(mid)
            outer.addSuppressed(NoTrace("no-trace"))
            val clone = RuntimeException("clone")
            outer.addSuppressed(clone)

            val common = arrayOf(ste("s.Bot", "z", "S.kt", 2), ste("r.Root", "m", "R.kt", 1))
            outer.stackTrace = common
            mid.stackTrace = arrayOf(ste("m.Top", "z", "M.kt", 5)) + common
            deep.stackTrace = common
            mid.cause!!.stackTrace = arrayOf(ste("n.Top", "z", "N.kt", 6)) + common
            outer.cause!!.stackTrace = arrayOf(ste("i.Top", "z", "I.kt", 7)) + common
            clone.stackTrace = common

            println("BEGIN")
            println(outer.stackTraceToString())
            println("END")
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ThrowableEnclosedStackTraceFormat",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(normalizeThrowableStderr(result.stderr).isEmpty)

            let lines = result.stdout.components(separatedBy: "\n")
            guard let begin = lines.firstIndex(of: "BEGIN"),
                  let end = lines.firstIndex(of: "END"), begin + 1 < end
            else {
                Issue.record("missing BEGIN/END markers in stdout: \(result.stdout)")
                return
            }
            let trace = Array(lines[(begin + 1) ..< end])
            #expect(trace == [
                "java.lang.Exception: outer",
                "\tat s.Bot.z(S.kt:2)",
                "\tat r.Root.m(R.kt:1)",
                "\tSuppressed: java.lang.RuntimeException: mid",
                "\t\tat m.Top.z(M.kt:5)",
                "\t\t... 2 more",
                "\t\tSuppressed: java.lang.IllegalStateException: deep-sup",
                "\t\t\t... 2 more",
                "\tCaused by: java.lang.NullPointerException: mid-cause",
                "\t\tat n.Top.z(N.kt:6)",
                "\t\t... 2 more",
                "\tSuppressed: NoTrace: no-trace",
                "\tSuppressed: java.lang.RuntimeException: clone",
                "\t\t... 2 more",
                "Caused by: java.lang.IllegalArgumentException: outer-cause",
                "\tat i.Top.z(I.kt:7)",
                "\t... 2 more",
            ])
        }
    }
}
#endif
