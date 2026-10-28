#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func stdlibSourceRuntimeStringsAndCollections(mode: EmitMode) throws {
        try withWorkspace { root in
            let library = try m22Build(root: root, name: "kswiftk-stdlib.jar", stdlib: true)
            try #require(library.1 == 0, "\(library.2.map(\.message))")
            let foreign = root.appendingPathComponent("foreign")
            try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: true)
            try """
            public final class OpaqueText implements CharSequence {
                public int length() { return 1; }
                public char charAt(int i) { return 'x'; }
                public CharSequence subSequence(int a, int b) { return "x".subSequence(a, b); }
                public String toString() { return "y"; }
            }
            """.write(to: root.appendingPathComponent("OpaqueText.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-d", foreign.path, "OpaqueText.java"], root: root)
            let source = #"""
            fun String.self(): String = "$this"
            data class Ranked(val key: Int, val label: String): Comparable<Ranked> {
                override fun compareTo(other: Ranked): Int = key.compareTo(other.key)
            }
            var hashes = 0
            class Key { override fun hashCode(): Int { hashes++; return 1 } }
            class EquivalentKey(val label: String) {
                override fun equals(other: Any?): Boolean = other is EquivalentKey
                override fun hashCode(): Int = 1
                override fun toString(): String = label
            }
            fun main() {
                println("receiver".self())
                val opaque = OpaqueText() as CharSequence
                println("x".contains(opaque)); println("y".contains(opaque))
                val missing: String? = null
                println(missing.orEmpty()); println(missing.isNullOrBlank()); println(missing.isNullOrEmpty())
                println(" \t\n\u00a0".isBlank()); println(" a ".isNotBlank())
                println(' '.isWhitespace()); println('\u00a0'.isWhitespace()); println('x'.isWhitespace())
                println("hello".first()); println("hello".last()); println("".firstOrNull()); println("".lastOrNull())
                println("hello".take(2)); println("hello".takeLast(2)); println("hello".drop(2)); println("hello".dropLast(2))
                println("hello".take(20)); println("hello".drop(20))
                println("x".padStart(3, '0')); println("x".padEnd(3, '!')); println("ab".repeat(3))
                println("aß".uppercase()); println("IABC".lowercase()); println("a😀b".reversed())
                println("TRUE".toBoolean()); println(missing.toBoolean()); println("true".toBooleanStrict()); println("TRUE".toBooleanStrictOrNull())
                println("7f".toByte(16)); println("32767".toShort()); println("ff".toInt(16)); println("-9223372036854775808".toLong())
                println("128".toByteOrNull()); println("-1".toIntOrNull()); println("x".toLongOrNull()); println("1.5".toFloat()); println("NaN".toDoubleOrNull())
                try { "x".take(-1) } catch (e: IllegalArgumentException) { println(e.message) }
                try { "x".toIntOrNull(1) } catch (e: IllegalArgumentException) { println(e.message) }
                try { "bad".toBooleanStrict() } catch (e: IllegalArgumentException) { println(e.message) }
                println("  \u00a0x ".trim()); println("  x ".trimStart()); println(" x  ".trimEnd())
                println("__x__".trim('_')); println("__x__".trimStart('_')); println("__x__".trimEnd('_'))
                println("<text>".removeSurrounding("<", ">")); println("prefix:value".removePrefix("prefix:")); println("value:end".removeSuffix(":end"))
                println("ABC".startsWith("a", ignoreCase = true)); println("ABC".endsWith('c', ignoreCase = true)); println("ABC".contains("b", ignoreCase = true))
                val sequence: CharSequence = "AbCd"
                println("Ab" in sequence); println("bc" in sequence); println('b' in sequence); println('a' in sequence)
                println(sequence.contains(other = "bc", ignoreCase = true)); println(sequence.contains(char = 'a', ignoreCase = true))
                println(sequence.contains("Ab")); println(sequence.contains('b'))
                println("a:b:c".substringBefore(':')); println("a:b:c".substringAfter(":")); println("a:b:c".substringBeforeLast(":")); println("a:b:c".substringAfterLast(':'))
                println("abc".substringBefore("x", "missing")); println("abc".replace("", "-")); println("aAa".replace('a', 'x', true)); println("aAa".replaceFirst("A", "x", true))
                println("a".compareTo("B", true)); println("abc".indexOf("", 100)); println("abc".lastIndexOf("", 100, true))
                val text: CharSequence = StringBuilder("ab")
                for (n in listOf(-5, -1, 0, 1, 2, 3, 100)) {
                    println(text.indexOf("", n)); println(text.lastIndexOf("", n)); println(text.lastIndexOf("", n, true))
                }
                val values = listOf(3, 1, 3, 2)
                println(values.toList()); println(values.toMutableList()); println(values.toSet()); println(values.toMutableSet())
                println(values.distinct()); println(values.reversed()); println(values.sorted()); println(values.sortedDescending())
                val ranked = listOf(Ranked(1, "a"), Ranked(2, "b"), Ranked(1, "c"), Ranked(2, "d"))
                println(ranked.sortedDescending().joinToString { it.label })
                val key = Key(); val single = listOf(key to 1).toMap(); println(hashes); println(single.size)
                println(values.take(2)); println(values.drop(2)); println(values.take(20)); println(values.drop(20))
                println(values.joinToString()); println(values.joinToString("/", "[", "]", 2, "more") { "v$it" })
                println(listOf("a" to 1, "b" to 2, "a" to 3).toMap())
                val first = EquivalentKey("first"); val last = EquivalentKey("last")
                println(listOf(first to 1, last to 2).toMap())
                try { values.take(-1) } catch (e: IllegalArgumentException) { println(e.message) }
                val function: (Int) -> Int = { it + 1 }; println(function(41))
            }
            """#
            let output = try m22Build(root: root, sources: [("Strings.kt", source)], name: mode == .jvmJar ? "app.jar" : "classes", mode: mode, classpath: [library.0.path, foreign.path])
            try #require(output.1 == 0, "\(output.2.map(\.message))")
            let candidate = try java(["-cp", output.0.path + ":" + library.0.path + ":" + foreign.path, "StringsKt"])
            _ = try jvmTool("kotlinc", ["Strings.kt", "-cp", foreign.path, "-d", "reference.jar"], root: root)
            let runtime = try m11Runtime()
            let reference = try java(["-cp", root.appendingPathComponent("reference.jar").path + ":" + foreign.path + ":" + runtime, "StringsKt"])
            #expect(candidate.stdout == reference.stdout)
            #expect(candidate.stderr.isEmpty)
            _ = try jvmTool("kotlinc", ["-no-stdlib", "-no-reflect", "-cp", library.0.path + ":" + foreign.path, "Strings.kt", "-d", "consumer.jar"], root: root)
            let consumer = try java(["-cp", root.appendingPathComponent("consumer.jar").path + ":" + library.0.path + ":" + foreign.path, "StringsKt"])
            #expect(consumer.stdout == reference.stdout)
            #expect(consumer.stderr.isEmpty)
            if mode == .jvmJar {
                let app = try ZipArchive(data: Data(contentsOf: output.0))
                #expect(!app.entries.contains { $0.name == "kotlin/Unit.class" || $0.name.hasPrefix("kotlin/jvm/functions/") })
            }
            let archive = try ZipArchive(data: Data(contentsOf: library.0))
            for name in ["kotlin/jvm/internal/InlineMarker.class", "kotlin/jvm/internal/Intrinsics.class", "kotlin/UninitializedPropertyAccessException.class"] {
                #expect(archive.entries.contains { $0.name == name })
            }
            let report = try #require(archive.entries.first { $0.name == "META-INF/kswiftk-stdlib-coverage.json" })
            let data = Data(try archive.contents(of: report))
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(json["schemaVersion"] as? Int == 1)
            let present = try #require(json["abiPresent"] as? Int)
            let missing = try #require(json["abiMissing"] as? Int)
            let apis = try #require(json["apis"] as? [[String: Any]])
            #expect(present + missing == apis.count)
            #expect(apis.contains { $0["owner"] as? String == "kotlin/text/StringsKt" && $0["name"] as? String == "take" && $0["status"] as? String == "jar_abi_present" })
        }
    }

    @Test(arguments: ["listOf(1, 2, 3)", "intArrayOf(1, 2, 3)", "\"abc\""])
    func stdlibLoopsDiscardMixedBranchValues(iterable: String) throws {
        try withWorkspace { root in
            let library = try m22Build(root: root, name: "kswiftk-stdlib.jar", stdlib: true)
            try #require(library.1 == 0, "\(library.2.map(\.message))")
            let output = try m22Build(root: root, sources: [("Main.kt", """
            fun Any.firstItem(): Any? = if (this is List<*>) this[0] else null
            fun Iterable<*>.firstIfList(): Any? = if (this is List<*>) this[0] else null
            fun main() {
                var skip = 1
                val result = mutableListOf<Any?>()
                for (element in \(iterable)) {
                    if (skip == 0) result.add(element) else skip--
                }
                println(result)
                println((listOf(4, 5) as Any).firstItem())
                println(listOf(6, 7).firstIfList())
            }
            """)], name: "loops.jar", classpath: [library.0.path])
            try #require(output.1 == 0, "\(output.2.map(\.message))")
            let execution = try java(["-cp", output.0.path + ":" + library.0.path, "MainKt"])
            #expect(execution.stdout == (iterable.hasPrefix("\"") ? "[b, c]\n4\n6\n" : "[2, 3]\n4\n6\n"))
            #expect(execution.stderr.isEmpty)
        }
    }

    @Test
    func stdlibNamedFacadesAndPackageLocalAliases() throws {
        try withWorkspace { root in
            let sources = [("Names.kt", "@file:kotlin.jvm.JvmName(\"PublicNames\")\npackage one\ntypealias Name = String\nfun name(): Name = \"one\""), ("Values.kt", "package two\ntypealias Value = Int\nfun value(): Value = 42"), ("Main.kt", "fun main() { println(one.name()); println(two.value()) }")]
            let output = try m22Build(root: root, sources: sources, name: "facades.jar")
            try #require(output.1 == 0, "\(output.2.map(\.message))")
            let execution = try java(["-jar", output.0.path])
            #expect(execution.stdout == "one\n42\n")
            let archive = try ZipArchive(data: Data(contentsOf: output.0))
            #expect(archive.entries.contains { $0.name == "one/PublicNames.class" })
        }
    }
}
#endif
