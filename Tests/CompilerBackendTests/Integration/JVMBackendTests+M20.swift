#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m20PairsGroupingAssociationsAndZip(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11(#"""
            fun main() {
                println(listOf(1, 2).zip(listOf("a", "b")).map { (a, b) -> "$a$b" });
                println(listOf(1) zip listOf(2)); println((sequenceOf(1) zip sequenceOf(2)).toList())
                val p = "a" to 1; println(p); println(p.first); println(p.second); val (a, b) = p; println("$a:$b")
                println(p == Pair("a", 1)); println(p.copy(second = 2)); println(listOf(p).joinToString())
                val words = listOf("a", "bb", "c", "dd")
                println(words.groupBy { it.length }); println(words.groupBy({ it.length }) { it.uppercase() })
                println(words.associate { it.length to it }); println(words.associateBy { it.length })
                println(words.associateBy({ it.length }) { it.uppercase() }); println(words.associateWith { it.length })
                val (yes, no) = words.partition { it.length == 1 }; println(yes); println(no)
                println(words.zip(listOf(1, 2))); println(words.zip(arrayOf(1, 2)) { x, y -> "$x$y" })
                println(words.zipWithNext()); println(words.zipWithNext { x, y -> x + y })
                println(listOf("a", "b", "a").associateWith { if (it == "a") null else 2 })
                println(words.groupBy { if (it.length == 1) null else 2 })
                println(listOf("b" to 1, "a" to 2, "b" to 3).toMap())
                println(words.joinToString(separator = "/", prefix = "[", postfix = "]", limit = 2) { it.uppercase() })
                println(emptyList<String>().joinToString()); println(words.take(2)); println(words.drop(2))
                println(listOf(3, 1, 2, 1).distinct().sorted()); println(words.sortedBy { it.length })
                println(words.asSequence().zip(sequenceOf(1, 2)).toList())
            }
            """#, expected: "[1a, 2b]\n[(1, 2)]\n[(1, 2)]\n(a, 1)\na\n1\na:1\ntrue\n(a, 2)\n(a, 1)\n{1=[a, c], 2=[bb, dd]}\n{1=[A, C], 2=[BB, DD]}\n{1=c, 2=dd}\n{1=c, 2=dd}\n{1=C, 2=DD}\n{a=1, bb=2, c=1, dd=2}\n[a, c]\n[bb, dd]\n[(a, 1), (bb, 2)]\n[a1, bb2]\n[(a, bb), (bb, c), (c, dd)]\n[abb, bbc, cdd]\n{a=null, b=2}\n{null=[a, c], 2=[bb, dd]}\n{b=3, a=2}\n[A/BB/...]\n\n[a, bb]\n[c, dd]\n[1, 2, 3]\n[a, c, bb, dd]\n[(a, 1), (bb, 2)]\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m20LazySequencesAndTerminals(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11(#"""
            fun main() {
                var calls = 0
                val s = generateSequence(1) { if (it < 5) it + 1 else null }.map { calls++; it * 2 }.filter { it > 2 }.onEach { println("seen$it") }
                println(calls); println(s.drop(1).take(2).joinToString()); println(calls)
                println(s.take(0).toList()); println(calls)
                println(sequenceOf(3, 1, 3, 2).distinct().sorted().toList())
                println(sequenceOf("a", "bb", "c").groupBy { it.length })
                println(sequenceOf(1, 2, 3).associate { it to "v$it" })
                println(sequenceOf(1, 2, 3).partition { it > 1 })
                println(sequenceOf(1, 2, 3).zipWithNext { a, b -> a + b }.toList())
                println(sequenceOf(1, 2).flatMap { sequenceOf(it, it) }.toList())
                println(sequenceOf(1, 2, 3).mapIndexed { i, n -> i + n }.toList())
                println(sequenceOf(1, 2, 3).mapNotNull { if (it == 2) null else it }.toList())
                println(sequenceOf<Int?>(null, 1, null).filterNotNull().toList())
                println(sequenceOf(1, 2, 3).takeWhile { it < 3 }.toList())
                println(sequenceOf(1, 2, 3).dropWhile { it < 2 }.toList())
                println(sequenceOf(1, 2, 3).fold(0) { a, b -> a + b })
                println(sequenceOf(1, 2, 3).any { it == 2 }); println(sequenceOf(1, 2).all { it > 0 })
                println(sequenceOf(1, 2, 3).first { it > 1 }); println(emptySequence<Int>().firstOrNull())
                println(sequenceOf(1, 2, 3).chunked(2).toList()); println(sequenceOf(1, 2, 3).windowed(2, partialWindows = true).toList())
                var n = 0; val once = generateSequence { if (n < 2) ++n else null }; println(once.toList())
                try { once.toList() } catch (e: IllegalStateException) { println("once") }
                val iterator = listOf(4, 5).iterator(); val single = iterator.asSequence(); println(single.toList())
                try { single.toList() } catch (e: IllegalStateException) { println("iterator") }
                try { sequenceOf(1).take(-1) } catch (e: IllegalArgumentException) { println("take") }
                println(sequenceOf(1, 2, 1).distinctBy { it % 2 }.toList())
            }
            """#, expected: "0\nseen4\nseen6\nseen8\n6, 8\n4\n[]\n4\n[1, 2, 3]\n{1=[a, c], 2=[bb]}\n{1=v1, 2=v2, 3=v3}\n([2, 3], [1])\n[3, 5]\n[1, 1, 2, 2]\n[1, 3, 5]\n[1, 3]\n[1]\n[1, 2]\n[2, 3]\n6\ntrue\ntrue\n2\nnull\n[[1, 2], [3]]\n[[1, 2], [2, 3], [3]]\n[1, 2]\nonce\n[4, 5]\niterator\ntake\n[1, 2]\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m20ArraysTextAndBoxedValues(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11(#"""
            fun main() {
                println(arrayOf("a", "bb", "c").groupBy { it.length })
                println(intArrayOf(1, 2, 3).associate { it to it * 2 })
                println(charArrayOf('a', 'b').zip(listOf(1, 2)))
                println(uintArrayOf(0u, UInt.MAX_VALUE, 1u).groupBy { it > 0u })
                println(ubyteArrayOf(0u, 255u).associateWith { it.toInt() })
                println(ushortArrayOf(0u, 65535u).partition { it > 0u })
                val chars: CharSequence = StringBuilder("abcd")
                val parts = chars.partition { it < 'c' }; println(parts); println(parts.first.javaClass.name)
                val strings = "abcd".partition { it < 'c' }; println(strings); println(strings.first.javaClass.name)
                println("abca".groupBy { it }); println("abc".associate { it to it.code })
                println("abc".zip("XY")); println("abc".zip("XY") { a, b -> "$a$b" })
                println(intArrayOf(1, 2, 3).joinToString()); println(arrayOf("a", "b").joinToString { it.uppercase() })
                val array = uintArrayOf(1u, UInt.MAX_VALUE); val sequence = array.asSequence(); array[0] = 2u
                println(sequence.toList()); println(array.joinToString())
                println("a界".asSequence().map { it.code }.joinToString())
                println(arrayOf(1, 2).asSequence().toList()); println(charArrayOf('a', 'b').asSequence().toList())
                val elements = arrayOf(1, 2); val seq = sequenceOf(*elements, 3); elements[0] = 9; println(seq.toList())
            }
            """#, expected: "{1=[a, c], 2=[bb]}\n{1=2, 2=4, 3=6}\n[(a, 1), (b, 2)]\n{false=[0], true=[4294967295, 1]}\n{0=0, 255=255}\n([65535], [0])\n(ab, cd)\njava.lang.StringBuilder\n(ab, cd)\njava.lang.String\n{a=[a, a], b=[b], c=[c]}\n{a=97, b=98, c=99}\n[(a, X), (b, Y)]\n[aX, bY]\n1, 2, 3\nA, B\n[2, 4294967295]\n2, 4294967295\n97, 30028\n[1, 2]\n[a, b]\n[1, 2, 3]\n", mode: mode, root: root)
        }
    }
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m20SequenceEvaluationOrderAndBounds(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11(#"""
            class Key(val n: Int) { override fun hashCode(): Int { println("hash$n"); return n } }
            fun second(): Pair<Key, Int> { println("second"); return Key(2) to 2 }
            fun element(): Int { println("left"); return 1 }
            fun container(): Sequence<Int> { println("right"); return sequenceOf(1, 2) }
            fun argument(n: Int): String { println("arg$n"); return "[$n]" }
            fun main() {
                println(element() in container()); println(3 !in sequenceOf(1, 2)); println(1 in listOf(1, 2))
                println(1.to(that = 2))
                println(setOf("a", "b", "a")); println(mapOf(pair = "a" to 1)); println(listOf(element = 1)); println(setOf(element = 2)); println(sequenceOf(element = 3).toList())
                val pairs = arrayOf("a" to 1, "b" to 2); println(mapOf(*pairs)); println(mutableMapOf(pairs = pairs))
                println(mapOf(Key(9) to 9).size); println(setOf(Key(8)).size)
                val first = Key(1) to 1; println(mapOf(first, second()).size)
                var read = 0; println(sequenceOf(1, 2, 3).onEach { read++ }.asIterable().zip(arrayOf(9))); println(read)
                println(sequenceOf("NaN".toDouble(), 1.0).minOrNull()); println(sequenceOf("NaN".toFloat(), 1.0f).minOrNull())
                println(sequenceOf("NaN".toDouble(), 1.0).maxOrNull()); println(sequenceOf("NaN".toFloat(), 1.0f).maxOrNull())
                var consumed = 0; var transformed = 0
                val seq = sequenceOf(1, 2, 3).onEach { consumed++ }
                println(seq.joinToString(limit = 1) { transformed++; "v$it" }); println("$consumed/$transformed")
                consumed = 0; transformed = 0
                println(seq.joinToString(limit = 0) { transformed++; "v$it" }); println("$consumed/$transformed")
                println(sequenceOf(1, 2).joinToString(postfix = argument(1), prefix = argument(2), separator = argument(3)))
                var left = 0; var right = 0
                val xs = sequenceOf(1, 2, 3).map { left++; it }.asIterable()
                val ys = sequenceOf(4).map { right++; it }.asIterable()
                println(xs.zip(ys)); println("$left/$right")
                val values = mutableListOf(1, 2); val view = values.asSequence(); values.add(3); println(view.toList())
                val empty = emptySequence<Int>(); println(empty.toList()); println(sequenceOf<Int>().toList())
                println(sequenceOf(3, 1, 2).sortedDescending().toList())
                println(sequenceOf("bbb", "a", "cc").sortedBy { it.length }.toList())
                println(sequenceOf("bbb", "a", "cc").sortedByDescending { it.length }.toList())
                println(sequenceOf(1, 2).flatMap { listOf(it, it) }.toList())
                println(sequenceOf(listOf(1, 2), listOf(3)).flatten().toList())
                println(sequenceOf(sequenceOf(1), sequenceOf(2)).flatten().toList())
                println(sequenceOf(1, 2, 3).filterIndexed { i, n -> i % 2 == 0 }.toList())
                println(sequenceOf(1, 2, 3).mapIndexedNotNull { i, n -> if (i == 1) null else n }.toList())
                println(sequenceOf(3, 1, 2).minOrNull()); println(sequenceOf(3, 1, 2).maxOrNull())
                println(sequenceOf(1, 2, 3).last()); println(empty.lastOrNull()); println(sequenceOf(1).single())
                println(sequenceOf(1, 2).singleOrNull()); println(sequenceOf(1, 2).elementAt(1)); println(empty.elementAtOrNull(0))
                println(sequenceOf("a" to 1, "a" to 2).toMap())
                println(sequenceOf(1, 2, 1).toMutableSet()); println(sequenceOf(1, 2).count())
                try { empty.first() } catch (e: NoSuchElementException) { println("empty") }
                try { sequenceOf(1, 2).single() } catch (e: IllegalArgumentException) { println("many") }
                try { sequenceOf(1).drop(-1) } catch (e: IllegalArgumentException) { println("drop") }
                try { sequenceOf(1).windowed(0) } catch (e: IllegalArgumentException) { println("window") }
                var seed = 0; val generator = generateSequence({ seed++; 1 }) { if (it < 2) it + 1 else null }
                println(seed); println(generator.toList()); println(generator.toList()); println(seed)
            }
            """#, expected: "right\nleft\ntrue\ntrue\ntrue\n(1, 2)\n[a, b]\n{a=1}\n[1]\n[2]\n[3]\n{a=1, b=2}\n{a=1, b=2}\n1\n1\nsecond\nhash1\nhash2\n2\n[(1, 9)]\n2\nNaN\nNaN\nNaN\nNaN\nv1, ...\n2/1\n...\n1/0\narg1\narg2\narg3\n[2]1[3]2[1]\n[(1, 4)]\n1/1\n[1, 2, 3]\n[]\n[]\n[3, 2, 1]\n[a, cc, bbb]\n[bbb, cc, a]\n[1, 1, 2, 2]\n[1, 2, 3]\n[1, 2]\n[1, 3]\n[1, 3]\n1\n3\n3\nnull\n1\nnull\n2\nnull\n{a=2}\n[1, 2]\n2\nempty\nmany\ndrop\nwindow\n0\n[1, 2]\n[1, 2]\n2\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m20InlineControlFlowSuspensionAndCapture(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11(#"""
            import kotlin.coroutines.*
            class Gate {
                var pending: Continuation<Int>? = null
                suspend fun await(): Int = suspendCoroutine { pending = it }
                fun release(value: Int) { pending!!.resume(value) }
            }
            class Sink: Continuation<Map<Int, String>> {
                override val context: CoroutineContext get() = EmptyCoroutineContext
                override fun resumeWith(result: Result<Map<Int, String>>) { println(result.getOrThrow()) }
            }
            suspend fun work(gate: Gate): Map<Int, String> = listOf("a", "b").associate { gate.await() to it }
            fun early(): Int { try { listOf(1, 2, 3).groupBy { if (it == 2) return 42; it }; return 0 } finally { println("finally") } }
            fun terminal(): Int { sequenceOf(1, 2, 3).forEach { if (it == 2) return 43 }; return 0 }
            fun arrayEarly(): Int { intArrayOf(1, 2).associate { if (it == 2) return 44; it to it }; return 0 }
            fun main() {
                println(early()); println(terminal()); println(arrayEarly())
                val gate = Gate(); val job: suspend () -> Map<Int, String> = { work(gate) }
                job.startCoroutine(Sink()); println("pause1"); gate.release(7); println("pause2"); gate.release(8)
                var total = 0; val captured = sequenceOf(1, 2).map { total += it; total }
                println(total); println(captured.toList()); println(captured.toList()); println(total)
                val selector: (String) -> Int = { it.length }; println(listOf("a", "bb").groupBy(selector))
            }
            """#, expected: "finally\n42\n43\n44\npause1\npause2\n{7=a, 8=b}\n0\n[1, 3]\n[4, 6]\n6\n{1=[a], 2=[bb]}\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [
        #"fun f(): Int { sequenceOf(1).map { return 1 }; return 0 }"#,
        #"fun f(): Int { listOf(1).joinToString { return 1 }; return 0 }"#,
        #"fun f(): Int { sequenceOf(1).onEach { return 1 }; return 0 }"#,
        #"fun f(): Int { sequenceOf(1).sortedBy { return 1 }; return 0 }"#,
        #"fun main() { listOf(1).groupBy { missing } }"#,
        #"fun main() { listOf(1).zip(42) }"#,
        #"fun main() { val values: Set<String> = setOf(1) }"#,
        #"fun main() { val values: Map<String, Int> = mutableMapOf(1 to 2) }"#,
        #"fun main() { 1.to(other = 2) }"#,
        #"fun main() { "abc".joinToString() }"#,
        #"suspend fun await(): Int = 1; suspend fun work() { sequenceOf(1).map { await() } }"#,
        #"fun main() { listOf(1).associate { it } }"#,
        #"fun main() { listOf(1).joinToString(unknown = 1) }"#,
        #"fun main() { generateSequence<Int>("bad") { it } }"#,
        #"fun main() { sequenceOf(Any()).sorted() }"#,
        #"fun main() { val x: Sequence<Int>? = null; x.toList() }"#,
    ])
    func m20InvalidCollectionProgramsPreserveOutput(source: String) throws {
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
    func m20JavaAndOfficialKotlinCollectionConsumers() throws {
        try withWorkspace { root in
            let result = try compile(#"""
            package api
            fun pair(): Pair<String, Int> = "answer" to 42
            fun grouped(input: List<String>): Map<Int, List<String>> = input.groupBy { it.length }
            fun pipeline(input: List<Int>): Sequence<Int> = input.asSequence().map { it * 2 }.filter { it > 2 }
            inline fun <K, V> associate(input: List<String>, transform: (String) -> Pair<K, V>): Map<K, V> = input.associate(transform)
            inline fun terminal(input: Sequence<Int>, action: (Int) -> Unit) { input.forEach(action) }
            """#, root: root, mode: .jvmJar)
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let jar = root.appendingPathComponent("hello.jar").path, runtime = try m11Runtime()
            try #"""
            import api.*
            fun early(): Int { associate<Int, String>(listOf("x")) { return 42 }; return 0 }
            fun stop(): Int { terminal(sequenceOf(1, 2)) { if (it == 2) return 43 }; return 0 }
            fun main() {
                val (a, b) = pair(); println("$a:$b"); println(grouped(listOf("a", "bb", "c")))
                println(pipeline(listOf(1, 2, 3)).joinToString())
                println(associate(listOf("a", "bb")) { it.length to it.uppercase() }); println(early()); println(stop())
            }
            """#.write(to: root.appendingPathComponent("consumer.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["consumer.kt", "-cp", jar + ":" + runtime, "-d", "consumer.jar"], root: root)
            for cp in [jar + ":" + runtime, runtime + ":" + jar] {
                #expect(try java(["-cp", root.appendingPathComponent("consumer.jar").path + ":" + cp, "ConsumerKt"]).stdout == "answer:42\n{1=[a, c], 2=[bb]}\n4, 6\n{1=A, 2=BB}\n42\n43\n")
            }
            try #"""
            import java.util.Arrays;
            public class JavaConsumer {
                public static void main(String[] args) {
                    kotlin.Pair<String, Integer> pair = api.HelloKt.pair();
                    System.out.println(pair.getFirst() + ":" + pair.getSecond());
                    System.out.println(api.HelloKt.grouped(Arrays.asList("a", "bb", "c")));
                    System.out.println(kotlin.sequences.SequencesKt.toList(api.HelloKt.pipeline(Arrays.asList(1, 2, 3))));
                }
            }
            """#.write(to: root.appendingPathComponent("JavaConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", jar + ":" + runtime, "JavaConsumer.java"], root: root)
            #expect(try java(["-cp", root.path + ":" + jar + ":" + runtime, "JavaConsumer"]).stdout == "answer:42\n{1=[a, c], 2=[bb]}\n[4, 6]\n")
        }
    }

}
#endif
