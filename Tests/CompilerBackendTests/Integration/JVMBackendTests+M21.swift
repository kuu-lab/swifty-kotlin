#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m21BuildersYieldAllAndLazyIteration(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11(#"""
            fun main() {
                val values = sequence { println("start"); yield(1); println("next"); yieldAll(listOf(2, 3)); yieldAll(sequenceOf(4)); yieldAll(listOf(5).iterator()); println("done") }
                println("created")
                val it = values.iterator(); println("iterator"); println(it.hasNext()); println(it.hasNext()); println(it.next()); println(it.next()); println(values.toList()); println(it.asSequence().toList())
                val empty = sequence<Int> { yieldAll(emptyList<Int>()); yieldAll(emptySequence<Int>()); yieldAll(emptyList<Int>().iterator()); println("empty"); yield(9) }
                println(empty.toList())
                val direct = iterator { yield("a"); yieldAll(sequenceOf("b", "c")) }
                println(direct.next()); println(direct.asSequence().joinToString()); println(direct.hasNext())
                try { direct.next() } catch (e: NoSuchElementException) { println("end") }
                println(sequence<Int> {}.toList())
                println(sequence<Int?>(block = { yield(null); yield(1); yieldAll(listOf(null, 2)) }).toList())
            }
            """#, expected: "created\niterator\nstart\ntrue\ntrue\n1\nnext\n2\nstart\nnext\ndone\n[1, 2, 3, 4, 5]\ndone\n[3, 4, 5]\nempty\n[9]\na\nb, c\nfalse\nend\n[]\n[null, 1, null, 2]\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m21ControlFlowFinallyAndFailure(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11(#"""
            fun main() {
                var finished = 0
                val values = sequence { try { yield(1); yield(2) } finally { finished++; println("finally") } }
                println(values.first()); println(finished)
                val it = values.iterator(); println(it.next()); println(it.next()); println(finished); println(it.hasNext()); println(finished)
                val broken = iterator<Int> { try { yield(3); throw IllegalArgumentException("boom") } finally { println("failure-finally") } }
                println(broken.next())
                try { broken.hasNext() } catch (e: IllegalArgumentException) { println(e.message) }
                try { broken.hasNext() } catch (e: IllegalStateException) { println(e.message) }
                val caught = sequence {
                    try { yield(4); throw IllegalStateException("caught") }
                    catch (e: IllegalStateException) { println(e.message); yield(5) }
                    finally { println("caught-finally") }
                    for (n in 1..4) { if (n == 2) continue; if (n == 4) break; yield(n) }
                    return@sequence
                }
                println(caught.toList())
                var outerFinally = false
                val delegated = sequence<Int> { try { yieldAll(sequence<Int> { yield(8); throw IllegalStateException("delegate") }) } finally { outerFinally = true } }.iterator()
                println(delegated.next()); try { delegated.hasNext() } catch (e: IllegalStateException) { println(e.message) }; println(outerFinally)
                println(sequence<Int> { try { yield(6); return@sequence } finally { yield(7) } }.toList())
                var calls = 0
                val endless = sequence { var n = 0; while (true) { calls++; yield(n++) } }
                println(endless.take(3).toList()); println(calls)
            }
            """#, expected: "1\n0\n1\n2\n0\nfinally\nfalse\n1\n3\nfailure-finally\nboom\nIterator has failed.\ncaught\ncaught-finally\n[4, 5, 1, 3]\n8\ndelegate\nfalse\n[6, 7]\n[0, 1, 2]\n3\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m21CaptureGenericHelpersAndReceiverFunctions(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11(#"""
            import kotlin.sequences.*
            suspend fun <T> SequenceScope<T>.twice(value: T) { yield(value); this.yield(value) }
            inline fun action(block: () -> Unit) { block() }
            class Owner(val n: Int) {
                suspend fun SequenceScope<Int>.member() { twice(n); yield(n + 1) }
                fun values(): Sequence<Int> = sequence { member(); this.yield(this@Owner.n + 2) }
            }
            inline fun <reified T> selected(values: List<Any>): Sequence<T> = sequence { for (item in values) { if (item is T) yield(item) } }
            fun main() {
                println(Owner(3).values().toList())
                val f: suspend SequenceScope<Int>.() -> Unit = { yield(7) }
                println(sequence(block = f).toList()); println(iterator(block = f).asSequence().toList())
                println(sequence<Int> { f(); f(this); this.f() }.toList())
                var total = 10
                val shared = sequence { var local = 0; action { yield(total) }; listOf(1, 2).forEach { local += it; total++; yield(local + total) } }
                println(shared.toList()); println(shared.toList()); println(total)
                val left = shared.iterator(); val right = shared.iterator(); println(left.next()); println(right.next()); println(left.next()); println(right.next())
                println(selected<String>(listOf<Any>(1, "x", 2, "y")).toList())
                println(sequence<Long> { yield(4294967296L); yieldAll(listOf(9L)) }.toList())
                println(sequence<UInt> { yield(UInt.MAX_VALUE); yield(0u) }.toList())
                println(sequence<Char> { yield('界'); yieldAll("ab".asSequence()) }.joinToString())
            }
            """#, expected: "[3, 3, 4, 5]\n[7]\n[7]\n[7, 7, 7]\n[10, 12, 15]\n[12, 14, 17]\n14\n14\n14\n16\n17\n[x, y]\n[4294967296, 9]\n[4294967295, 0]\n界, a, b\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m21RestrictedReceiverTypesAndFunctionValues(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11(#"""
            import kotlin.sequences.*
            import kotlin.sequences.sequence
            import kotlin.sequences.iterator
            import kotlin.sequences.sequence as seq
            import kotlin.sequences.iterator as iter
            suspend fun <S: SequenceScope<Int>> S.genericYield() { yield(10) }
            suspend fun forward(f: suspend SequenceScope<Int>.() -> Unit, scope: SequenceScope<Int>) { f(scope) }
            suspend fun SequenceScope<Int>?.nullableSmart() { if (this != null) yield(2) }
            @JvmInline value class Id(val value: Int)
            fun main() {
                val f: suspend SequenceScope<Int>.() -> Unit = { yield(7) }
                val delegated: suspend SequenceScope<Int>.() -> Unit = { val alias = this; f(alias); this.f() }
                println(sequence(block = delegated).toList())
                println(sequence<Int> { nullableSmart(); genericYield() }.toList())
                val values = sequence { yieldAll(listOf(1, 2)); yieldAll(sequenceOf(3)) }; println(values.toList())
                println(iterator { yieldAll(listOf("x", "y")) }.asSequence().toList())
                println(seq { yieldAll(listOf(5, 6)) }.toList()); println(iter { yieldAll(listOf(7, 8)) }.asSequence().toList())
                println(kotlin.sequences.sequence { yieldAll(listOf(9)) }.toList()); println(kotlin.sequences.iterator { yieldAll(listOf(10)) }.asSequence().toList())
                println(sequence<Int> { buildString { yield(11); append("x") }; yield(12) }.toList())
                println(iter<Int> { yield(13); return@iter }.asSequence().toList())
                println(sequence<Id> { yield(Id(1)); yieldAll(listOf(Id(2))) }.map { it.value }.toList())
                println(sequence { yield(intArrayOf(3)); yieldAll(listOf(intArrayOf(4))) }.map { it[0] }.toList())
            }
            """#, expected: "[7, 7]\n[2, 10]\n[1, 2, 3]\n[x, y]\n[5, 6]\n[7, 8]\n[9]\n[10]\n[11, 12]\n[13]\n[1, 2]\n[3, 4]\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m21UserFunctionsShadowBuilderNames(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            fun sequence(block: () -> Int): Int = block()
            fun iterator(block: () -> Int): Int = block()
            fun main() { println(sequence { 42 }); println(iterator { 43 }) }
            """, expected: "42\n43\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [
        #"suspend fun work() {}; fun main() { sequence<Int> { work(); yield(1) } }"#,
        #"fun main() { sequence<Int> { val alias = this; alias.yield(1) } }"#,
        #"suspend fun plain(scope: kotlin.sequences.SequenceScope<Int>) { scope.yield(1) }"#,
        #"fun main() { sequence<Int> outer@ { yieldAll(sequence<Int> { this@outer.yield(1) }) } }"#,
        #"fun f(): Int { sequence<Int> { return 1 }; return 0 }"#,
        #"fun main() { sequence<Int> { sequenceOf(1).map { yield(it) }.toList() } }"#,
        #"fun main() { sequence<Int>(unknown = { yield(1) }) }"#,
        #"fun main() { iterator<Int>(unknown = { yield(1) }) }"#,
        #"fun main() { sequence<Int> { yield("wrong") } }"#,
        #"fun main() { sequence<Int> { yieldAll(arrayOf(1)) } }"#,
        #"fun main() { sequence<Int, String> { yield(1) } }"#,
        #"fun main() { sequence<Int>(null) }"#,
        #"fun main() { yield(1) }"#,
        #"abstract class Derived: kotlin.sequences.SequenceScope<Int>()"#,
        #"suspend fun work() {}; suspend fun <S: kotlin.sequences.SequenceScope<Int>> S.bad() { work() }"#,
        #"import kotlin.sequences.*; class Custom: SequenceScope<Int>() { override suspend fun yield(value: Int) {}; override suspend fun yieldAll(iterator: Iterator<Int>) {} }"#,
        #"fun main() { sequence<Int> { val nested: suspend () -> Unit = { yield(1) }; nested() } }"#,
        #"fun bad(scope: kotlin.sequences.SequenceScope<Int>) = sequence<Int> { scope.yield(1) }"#,
        #"fun bad(g: suspend (kotlin.sequences.SequenceScope<Int>) -> Unit) = sequence<Int> { g(this) }"#,
        #"fun bad(f: suspend kotlin.sequences.SequenceScope<Int>.() -> Unit) = sequence<Int> { val alias = this; alias.f() }"#,
        #"fun bad(f: suspend kotlin.sequences.SequenceScope<Int>.() -> Unit) = sequence<Int> { f.invoke(this) }"#,
    ])
    func m21InvalidBuildersPreserveOutput(source: String) throws {
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
    func m21JavaAndOfficialKotlinBuilderConsumers() throws {
        try withWorkspace { root in
            let result = try compile(#"""
            package api
            import kotlin.sequences.*
            fun values(n: Int): Sequence<Int> = sequence { for (i in 1..n) { yield(i); yieldAll(listOf(i * 10)) } }
            fun items(): Iterator<String> = iterator { yield("a"); yieldAll(sequenceOf("b", "c")) }
            suspend fun <T> SequenceScope<T>.twice(value: T) { yield(value); yield(value) }
            inline fun <reified T> selected(values: List<Any>): Sequence<T> = sequence { for (item in values) if (item is T) yield(item) }
            fun from(block: suspend SequenceScope<Int>.() -> Unit): Sequence<Int> = sequence(block)
            """#, root: root, mode: .jvmJar)
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let jar = root.appendingPathComponent("hello.jar").path, runtime = try m11Runtime()
            try #"""
            import api.*
            fun main() {
                println(values(2).toList()); println(items().asSequence().joinToString())
                println(sequence { twice(7) }.toList()); println(from { yield(8); yieldAll(listOf(9)) }.toList())
                println(selected<String>(listOf(1, "x", 2, "y")).toList())
            }
            """#.write(to: root.appendingPathComponent("consumer.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["consumer.kt", "-cp", jar + ":" + runtime, "-d", "consumer.jar"], root: root)
            for cp in [jar + ":" + runtime, runtime + ":" + jar] {
                #expect(try java(["-cp", root.appendingPathComponent("consumer.jar").path + ":" + cp, "ConsumerKt"]).stdout == "[1, 10, 2, 20]\na, b, c\n[7, 7]\n[8, 9]\n[x, y]\n")
            }
            try #"""
            public class JavaConsumer {
                public static void main(String[] args) {
                    System.out.println(kotlin.sequences.SequencesKt.toList(api.HelloKt.values(2)));
                    java.util.Iterator<String> it = api.HelloKt.items();
                    while (it.hasNext()) System.out.println(it.next());
                }
            }
            """#.write(to: root.appendingPathComponent("JavaConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", jar + ":" + runtime, "JavaConsumer.java"], root: root)
            #expect(try java(["-cp", root.path + ":" + jar + ":" + runtime, "JavaConsumer"]).stdout == "[1, 10, 2, 20]\na\nb\nc\n")
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m21ForLoopOverIteratorUsesItAsCursor(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11(#"""
            fun <I : Iterator<Int>> drain(it: I): Int { var sum = 0; for (n in it) sum += n; return sum }
            fun main() {
                val values = iterator<Int> { yield(1); yield(2) }
                for (value in values) println(value)
                var total = 0
                for (n in listOf(1, 2, 3).iterator()) total += n
                println(total)
                for (n in mutableListOf(4, 5).iterator()) println(n + 10)
                val halted = iterator<String> { yield("x"); yield("y"); yield("z") }
                for (s in halted) { if (s == "y") break; println(s) }
                println(drain(listOf(8, 9).iterator()))
                val exhausted = listOf(3).iterator()
                for (n in exhausted) println(n)
                println(exhausted.hasNext())
                for (n in sequenceOf(10, 11)) println(n)
            }
            """#, expected: "1\n2\n6\n14\n15\nx\n17\n3\nfalse\n10\n11\n", mode: mode, root: root)
        }
    }
}
#endif
