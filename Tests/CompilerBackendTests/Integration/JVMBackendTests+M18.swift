#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func kuu2911StringSliceAndCodePointAt(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11(#"""
            fun main() {
                println("kotlin".slice(0..2))
                println("kotlin".slice(listOf(0, 2)))
                println("a".codePointAt(0))
            }
            """#, expected: "kot\nkt\n97\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m18ConcatenationTemplatesAndEvaluationOrder(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11(#"""
            class Text(val n: Int) {
                override fun toString(): String { println("str$n"); return "T$n" }
            }
            fun make(n: Int): Text { println("arg$n"); return Text(n) }
            fun effect() { println("effect") }
            @JvmInline value class U(val value: UInt)
            fun <T> render(value: T): String = "<$value>"
            fun main() {
                val name = "界"; val n = 42
                println("hello $name: ${n + 1}")
                println("" + make(1) + make(2))
                println("${make(3)}:${make(4)}")
                println("unit=${effect()}")
                val missing: String? = null; println(missing + "x"); println("$missing")
                println("$n/${1.5}/${true}/${'界'}/${255u.toUByte()}/${ULong.MAX_VALUE}")
                println(render(U(4294967295u)))
                println("escape\n\t\"\$name")
                println("${"nested=$n"}")
                val chars = charArrayOf('A', 'B'); val ints = intArrayOf(1, 2)
                println("$chars".startsWith("[C@")); println(("" + ints).startsWith("[I@"))
                println('A' + "BC")
                var x = 1; val text = "${x++}/${x++}/$x"; println(text)
            }
            """#, expected: "hello 界: 43\narg1\nstr1\narg2\nstr2\nT1T2\narg3\nstr3\narg4\nstr4\nT3:T4\neffect\nunit=kotlin.Unit\nnullx\nnull\n42/1.5/true/界/255/18446744073709551615\n<U(value=4294967295)>\nescape\n\t\"$name\nnested=42\ntrue\ntrue\nABC\n1/2/3\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m18TextOperationsUnicodeAndDefaults(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11(#"""
            fun main() {
                val text = "A😀界"; println(text.length); println(text.lastIndex)
                println(text[1].code); println(text[2].code); println(text.get(3))
                for (c in "界A") { println(c.code) }
                val sequence: CharSequence = "abc"; println(sequence.length); println(sequence[1]); println(sequence.subSequence(1, 3))
                println("hello".substring(1)); println("hello".substring(endIndex = 4, startIndex = 1))
                println("hello".take(2)); println("hello".drop(2)); println("hello".takeLast(2)); println("hello".dropLast(2))
                println("\u00a0\u202f hi \t".trim()); println("xyhelloxy".trim('x', 'y'))
                println("  hi ".trimStart()); println(" hi  ".trimEnd())
                println("\u00a0\u202f".isBlank()); println("".isEmpty()); println("x".isNotEmpty()); println("x".isNotBlank())
                println("Straße".uppercase()); println("İΣ".lowercase()); println("A😀B".reversed())
                println("AbCd".startsWith("ab", ignoreCase = true)); println("AbCd".endsWith('D', true))
                println("AbCd".contains("BC", true)); println("AbCd".indexOf("bc", ignoreCase = true))
                println("abc".lastIndexOf("")); println("ababa".lastIndexOf('a', startIndex = 3))
                println("abc".replace("", "-")); println("AaA".replace('a', 'x', true)); println("AaA".replaceFirst("a", "x", true))
                println("a,,".split(",")); println("a;b,c".split(';', ',')); println("a;b,c".split(*arrayOf(";", ","), limit = 2))
                println("abc".split("")); println("x".repeat(3)); println("x".padStart(3, '0')); println("x".padEnd(3))
                println("a:b:c".substringBeforeLast(':')); println("a:b:c".substringAfter(':')); println("abc".substringBefore(':', "missing"))
                println("<abc>".removePrefix("<")); println("<abc>".removeSuffix(">")); println("<abc>".removeSurrounding("<", ">"))
                println("ab" < "ac"); println("ABC".equals("abc", true)); println("abc".compareTo("ABC", true))
                println("".firstOrNull()); println("abc".first()); println("abc".last())
                val chars = "A界Z".toCharArray(1, 3); println(chars.concatToString()); println(chars.concatToString(0, 1))
                val missing: String? = null; println(missing.orEmpty()); println(missing.isNullOrEmpty()); println(missing.isNullOrBlank()); println(missing.toString())
            }
            """#, expected: "4\n3\n55357\n56832\n界\n30028\n65\n3\nb\nbc\nello\nell\nhe\nllo\nlo\nhel\nhi\nhello\nhi \n hi\ntrue\ntrue\ntrue\ntrue\nSTRASSE\ni̇ς\nB😀A\ntrue\ntrue\ntrue\n1\n2\n2\n-a-b-c-\nxxx\nxaA\n[a, , ]\n[a, b, c]\n[a, b,c]\n[, a, b, c, ]\nxxx\n00x\nx  \na:b\nb:c\nmissing\nabc>\n<abc\nabc\ntrue\ntrue\n0\nnull\na\nc\n界Z\n界\n\ntrue\ntrue\nnull\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m18StringNumericConversionsAndFailures(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11(#"""
            fun main() {
                println("7f".toByte(16)); println("32767".toShort()); println("ff".toInt(16)); println("9223372036854775807".toLong())
                println("１２".toInt()); println("-0.5".toDouble()); println("1.5".toFloat())
                println("2147483648".toIntOrNull()); println("bad".toLongOrNull()); println("128".toByteOrNull()); println("7fff".toShortOrNull(16))
                println("NaN".toDoubleOrNull()); println("bad".toFloatOrNull()); println("TRUE".toBoolean()); println("true".toBooleanStrict())
                println("TRUE".toBooleanStrictOrNull()); val missing: String? = null; println(missing.toBoolean())
                try { "1".toInt(1) } catch (e: IllegalArgumentException) { println("radix") }
                try { "overflow".toInt() } catch (e: NumberFormatException) { println("number") }
                try { "x".repeat(-1) } catch (e: IllegalArgumentException) { println("repeat") }
                try { "x".take(-1) } catch (e: IllegalArgumentException) { println("take") }
                try { println("x"[1]) } catch (e: IndexOutOfBoundsException) { println("index") }
                try { println("x".substring(2)) } catch (e: IndexOutOfBoundsException) { println("substring") }
                try { "x".split(",", limit = -1) } catch (e: IllegalArgumentException) { println("limit") }
            }
            """#, expected: "127\n32767\n255\n9223372036854775807\n12\n-0.5\n1.5\nnull\nnull\nnull\n32767\nNaN\nnull\ntrue\ntrue\nnull\nfalse\nradix\nnumber\nrepeat\ntake\nindex\nsubstring\nlimit\n", mode: mode, root: root)
        }
    }
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m18StringMutationTemplatesCaptureAndEscapes(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11(#"""
            class Box {
                var text = "A"
                    get() { println("get"); return field }
                    set(value) { println("set:$value"); field = value }
                fun fieldAdd(value: Any?) { fieldText += value }
                var fieldText = "F"
            }
            fun box(value: Box): Box { println("receiver"); return value }
            fun rhs(value: Box): Int { println("rhs"); value.text = "changed"; return 2 }
            fun effect() { println("unit") }
            fun index(n: Int): Int { println("index$n"); return n }
            fun mutate(array: Array<String>): Boolean { array[0] = ";"; return false }
            fun mutateChar(array: CharArray): Char { array[0] = 'y'; return 'z' }
            fun mutateString(array: Array<String>): String { array[0] = ";"; return "|" }
            class Bad { override fun toString(): String { throw IllegalStateException("render") } }
            class Custom { operator fun plus(n: Int): String = "custom:$n" }
            fun early(): String { return "before${return "early"}after" }
            fun short(flag: Boolean): String { return "${flag && (return "early")}" }
            fun shortOr(flag: Boolean): String { return "${flag || (return "early")}" }
            fun loop(flag: Boolean): String {
                do { if (flag) break } while ("${return "early"}" == "x")
                return "done"
            }
            fun fromBody(): String { do { return "body" } while ("${throw IllegalStateException("bad")}" == "x") }
            fun choose(flag: Boolean): String {
                val value = when { flag -> "chosen"; ("${return "early"}" == "x") -> "bad"; else -> "bad" }
                return "when:$value"
            }
            fun chooseMulti(value: String): String {
                val result = when (value) { "a", "${return "early"}" -> "chosen"; else -> "bad" }
                return "multi:$result"
            }
            fun main() {
                var text = "x"; text += 1; text += null; text += effect(); println(text)
                val box = Box(); box(box).text += rhs(box); println(box.text)
                box.fieldAdd(3); println(box.fieldText)
                val array = arrayOf("a"); array[0] += 2; println(array[0])
                val list = mutableListOf("l"); list[0] += true; println(list[0])
                val map = mutableMapOf(1 to "m"); map[1] += 3; map[2] += "x"; println(map[1]); println(map[2])
                var captured = "C"; val read = { captured += "!"; "$captured" }; println(read()); println(read())
                val obj = object { fun show(): String = "object:$captured" }; println(obj.show())
                try { println("${Bad()}${effect()}") } catch (e: IllegalStateException) { println(e.message) }
                try { println("${throw IllegalStateException("throw")}bad") } catch (e: IllegalStateException) { println(e.message) }
                println(early()); println(short(false)); println(short(true)); println(shortOr(true)); println(shortOr(false)); println(loop(true)); println(loop(false)); println(fromBody()); println(choose(true)); println(choose(false)); println(chooseMulti("a")); println(chooseMulti("b")); println(Custom() + 2)
                val any: Any? = "x"; println("x".equals(any)); println("x".equals(null)); println("x".equals("x"))
                println("hello".substring(endIndex = index(4), startIndex = index(1)))
                val delimiters = arrayOf(",")
                println("a,b;c".split(*delimiters, ignoreCase = mutate(delimiters)))
                println("a,b;c".split(delimiters = arrayOf(";"), limit = 2))
                val named = arrayOf(",")
                println("a,b;c".split(delimiters = named, ignoreCase = mutate(named)))
                val chars = charArrayOf('x'); println("xyz".trim(*chars, mutateChar(chars)))
                val strings = arrayOf(","); println("a,b;c|d".split(*strings, mutateString(strings)))
            }
            """#, expected: "unit\nx1nullkotlin.Unit\nreceiver\nget\nrhs\nset:changed\nset:A2\nget\nA2\nF3\na2\nltrue\nm3\nnullx\nC!\nC!!\nobject:C!!\nrender\nthrow\nearly\nfalse\nearly\ntrue\nearly\ndone\nearly\nbody\nwhen:chosen\nearly\nmulti:chosen\nearly\ncustom:2\ntrue\nfalse\ntrue\nindex4\nindex1\nell\n[a, b;c]\n[a,b, c]\n[a, b;c]\nx\n[a, b;c, d]\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m18RawTemplatesAndUTF16(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11(###"""
            fun main() {
                val name = "界"; val n = 42
                println("""
                    hello $name
                    value=${n + 1}
                """.trimIndent())
                println("""|a
                    |b=$n""".trimMargin())
                println($$"""$name $$name $${n + 1}""")
                val high = "\uD83D"; val text = "${high}\uDE00"
                println(high.length); println(text.length); println(text[0].code); println(text[1].code)
                println(text.uppercase()[0].code)
                println("\u0000x".length); println("${"\u0000"}x"[0].code)
                println("${if (true) "yes" else "no"}")
                println("quoted \"$name\"")
            }
            """###, expected: "hello 界\nvalue=43\na\nb=42\n$name 界 43\n1\n2\n55357\n56832\n55357\n2\n0\nyes\nquoted \"界\"\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m18TemplatesPreserveSuspensionAndReifiedCaptures(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11(#"""
            import kotlin.coroutines.*
            class Text(val n: Int) {
                override fun toString(): String { println("str$n"); return "T$n" }
            }
            fun make(n: Int): Text { println("arg$n"); return Text(n) }
            class Gate {
                var pending: Continuation<Text>? = null
                suspend fun await(): Text = suspendCoroutine { pending = it }
                fun release() { pending!!.resume(Text(2)) }
            }
            inline fun <reified T> renderer(): (Any?) -> String = { "${T::class.simpleName}:${it is T}:$it" }
            fun main() {
                val gate = Gate()
                val work: suspend () -> String = { "${make(1)}:${gate.await()}:${make(3)}" }
                work.startCoroutine(object: Continuation<String> {
                    override val context: CoroutineContext = EmptyCoroutineContext
                    override fun resumeWith(result: Result<String>) { println(result.getOrThrow()) }
                })
                println("paused"); gate.release()
                println(renderer<UInt>()(4294967295u))
            }
            """#, expected: "arg1\nstr1\npaused\nstr2\narg3\nstr3\nT1:T2:T3\nUInt:true:4294967295\n", mode: mode, root: root)
        }
    }

    @Test
    func m18JavaAndOfficialKotlinStringConsumers() throws {
        try withWorkspace { root in
            let result = try compile(#"""
            package api
            import kotlin.coroutines.*
            const val GREETING: String = "hel${"lo"}"
            fun greet(name: String?, n: Int = 2): String = "${name.orEmpty().uppercase()}:${"x".repeat(n)}"
            class Renderer(val prefix: String) { fun render(value: Any?): String = "$prefix:$value" }
            inline fun decorate(value: String, action: (String) -> String): String = "[${action(value).trim()}]"
            inline fun <reified T> describe(value: T): String = "${T::class.simpleName}:$value"
            class Gate {
                var pending: Continuation<String>? = null
                suspend fun await(): String = suspendCoroutine { pending = it }
                fun release(value: String) { pending!!.resume(value) }
            }
            inline suspend fun delayed(gate: Gate): String = "before:${gate.await()}:after"
            fun read(sequence: CharSequence, action: () -> Unit): String {
                var result = ""
                for (c in sequence) { result += c; action() }
                return result
            }
            """#, root: root, mode: .jvmJar)
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let jar = root.appendingPathComponent("hello.jar").path, runtime = try m11Runtime()
            try #"""
            package consumer
            import api.*
            import kotlin.coroutines.*
            fun early(): String { decorate("x") { return "early:$it" }; return "bad" }
            fun main() {
                println(GREETING); println(greet("界")); println(greet(null, 0)); println(Renderer("value").render(4294967295u))
                println(decorate(" x ") { it.uppercase() }); println(early()); println(describe(255u.toUByte()))
                val gate = Gate()
                val work: suspend () -> String = { delayed(gate) }
                work.startCoroutine(object: Continuation<String> {
                    override val context: CoroutineContext = EmptyCoroutineContext
                    override fun resumeWith(result: Result<String>) { println(result.getOrThrow()) }
                })
                println("paused"); gate.release("ready")
                val grow = StringBuilder("a")
                println(read(grow) { if (grow.length == 1) grow.append('b') })
                val shrink = StringBuilder("abc")
                println(read(shrink) { shrink.setLength(1) })
            }
            """#.write(to: root.appendingPathComponent("consumer.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["consumer.kt", "-cp", jar + ":" + runtime, "-d", "consumer.jar"], root: root)
            for cp in [jar + ":" + runtime, runtime + ":" + jar] {
                #expect(try java(["-cp", root.appendingPathComponent("consumer.jar").path + ":" + cp, "consumer.ConsumerKt"]).stdout == "hello\n界:xx\n:\nvalue:4294967295\n[X]\nearly:x\nUByte:255\npaused\nbefore:ready:after\nab\na\n")
            }
            try #"""
            public class JavaConsumer {
                public static void main(String[] args) {
                    System.out.println(api.HelloKt.GREETING);
                    System.out.println(api.HelloKt.greet("java", 3));
                    System.out.println(new api.Renderer("value").render(null));
                }
            }
            """#.write(to: root.appendingPathComponent("JavaConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", jar + ":" + runtime, "JavaConsumer.java"], root: root)
            #expect(try java(["-cp", root.path + ":" + jar + ":" + runtime, "JavaConsumer"]).stdout == "hello\nJAVA:xxx\nvalue:null\n")
        }
    }

    @Test(arguments: [
        #"fun main() { println("${missing}") }"#,
        #"fun main() { val s: String? = null; println(s.length) }"#,
        #"fun main() { "x"[0] = 'a' }"#,
        #"fun main() { println("x".substring("bad")) }"#,
        #"fun main() { println("x".replace("a")) }"#,
        #"fun main() { println("x".substring(unknown = 1)) }"#,
        #"fun main() { println("x" + 1) trailing }"#,
        #"class Text: CharSequence { override val length: Int get() = 0; override fun get(index: Int): Char = 'a'; override fun subSequence(startIndex: Int, endIndex: Int): CharSequence = "" }"#,
    ])
    func m18InvalidTextProgramsPreserveOutput(source: String) throws {
        try withWorkspace { root in
            let output = root.appendingPathComponent("hello.jar"), sentinel = Data("previous jar".utf8)
            try sentinel.write(to: output)
            let result = try compile(source, root: root, mode: .jvmJar)
            #expect(result.0 == 1, "\(source)")
            #expect(!result.1.contains { $0.code.hasPrefix("KSWIFTK-ICE") })
            #expect(try Data(contentsOf: output) == sentinel)
        }
    }

}
#endif
