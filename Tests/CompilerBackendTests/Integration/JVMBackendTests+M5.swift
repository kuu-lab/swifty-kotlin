#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func genericClassesAndFunctionsExecute(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            class Box<T>(var value: T) { fun get(): T = value }
            fun <T> identity(value: T): T = value
            fun <T: Any> bounded(value: T): T = value
            fun <T: Any> maybe(value: T?): T? = value
            fun main() {
                val text = Box<String>("hello")
                println(text.get())
                text.value = "changed"
                println(text.value)
                val number = Box(21)
                println(number.get() * 2)
                println(identity<Int>(7))
                println(identity("inferred"))
                println(bounded("bound"))
                println(maybe<String>(null))
                val optional: Int? = 8
                println(optional!! + 1)
                println(optional == 8)
                println(maybe<Int>(null) ?: 7)
                val nan: Double? = 0.0 / 0.0
                val zero: Double? = -0.0
                println(nan == nan)
                println(zero == 0.0)
                val erased: Any? = nan
                println(erased == nan)
            }
            """, expected: "hello\nchanged\n42\n7\ninferred\nbound\nnull\n9\ntrue\n7\nfalse\ntrue\ntrue\n", mode: mode, root: root)
        }
    }
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func primitiveAndReferenceArraysExecute(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            fun sum(values: IntArray): Int { var total = 0; for (value in values) { total += value }; return total }
            fun main() {
                val values = intArrayOf(2, 3, 4)
                values[1] = 8
                values[2] += 1
                println(values.size)
                println(sum(values))
                val zero = LongArray(2)
                zero[0] = 9L
                println(zero[0] + zero[1])
                val words = arrayOf("one", "two")
                words[1] = "three"
                for (word in words) { println(word) }
                val nullable = arrayOfNulls<String>(2)
                nullable[0] = "ok"
                println(nullable[0])
                println(nullable[1])
                val nested = arrayOf(intArrayOf(6))
                println(nested[0][0])
                println(booleanArrayOf(true, false)[1])
                println(doubleArrayOf(1.5, 2.5)[0])
            }
            """, expected: "3\n15\n9\none\nthree\nok\nnull\n6\nfalse\n1.5\n", mode: mode, root: root)
        }
    }
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func collectionsAndIterationExecute(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            fun main() {
                val values = mutableListOf(2, 3, 4)
                values.add(5)
                values[0] = 10
                println(values.size)
                println(values.removeAt(1))
                var sum = 0
                for (value in values) { if (value == 4) continue; sum += value }
                println(sum)
                val view: List<Int> = values
                println(view[1])
                val names = setOf("a", "b", "a")
                println(names.size)
                for (name in names) { println(name) }
                val counts = mutableMapOf<String, Int>()
                counts["answer"] = 42
                println(counts["answer"]!!)
                println(counts["absent"])
                println(counts.containsKey("answer"))
                for (key in counts.keys) { println(key) }
                val initial = mapOf("a" to 1, "b" to 2)
                println(initial["b"])
                println(emptyList<String>().isEmpty())
            }
            """, expected: "4\n3\n15\n4\n2\na\nb\n42\nnull\ntrue\nanswer\n2\ntrue\n", mode: mode, root: root)
        }
    }
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func exceptionsCatchFinallyAndEscapingControlFlow(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            class Failure(message: String): RuntimeException(message)
            fun returning(): Int {
                try { return 7 } finally { println("return-finally") }
            }
            fun nested(): Int {
                try {
                    try { throw IllegalArgumentException("inner") }
                    finally { println("inner-finally") }
                } catch (e: RuntimeException) { println(e.message); return 9 }
                finally { println("outer-finally") }
            }
            fun main() {
                val result = try { throw Failure("failure"); 0 }
                    catch (e: IllegalArgumentException) { 1 }
                    catch (e: Failure) { println(e.message); 42 }
                    finally { println("finally") }
                println(result)
                println(returning())
                println(nested())
                for (i in 1..3) {
                    try { if (i == 1) continue; if (i == 2) break }
                    finally { println(i) }
                }
                try { println(intArrayOf(1)[5]) }
                catch (e: IndexOutOfBoundsException) { println("bounds") }
                try { val n = 0; println(10 / n) }
                catch (e: ArithmeticException) { println("divide") }
            }
            """, expected: "failure\nfinally\n42\nreturn-finally\n7\ninner-finally\ninner\nouter-finally\n9\n1\n2\nbounds\ndivide\n", mode: mode, root: root)
        }
    }
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func genericInterfaceBridgesAndBounds(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            interface Transform<T> { fun apply(value: T): T }
            class Increment: Transform<Int> { override fun apply(value: Int): Int = value + 1 }
            class Echo: Transform<String> { override fun apply(value: String): String = value }
            interface Source<T> { fun get(): T }
            class IntSource: Source<Int> { override fun get(): Int = 12 }
            interface Named { fun name(): String }
            class Name: Named { override fun name(): String = "bounded" }
            fun <T: Named> same(value: T): T = value
            fun <T: Number> number(value: T): Int = value.toInt()
            fun main() {
                val increment: Transform<Int> = Increment()
                println(increment.apply(41))
                val echo: Transform<String> = Echo()
                println(echo.apply("bridge"))
                val source: Source<Int> = IntSource()
                println(source.get())
                println(same(Name()).name())
                println(number(42L))
            }
            """, expected: "42\nbridge\n12\nbounded\n42\n", mode: mode, root: root)
        }
    }
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func finallyLexicalScopesOverridesAndPendingConstructors(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            class Box(val number: Int)
            open class Parent(val number: Int)
            class Child(): Parent(try { val zero = 0; 10 / zero } catch(e: ArithmeticException) { 11 })
            fun shadow(): Int {
                val x = 1
                try { val x = 2; return x } finally { println(x) }
            }
            fun replace(): Int { try { return 7 } finally { return 8 } }
            fun replaceException(flag: Boolean): Int {
                try {
                    try { return 1 }
                    finally { println("inner"); if (flag) throw IllegalStateException("replacement"); return 2 }
                } finally { println("outer") }
            }
            fun lexicalBreak(): Int {
                var n = 0
                while (n < 2) {
                    try { while (n < 2) { n++; return 7 } }
                    finally { break }
                }
                return 9
            }
            fun main() {
                println(shadow())
                println(replace())
                println(replaceException(false))
                try { println(replaceException(true)) } catch(e: IllegalStateException) { println(e.message) }
                println(lexicalBreak())
                val box = Box(try { throw IllegalArgumentException("arg"); 0 } catch(e: IllegalArgumentException) { 42 })
                println(box.number)
                println(Child().number)
                try {
                    try { throw IllegalArgumentException("first") }
                    catch(e: IllegalArgumentException) { throw IllegalStateException("catch") }
                    finally { println("catch-finally") }
                } catch(e: IllegalStateException) { println(e.message) }
                val erased: Any = 42
                println(erased is Int)
                println(erased as? String)
                try { println(erased as String) } catch(e: ClassCastException) { println("cast") }
            }
            """, expected: "1\n2\n8\ninner\nouter\n2\ninner\nouter\nreplacement\n9\n42\n11\ncatch-finally\ncatch\ntrue\nnull\ncast\n", mode: mode, root: root)
        }
    }
    @Test
    func genericArraysCollectionsAndExceptionsAreConsumableFromJavaAndKotlin() throws {
        try withWorkspace { root in
            let result = try compile("""
            package api
            class Box<T>(var value: T)
            interface Transform<T> { fun apply(value: T): T }
            class Increment: Transform<Int> { override fun apply(value: Int): Int = value + 1 }
            interface Named { fun name(): String }
            class Name: Named { override fun name(): String = "bound" }
            fun <T: Named> bounded(value: T): T = value
            fun <T> identity(value: T): T = value
            open class Base
            class Child: Base()
            fun count(items: List<Base>): Int = items.size
            fun sum(values: IntArray): Int { var result = 0; for (n in values) { result += n }; return result }
            fun first(values: Array<String>): String = values[0]
            fun numbers(): List<Int> = listOf(20, 22)
            fun failure(): Int { throw IllegalStateException("failure") }
            """, root: root, mode: .jvmJar)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }
            try """
            import api.*;
            import java.util.*;
            public class JavaConsumer {
                public static void main(String[] args) throws Exception {
                    Box<String> box = new Box<>("java");
                    System.out.println(box.getValue());
                    box.setValue("changed"); System.out.println(box.getValue());
                    Transform<Integer> t = new Increment(); System.out.println(t.apply(41));
                    System.out.println(HelloKt.identity(7) * 2);
                    System.out.println(HelloKt.bounded(new Name()).name());
                    System.out.println(HelloKt.count(Arrays.asList(new Child(), new Child())));
                    System.out.println(HelloKt.sum(new int[]{20,22}));
                    System.out.println(HelloKt.first(new String[]{"array"}));
                    System.out.println(HelloKt.numbers().get(1) + 20);
                    System.out.println(Box.class.getDeclaredField("value").getGenericType().getTypeName());
                    try { HelloKt.failure(); } catch(IllegalStateException e) { System.out.println(e.getMessage()); }
                }
            }
            """.write(to: root.appendingPathComponent("JavaConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", "hello.jar", "JavaConsumer.java"], root: root)
            let javaRun = try java(["-cp", root.path + ":" + root.appendingPathComponent("hello.jar").path + ":" + (try m11Runtime()), "JavaConsumer"])
            #expect(javaRun.stdout == "java\nchanged\n42\n14\nbound\n2\n42\narray\n42\nT\nfailure\n")
            try """
            import api.*
            fun main() {
                val box = Box<String>("kotlin")
                box.value = "changed"
                println(box.value)
                val transform: Transform<Int> = Increment()
                println(transform.apply(41))
                println(identity(7) * 2)
                println(bounded(Name()).name())
                println(count(listOf(Child(), Child())))
                println(sum(intArrayOf(20,22)))
                println(first(arrayOf("array")))
                val list: List<Int> = numbers()
                println(list[1] + 20)
                try { failure() } catch(e: IllegalStateException) { println(e.message) }
            }
            """.write(to: root.appendingPathComponent("Consumer.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["-cp", "hello.jar", "Consumer.kt", "-include-runtime", "-d", "consumer.jar"], root: root)
            let kotlinRun = try java(["-cp", root.appendingPathComponent("consumer.jar").path + ":" + root.appendingPathComponent("hello.jar").path, "ConsumerKt"])
            #expect(kotlinRun.stdout == "changed\n42\n14\nbound\n2\n42\narray\n42\nfailure\n")
            try "import api.*\nval invalid: String = identity(1)\n".write(to: root.appendingPathComponent("Invalid.kt"), atomically: true, encoding: .utf8)
            do {
                _ = try jvmTool("kotlinc", ["-cp", "hello.jar", "Invalid.kt", "-d", "invalid.jar"], root: root)
                Issue.record("Kotlin consumer accepted incompatible generic types.")
            } catch CommandRunnerError.nonZeroExit(let error) { #expect(error.exitCode != 0) }
        }
    }

    @Test
    func externalJavaArraySignaturesExecute() throws {
        try withWorkspace { root in
            let dependency = try javaFixture(root)
            let result = try compile("""
            import dep.Counter
            fun main() {
                println(Counter.array(intArrayOf(1, 2, 3)))
                val values = mutableListOf(1, 2, 3)
                println(values.remove(2))
                println(values.size)
                val set = mutableSetOf("a", "b")
                println(set.remove("a"))
                println(set.contains("b"))
            }
            """, root: root, mode: .jvmJar, classpath: [dependency.path])
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }
            #expect(try java(["-cp", root.appendingPathComponent("hello.jar").path + ":" + dependency.path + ":" + (try m11Runtime()), "HelloKt"]).stdout == "3\ntrue\n2\ntrue\ntrue\n")
        }
    }
    @Test(arguments: [
        "fun <reified T> identity(x: T): T = x",
        "fun <T> main() {}",
        "fun <T> make(): Array<T> = arrayOf<T>()",
        "fun main() { val a = arrayOf<Unit>() }",
        "fun unsupported(x: List<Unit>) {}",
        "fun main() { val a = intArrayOf(1); println(a[\"wrong\"]) }",
        "fun main() { val a = listOf(1); a[0] = 2 }",
        "fun main() { val a: MutableList<out Int> = mutableListOf(1); a[0] = 2 }",
        "fun main() { val a: Array<out Int> = arrayOf(1); a[0] = 2 }",
        "fun main() { val pair = Pair(1) }",
        "abstract class CustomNumber: Number()",
        "fun main() { try { throw 1 } catch(e: String) {} }",
        "fun main() { try { println(1) } }",
        "fun first(x: List<Int>): Int = 1; fun first(x: List<String>): Int = 2",
    ])
    func unsupportedOrInvalidM5PreservesExistingOutput(source: String) throws {
        try withWorkspace { root in
            let output = root.appendingPathComponent("hello.jar"), previous = Data("existing output".utf8)
            try previous.write(to: output)
            let result = try compile(source, root: root, mode: .jvmJar)
            #expect(result.0 != 0)
            #expect(!result.1.contains { $0.code.hasPrefix("KSWIFTK-ICE") })
            #expect(try Data(contentsOf: output) == previous)
        }
    }

}
#endif
