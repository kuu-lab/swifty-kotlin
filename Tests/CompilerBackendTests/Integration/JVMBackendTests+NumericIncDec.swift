#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func numericIncDecOperatorsUseBundledStdlib(mode: EmitMode) throws {
        let source = """
        fun main() {
            println(1.inc())
            println(1.dec())
            println(1L.inc())
            println(1.toByte().inc())
            println(1.toShort().dec())
            println(1.0f.inc())
            println(1.0.dec())
            println(1u.inc())
            println(1uL.dec())
            println(1.toUByte().inc())
            println(1.toUShort().dec())

            val (k, v) = 1 to "a"
            println(k.inc())
            println(v.length)
        }
        """
        let expected = "2\n0\n2\n2\n0\n2.0\n0.0\n2\n0\n2\n0\n2\n1\n"

        try withWorkspace { root in
            let runtime = try m11Runtime()
            let app = try m22Build(
                root: root,
                sources: [("Main.kt", source)],
                name: mode == .jvmJar ? "numeric-inc-dec.jar" : "numeric-inc-dec-classes",
                mode: mode,
                classpath: runtime.components(separatedBy: ":")
            )
            try #require(app.1 == 0, "\(app.2.map(\.message))")

            let candidate = try java(["-cp", app.0.path + ":" + runtime, "MainKt"])
            #expect(candidate.stdout == expected)
            #expect(candidate.stderr.isEmpty)

            _ = try jvmTool(
                "kotlinc",
                ["-cp", runtime, "Main.kt", "-d", "consumer.jar"],
                root: root
            )
            let consumer = try java(["-cp", root.appendingPathComponent("consumer.jar").path + ":" + runtime, "MainKt"])
            #expect(consumer.stdout == expected)
            #expect(consumer.stderr.isEmpty)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func incDecCallableReferencesUseRuntimeFacades(mode: EmitMode) throws {
        let source = """
        fun main() {
            val inc: (Int) -> Int = Int::inc
            val dec: (Long) -> Long = Long::dec
            val charInc: (Char) -> Char = Char::inc
            val charDec: (Char) -> Char = Char::dec
            println(inc(1))
            println(dec(2L))
            println(charInc('a'))
            println(charDec('b'))
        }
        """
        let expected = "2\n1\nb\na\n"

        try withWorkspace { root in
            let runtime = try m11Runtime()
            let app = try m22Build(
                root: root,
                sources: [("Main.kt", source)],
                name: mode == .jvmJar ? "inc-dec-references.jar" : "inc-dec-references-classes",
                mode: mode,
                classpath: runtime.components(separatedBy: ":")
            )
            try #require(app.1 == 0, "\(app.2.map(\.message))")

            let candidate = try java(["-cp", app.0.path + ":" + runtime, "MainKt"])
            #expect(candidate.stdout == expected)
            #expect(candidate.stderr.isEmpty)

            _ = try jvmTool(
                "kotlinc",
                ["-cp", runtime, "Main.kt", "-d", "consumer.jar"],
                root: root
            )
            let consumer = try java(["-cp", root.appendingPathComponent("consumer.jar").path + ":" + runtime, "MainKt"])
            #expect(consumer.stdout == expected)
            #expect(consumer.stderr.isEmpty)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func charIncDecOperatorsUseBundledStdlib(mode: EmitMode) throws {
        let source = """
        fun main() {
            println('a'.inc())
            println('a'.dec())
            val c = 'A'
            println(c.inc())
            println(c.dec())
        }
        """
        let expected = "b\n`\nB\n@\n"

        try withWorkspace { root in
            let runtime = try m11Runtime()
            let app = try m22Build(
                root: root,
                sources: [("Main.kt", source)],
                name: mode == .jvmJar ? "char-inc-dec.jar" : "char-inc-dec-classes",
                mode: mode,
                classpath: runtime.components(separatedBy: ":")
            )
            try #require(app.1 == 0, "\(app.2.map(\.message))")

            let candidate = try java(["-cp", app.0.path + ":" + runtime, "MainKt"])
            #expect(candidate.stdout == expected)
            #expect(candidate.stderr.isEmpty)

            _ = try jvmTool(
                "kotlinc",
                ["-cp", runtime, "Main.kt", "-d", "consumer.jar"],
                root: root
            )
            let consumer = try java(["-cp", root.appendingPathComponent("consumer.jar").path + ":" + runtime, "MainKt"])
            #expect(consumer.stdout == expected)
            #expect(consumer.stderr.isEmpty)
        }
    }
}
#endif
