#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    /// Text functions lowered from `JVMTextOperation` rows (including the
    /// `@InlineOnly` ones with no stdlib body) and runtime-facade text
    /// declarations must be usable as callable references, not only as calls.
    private static func kuu4734TextReferenceSource(printReference: Bool) -> String {
        """
    fun apply(f: (String) -> Unit) { f("x") }

    fun main() {
        val f = String::trimIndent
        println(listOf("  a", "  b").map(f))
        println(listOf("a", "b").map(String::uppercase))
        println(listOf(" a ", " b ").map(String::trim))
        println(listOf("abc").map(String::reversed))
        println(listOf("", "a").map(String::isEmpty))
        println(listOf(" ", "a").map(String::isNotBlank))
        println(listOf("a\\nb").map(String::lines))
        println(listOf("1a").map(String::toIntOrNull))
        println(listOf("a").map(String::encodeToByteArray).map { it.size })
        val encodeAll: (String, Int, Int, Boolean) -> ByteArray = String::encodeToByteArray
        println(encodeAll("abc", 1, 3, false).toList())
        val encodeFrom: (String, Int) -> ByteArray = String::encodeToByteArray
        println(encodeFrom("abc", 1).toList())
        val take: (String, Int) -> String = String::take
        println(take("hello", 2))
        val bound = "hello"::take
        println(bound(3))
        val upper: () -> String = "abc"::uppercase
        println(upper())
        val trimChars: (String, CharArray) -> String = String::trim
        println(trimChars("xxaxx", charArrayOf('x')))
        println(listOf("  |x").map(String::trimMargin))
        println(listOf("12").map(String::toInt))
        val pad: (String, Int) -> String = String::padStart
        println(pad("7", 3))
        val before: (String, String) -> String = String::substringBefore
        println(before("a.b", ".") + "|" + before("ab", "."))
        apply(String::trimIndent)
        println(String::trimIndent == String::trimIndent)
    """ + (printReference ? "\n    println(String::trimIndent)" : "") + "\n}\n"
    }

    private static func kuu4734TextReferenceExpected(printReference: Bool) -> String {
        """
    [a, b]
    [A, B]
    [a, b]
    [cba]
    [true, false]
    [false, true]
    [[a, b]]
    [null]
    [1]
    [98, 99]
    [98, 99]
    he
    hel
    ABC
    a
    [x]
    [12]
      7
    a|ab
    true

    """ + (printReference ? "function trimIndent (Kotlin reflection is not available)\n" : "")
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func kuu4734TextCallableReferencesRunOnOwnAndOfficialRuntimes(mode: EmitMode) throws {
        try withWorkspace { root in
            // The official lane carries kotlin-reflect, so only invocation is compared here.
            try runRuntimeParity(Self.kuu4734TextReferenceSource(printReference: false), expected: Self.kuu4734TextReferenceExpected(printReference: false), mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func kuu4734TextCallableReferencesCompileWithoutClasspath(mode: EmitMode) throws {
        try withWorkspace { root in
            let runtime = try m11Runtime().components(separatedBy: ":").filter { !$0.hasSuffix("kotlin-reflect.jar") }.joined(separator: ":")
            let compiled = try compile(Self.kuu4734TextReferenceSource(printReference: true), root: root, mode: mode)
            try #require(compiled.0 == 0, "\(compiled.1.map(\.message))")
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            // Without kotlin-reflect the references must still invoke directly.
            let generated = try java(["-cp", artifact + ":" + runtime, "HelloKt"])
            #expect(generated.stdout == Self.kuu4734TextReferenceExpected(printReference: true))
            #expect(generated.stderr.isEmpty)
            _ = try jvmTool("kotlinc", ["hello.kt", "-cp", runtime, "-d", "reference.jar"], root: root)
            let reference = try java(["-cp", root.appendingPathComponent("reference.jar").path + ":" + runtime, "HelloKt"])
            #expect(reference.stdout == Self.kuu4734TextReferenceExpected(printReference: true))
        }
    }

    /// The bundled stdlib lacked the ranged `encodeToByteArray` overload, so
    /// both calls and references to it failed with `NoSuchMethodError` there.
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func kuu4734RangedEncodeToByteArrayMatchesOnBothRuntimes(mode: EmitMode) throws {
        try withWorkspace { root in
            try runRuntimeParity("""
            fun main() {
                println("abc".encodeToByteArray(1, 3, false).toList())
                println("abc".encodeToByteArray(1).toList())
                println("a\\uD800b".encodeToByteArray(0, 3, false).toList())
                println("\\uD83D\\uDE00".encodeToByteArray(0, 2, true).size)
                try { "a\\uD800b".encodeToByteArray(0, 3, true) } catch (e: Exception) { println(e::class.simpleName + ": " + e.message) }
                try { "abc".encodeToByteArray(2, 1) } catch (e: Exception) { println(e::class.simpleName + ": " + e.message) }
                try { "abc".encodeToByteArray(0, 4) } catch (e: Exception) { println(e::class.simpleName + ": " + e.message) }
            }
            """, expected: """
            [98, 99]
            [98, 99]
            [97, 63, 98]
            4
            MalformedInputException: Input length = 1
            IllegalArgumentException: startIndex: 2 > endIndex: 1
            IndexOutOfBoundsException: startIndex: 0, endIndex: 4, size: 3

            """, mode: mode, root: root)
        }
    }

    /// `KFunction.call` looks the target up by the recorded JVM signature, so
    /// it must name the real declaration (`CharSequence.repeat`, not the JVM
    /// stub's `String.repeat`). The official runtime refuses reflective calls
    /// into stdlib multifile facades even for kotlinc output, so only the
    /// bundled runtime is exercised.
    @Test
    func kuu4734TextReferenceReflectiveCallUsesRealSignature() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            fun main() {
                val indent = String::trimIndent
                println(indent.call("  a"))
                val repeat = String::repeat
                println(repeat.call("ab", 2))
                val lines = String::lines
                println(lines.call("a\\nb"))
            }
            """
            let app = try m22Build(root: root, sources: [("hello.kt", source)], name: "app.jar", mode: .jvmJar, classpath: [library.path])
            try #require(app.1 == 0, "\(app.2.map(\.message))")
            let execution = try java(["-cp", app.0.path + ":" + library.path, "HelloKt"])
            #expect(execution.stdout == "a\nabab\n[a, b]\n")
            #expect(execution.stderr.isEmpty)
        }
    }

    @Test
    func kuu4734UserTextExtensionReferenceIsNotRedirected() throws {
        try withWorkspace { root in
            try runM11("""
            fun String.trimIndent(): String = "mine:" + this

            fun main() {
                println(listOf(" a").map(String::trimIndent))
            }
            """, expected: "[mine: a]\n", mode: .jvmJar, root: root)
        }
    }
}
#endif
