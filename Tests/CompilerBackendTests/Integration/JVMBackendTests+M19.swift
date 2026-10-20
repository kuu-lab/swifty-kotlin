#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m19BuilderAndInlineText(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11(#"""
            fun early(): Int { "abc".map { if (it == 'b') return 42; it }; return 0 }
            fun main() {
                val b = StringBuilder("ab"); b.append(charArrayOf('界', 'Z')).append(42).append(true)
                println(b); println(b.length); b[0] = 'A'; println(b[0])
                b.deleteRange(2, 99); b.insert(1, "!"); println(b.reverse()); b.clear(); b.appendLine("x"); println(b.length)
                println(buildString { append("hello"); append('界'); append(42) })
                println("abc".map { it.code }); println("abc".mapIndexed { i, c -> i + c.code })
                println("abc".filter { it != 'b' }); println("abc".filterNot { it == 'b' })
                println("abc".fold(0) { n, c -> n + c.code }); println("abc".foldRight("") { c, n -> n + c })
                println("abc".any { it == 'b' }); println("abc".count { it != 'b' })
                println("abc".takeWhile { it != 'c' }); println("abc".dropWhile { it != 'b' })
                println("abcd".windowed(2)); println("abcde".chunked(2)); println("abc".zipWithNext { a, b -> "" + a + b })
                println(early())
            }
            """#, expected: "ab界Z42true\n10\nA\nb!A\n2\nhello界42\n[97, 98, 99]\n[97, 99, 101]\nac\nac\n294\ncba\ntrue\n2\nab\nbc\n[ab, bc, cd]\n[ab, cd, e]\n[ab, bc]\n42\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m19RegexAndSequences(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11(#"""
            fun main() {
                val r = Regex("(?<word>[a-z]+)([0-9]+)?", RegexOption.IGNORE_CASE)
                println(r.pattern); println(r.matches("ABC12")); println(r.containsMatchIn("!ab!"))
                val m = r.find("!Ab12!")!!; println(m.value); println(m.range.first); println(m.range.last)
                println(m.groups["word"]!!.value); println(m.groupValues); println(m.groups[2]!!.value)
                println(r.findAll("a1 b2").map { it.value }.toList())
                println(Regex("[0-9]+").replace("a12b3") { "[${it.value}]" })
                println("a12b3".replace(Regex("[0-9]+"), "!"))
                println(",a,,".split(",".toRegex())); println(Regex.escape("a.b"))
                println(Regex("a").matchAt("ba", 0)); println(Regex("a").matchAt("ba", 1)!!.value)
                for (m in Regex("").findAll("aa")) println(m.range.first)
                println(Regex("a").find("bb")); println("ABC".matches(Regex("abc", RegexOption.IGNORE_CASE)))
            }
            """#, expected: "(?<word>[a-z]+)([0-9]+)?\ntrue\ntrue\nAb12\n1\n4\nAb\n[Ab12, Ab, 12]\n12\n[a1, b2]\na[12]b[3]\na!b!\n[, a, , ]\n\\Qa.b\\E\nnull\na\n0\n1\n2\nnull\ntrue\n", mode: mode, root: root)
        }
    }
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m19MutableSequencesAndHigherOrderVariants(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11(#"""
            fun grow(b: StringBuilder, c: Char) { if (c == 'a') b.append('c') }
            fun main() {
                var reduction = StringBuilder("ab")
                println(reduction.reduce { a, c -> if (c == 'b') reduction.append('c'); c })
                reduction = StringBuilder("ab"); println(reduction.reduceIndexedOrNull { i, a, c -> if (c == 'b') reduction.append('c'); c })
                var b = StringBuilder("ab"); println(b.map { grow(b, it); it })
                b = StringBuilder("ab"); println(b.filter { grow(b, it); true })
                b = StringBuilder("ab"); println(b.filterNot { grow(b, it); false })
                b = StringBuilder("ab"); println(b.filterIndexed { i, c -> grow(b, c); i >= 0 })
                b = StringBuilder("ab"); println(b.fold("") { n, c -> grow(b, c); n + c })
                b = StringBuilder("ab"); println(b.windowed(1) { if (it[0] == 'a') b.append('c'); it.toString() })
                b = StringBuilder("ab"); val same = b.onEach { grow(b, it) }; println(same === b); println(same)
                val cs: CharSequence = StringBuilder("abcd")
                println(cs.filter { it != 'b' }); println(cs.filter { true }.javaClass.name)
                println(cs.takeLastWhile { it != 'b' }); println(cs.dropLastWhile { it != 'b' })
                println(cs.indexOfFirst { it == 'b' }); println(cs.indexOfLast { it == 'b' })
                println(cs.first { it == 'b' }); println(cs.lastOrNull { it == 'z' }); println(cs.findLast { it < 'c' })
                println(cs.single { it == 'c' }); println(cs.singleOrNull { it < 'c' })
                println("abc".mapNotNull { if (it == 'b') null else it.code })
                println("abc".mapIndexedNotNull { i, c -> if (i == 1) null else c.code + i })
                println("ab".flatMap { listOf(it, it) }); println("ab".flatMapIndexed { i, c -> listOf(i + c.code) })
                println("abc".foldIndexed(0) { i, n, c -> n + i + c.code })
                println("abc".foldRightIndexed("") { i, c, n -> n + i + c })
                println("abc".reduce { a, b -> if (a > b) a else b }); println("abc".reduceRight { a, b -> a })
                println("".reduceOrNull { a, b -> a }); println("abc".reduceIndexed { i, a, b -> if (i == 2) b else a })
                println("abc".reduceRightIndexed { i, a, b -> if (i == 0) a else b })
                println("abca".toSet()); println("A😀".map { it.code }); println("ab".toList())
                println("abc".all { it < 'd' }); println("abc".none { it == 'z' }); println("".none()); println("ab".count())
                println("abcde".windowed(size = 3, partialWindows = true, step = 2) { it.length })
                println("abcde".chunked(2) { it.length })
                try { "".reduce { a, b -> a } } catch (e: UnsupportedOperationException) { println("empty") }
                try { "".first { true } } catch (e: NoSuchElementException) { println("missing") }
                try { "ab".single { true } } catch (e: IllegalArgumentException) { println("many") }
            }
            """#, expected: "b\nb\n[a, b, c]\nab\nabc\nabc\nabc\n[a, b]\ntrue\nabc\nacd\njava.lang.StringBuilder\ncd\nab\n1\n1\nb\nnull\nb\nc\nnull\n[97, 99]\n[97, 101]\n[a, a, b, b]\n[97, 99]\n297\n2c1b0a\nc\na\nnull\nc\na\n[a, b, c]\n[65, 55357, 56832]\n[a, b]\ntrue\ntrue\ntrue\n2\n[3, 3, 1]\n[2, 2, 1]\nempty\nmissing\nmany\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m19BuilderRangesDefaultsAndExceptions(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11(#"""
            fun effect() { println("effect") }
            fun input(n: Int): Int { println("arg$n"); return n }
            fun main() {
                val special = StringBuilder("abc")
                println(special.get(index = 0)); special.set(index = 0, value = 'A')
                println(special.subSequence(startIndex = 0, endIndex = 2)); println(special.substring(startIndex = 1))
                println(special.indexOf(string = "B", startIndex = 0, ignoreCase = true)); println(special.lastIndexOf('c'))
                println(special.isNotEmpty()); println(special.last()); println(special.lastIndex)
                val chars = charArrayOf('A', 'B', 'C', 'D'); val nullable: CharArray? = chars
                val b = StringBuilder(2); b.append(nullable); println(b)
                val any: Any? = chars; b.clear().append(any); println(b.toString().startsWith("[C@"))
                b.clear().appendRange(chars, 1, 3).appendRange("wxyz", 1, 3); println(b)
                b.insertRange(1, chars, 1, 3).insertRange(0, "wxyz", 2, 4); println(b)
                b.setRange(0, 2, "!"); println(b.substring(0, 3)); println(b.indexOf("C")); println(b.lastIndexOf("y"))
                b.clear().append(effect()); println(b)
                b.clear().appendLine('A').appendLine(42).appendLine(); println(b.toString().replace("\n", "/"))
                b.clear().appendCodePoint(0x1f600); println(b); println(b.length)
                b.clear().append("x"); b.setLength(3); println(b[1].code); b.setLength(1); println(b)
                try { val a: CharArray? = null; b.append(a) } catch (e: NullPointerException) { println("nullarray") }
                try { b[9] = 'a' } catch (e: IndexOutOfBoundsException) { println("set") }
                try { b.deleteAt(9) } catch (e: IndexOutOfBoundsException) { println("delete") }
                try { b.appendRange(chars, 3, 2) } catch (e: IndexOutOfBoundsException) { println("range") }
                println(buildString(capacity = input(1), builderAction = { append('a'); append(length) }))
                try { buildString(-1) { append('x') } } catch (e: NegativeArraySizeException) { println("capacity") }
            }
            """#, expected: "a\nAb\nbc\n1\n2\ntrue\nc\n2\nABCD\ntrue\nBCxy\nyzBBCCxy\n!BB\n3\n6\neffect\nkotlin.Unit\nA/42//\n😀\n2\n0\nx\nnullarray\nset\ndelete\nrange\narg1\na1\ncapacity\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m19RegexBoundariesAndCallbacks(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11(#"""
            fun limit(): Int { println("limit"); return 2 }
            fun input(): String { println("input"); return "a,b,c" }
            fun main() {
                val empty = Regex(""); println(empty.findAll("😀").map { it.range.first }.toList())
                val m = Regex(".").find("😀")!!; println(m.range.first); println(m.range.last); println(m.range.start); println(m.range.endInclusive)
                println(empty.split("aa")); println(empty.replace("aa", "-"))
                println(Regex("a*").findAll("aa").map { "${it.value}:${it.range.first}:${it.range.last}" }.toList())
                val r = Regex("(?<letter>[a-z])([0-9])?"); val match = r.find("a")!!
                println(match.groups.size); println(match.groups[2]); println(match.groupValues[2]); println(match.groups["letter"]!!.value)
                val (letter, number) = match.destructured; println("$letter/$number"); println(match.destructured.toList())
                println(Regex("([a-z])").replace("ab", "$1$1"))
                println(Regex("([a-z])").replace("ab") { "$1" })
                var n = 0; val seq = Regex("[a-z]").findAll("a b c").filter { n++; it.value != "b" }.map { it.value.uppercase() }
                println(n); println(seq.toList()); println(n); println(seq.first()); println(n)
                println(Regex(",").split(limit = limit(), input = input()))
                println("a,b,c".split(regex = Regex(","), limit = 2)); println("a,b,".splitToSequence(Regex(",")).toList())
                println("ABC" matches Regex("abc", setOf(RegexOption.IGNORE_CASE)))
                println(Regex.fromLiteral("a.b").matches("a.b")); println(Regex.escapeReplacement("$1"))
                println(Regex("a").find("aa")!!.next()!!.value); println(Regex("a").findAll("bbb").firstOrNull())
                try { Regex("[") } catch (e: IllegalArgumentException) { println("pattern") }
                try { Regex("a").find("a", -1) } catch (e: IndexOutOfBoundsException) { println("index") }
                try { Regex(",").split("a", -1) } catch (e: IllegalArgumentException) { println("split") }
                try { "abc".windowed(0) } catch (e: IllegalArgumentException) { println("window") }
                try { "abc".windowed(1, step = 0) } catch (e: IllegalArgumentException) { println("step") }
            }
            """#, expected: "[0, 1, 2]\n0\n1\n0\n1\n[, a, a, ]\n-a-a-\n[aa:0:1, :2:1]\n3\nnull\n\na\na/\n[a, ]\naabb\n$1$1\n0\n[A, C]\n3\nA\n4\nlimit\ninput\n[a, b,c]\n[a, b,c]\n[a, b, ]\ntrue\ntrue\n\\$1\na\nnull\npattern\nindex\nsplit\nwindow\nstep\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m19InlineCallbacksSuspendAndFinally(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11(#"""
            import kotlin.coroutines.*
            class Gate {
                var pending: Continuation<String>? = null
                suspend fun await(): String = suspendCoroutine { pending = it }
                fun release(value: String) { pending!!.resume(value) }
            }
            class Sink: Continuation<String> {
                override val context: CoroutineContext get() = EmptyCoroutineContext
                override fun resumeWith(result: Result<String>) { println(result.getOrThrow()) }
            }
            suspend fun work(gate: Gate): String = buildString {
                "ab".forEach { append(it); append(gate.await()) }
            }
            inline fun shadow(action: StringBuilder.() -> Unit): String = buildString {
                if (true) { val action: StringBuilder.() -> Unit = { append("inner") }; this.action() }
                this.action()
            }
            fun early(): String {
                try { return buildString { "ab".filter { if (it == 'b') return "early"; true }; append("bad") } }
                finally { println("finally") }
            }
            fun main() {
                println(shadow { append("outer") }); println(early()); val gate = Gate(); val job: suspend () -> String = { work(gate) }
                job.startCoroutine(Sink()); println("pause1"); gate.release("1"); println("pause2"); gate.release("2")
                val action: StringBuilder.() -> Unit = { append("captured") }; println(buildString(action))
                val mapper: (Char) -> Int = { it.code }; println("ab".map(mapper))
                println(buildString { "ab".forEachIndexed { i, c -> append(i); append(c) } })
            }
            """#, expected: "innerouter\nfinally\nearly\npause1\npause2\na1b2\ncaptured\n[97, 98]\n0a1b\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [
        #"fun f(): String { return "abc".windowed(2) { return "bad" }.toString() }"#,
        #"fun f(): String { return "abc".chunked(2) { return "bad" }.toString() }"#,
        #"fun f(): String { return Regex("a").replace("a") { return "bad" } }"#,
        #"fun main() { val b = StringBuilder(); b.length = 2 }"#,
        #"fun main() { StringBuilder(capacity = 2) }"#,
        #"fun main() { StringBuilder().append(value = "x") }"#,
        #"fun main() { StringBuilder().setLength(newLength = 1) }"#,
        #"fun main() { StringBuilder().appendRange(null, 0, 1) }"#,
        #"fun main() { StringBuilder().insertRange(0, null, 0, 1) }"#,
        #"fun main() { val r: Regex? = null; r.matches("x") }"#,
        #"fun main() { println("abc".map { missing }) }"#,
        #"fun main() { println(Regex("a").find("a", unknown = 0)) }"#,
    ])
    func m19InvalidTextProgramsPreserveOutput(source: String) throws {
        try withWorkspace { root in
            let output = root.appendingPathComponent("hello.jar"), sentinel = Data("previous jar".utf8)
            try sentinel.write(to: output)
            let result = try compile(source, root: root, mode: .jvmJar)
            #expect(result.0 == 1, "\(source)")
            #expect(!result.1.contains { $0.code.hasPrefix("KSWIFTK-ICE") })
            #expect(try Data(contentsOf: output) == sentinel)
        }
    }

    @Test
    func m19JavaAndOfficialKotlinTextConsumers() throws {
        try withWorkspace { root in
            let result = try compile(#"""
            package api
            fun words(input: CharSequence): List<String> = Regex("[a-z]+").findAll(input).map { it.value.uppercase() }.toList()
            fun builder(): StringBuilder = StringBuilder("hello").append('界')
            fun pattern(): Regex = Regex("[0-9]+")
            inline fun change(text: String, transform: (Char) -> Char): String = buildString { text.forEach { append(transform(it)) } }
            fun filter(input: CharSequence, predicate: (Char) -> Boolean): CharSequence = input.filter(predicate)
            """#, root: root, mode: .jvmJar)
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let jar = root.appendingPathComponent("hello.jar").path, runtime = try m11Runtime()
            try #"""
            import api.*
            fun early(): String { change("x") { return "early" }; return "bad" }
            fun main() {
                println(words(StringBuilder("one two"))); println(builder()); println(pattern().matches("123"))
                println(change("ab") { if (it == 'a') 'A' else it }); println(early())
                println(filter(StringBuilder("abc")) { it != 'b' })
            }
            """#.write(to: root.appendingPathComponent("consumer.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["consumer.kt", "-cp", jar + ":" + runtime, "-d", "consumer.jar"], root: root)
            for cp in [jar + ":" + runtime, runtime + ":" + jar] {
                #expect(try java(["-cp", root.appendingPathComponent("consumer.jar").path + ":" + cp, "ConsumerKt"]).stdout == "[ONE, TWO]\nhello界\ntrue\nAb\nearly\nac\n")
            }
            try #"""
            public class JavaConsumer {
                public static void main(String[] args) {
                    System.out.println(api.HelloKt.words(new StringBuilder("one two")));
                    System.out.println(api.HelloKt.builder().append(42));
                    System.out.println(api.HelloKt.pattern().matches("123"));
                }
            }
            """#.write(to: root.appendingPathComponent("JavaConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", jar + ":" + runtime, "JavaConsumer.java"], root: root)
            #expect(try java(["-cp", root.path + ":" + jar + ":" + runtime, "JavaConsumer"]).stdout == "[ONE, TWO]\nhello界42\ntrue\n")
        }
    }

}
#endif
