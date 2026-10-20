#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    func runM7Coroutine(_ source: String, expected: String, mode: EmitMode, root: URL) throws {
        let result = try compile(source, root: root, mode: mode)
        #expect(result.0 == 0, "\(result.1.map(\.message))")
        guard result.0 == 0 else { return }
        // The reference JAR also provides the official coroutine runtime. The
        // generated classes come first so its duplicate HelloKt cannot mask them.
        _ = try jvmTool("kotlinc", ["hello.kt", "-include-runtime", "-d", "reference.jar"], root: root)
        let reference = root.appendingPathComponent("reference.jar").path
        let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
        #expect(try java(["-cp", artifact + ":" + reference, "HelloKt"]).stdout == expected)
        #expect(try java(["-jar", reference]).stdout == expected)
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func suspendMainFunctionsReceiverLambdasAndGenericBridges(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM7Coroutine("""
            interface Source<T> { suspend fun get(value: T): T }
            open class Base : Source<Int> { override suspend fun get(value: Int): Int = value + 1 }
            class Derived : Base() { override suspend fun get(value: Int): Int = super.get(value) + 1 }
            fun main(value: Int): Int = value
            suspend fun twice(value: Int): Int = value * 2
            suspend fun main() {
                val source: Source<Int> = Derived()
                println(source.get(40))
                val operation: suspend Int.(Int) -> Int = { other -> twice(this) + other }
                println(operation(20, 2))
                val callback: suspend () -> Int = { twice(21) }
                println(callback())
                println(main(7))
            }
            """, expected: "42\n42\n42\n7\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func suspensionResumesLocalsLoopsAndExceptionHandlers(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM7Coroutine("""
            import kotlin.coroutines.*
            class Gate {
                var pending: Continuation<Int>? = null
                suspend fun await(): Int = suspendCoroutine { pending = it }
                fun release(value: Int) { pending!!.resume(value) }
                fun reject() { pending!!.resumeWithException(IllegalStateException("failed")) }
            }
            class Sink : Continuation<Int> {
                override val context: CoroutineContext get() = EmptyCoroutineContext
                override fun resumeWith(result: Result<Int>) { println(result.getOrThrow()) }
            }
            class FailureSink : Continuation<Int> {
                override val context: CoroutineContext get() = EmptyCoroutineContext
                override fun resumeWith(result: Result<Int>) {
                    println(result.isSuccess)
                    println(result.isFailure)
                    println(result.exceptionOrNull()!!.message)
                }
            }
            fun main() {
                val gate = Gate()
                val work: suspend () -> Int = {
                    var sum = 0L
                    var index = 0
                    while (index < 2) { sum += gate.await(); index++ }
                    try { gate.await() } catch (failure: IllegalStateException) {
                        println(failure.message)
                    } finally { println("finally") }
                    sum.toInt()
                }
                work.startCoroutine(Sink())
                println("paused")
                gate.release(20)
                println("paused again")
                gate.release(22)
                println("awaiting failure")
                gate.reject()
                val fail: suspend () -> Int = { gate.await() }
                fail.startCoroutine(FailureSink())
                gate.reject()
            }
            """, expected: "paused\npaused again\nawaiting failure\nfailed\nfinally\n42\nfalse\ntrue\nfailed\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func suspendSAMAndSynchronousSafeContinuation(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM7Coroutine("""
            import kotlin.coroutines.*
            fun interface AsyncOp { suspend fun apply(value: Int): Int }
            suspend fun immediate(value: Int): Int = suspendCoroutine { it.resume(value) }
            class Sink : Continuation<Unit> {
                override val context: CoroutineContext get() = EmptyCoroutineContext
                override fun resumeWith(result: Result<Unit>) { result.getOrThrow(); println("complete") }
            }
            fun main() {
                val operation = AsyncOp { immediate(it * 2) }
                val callback: (Int) -> Int = { it * 2 }
                val adapted = AsyncOp(callback)
                val work: suspend () -> Unit = {
                    println(operation.apply(21))
                    println(adapted.apply(21))
                    suspendCoroutine<Unit> { it.resume(Unit) }
                }
                work.startCoroutine(Sink())
            }
            """, expected: "42\n42\ncomplete\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func samConstructorsConversionsGenericsAndDefaultMethods(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            fun interface Op { fun apply(value: Int): Int; fun tag(): Int = 9 }
            fun interface Transform<T> { fun apply(value: T): T }
            fun use(op: Op): Int = op.apply(21)
            fun main() {
                var offset = 1
                val op = Op { value -> value + offset }
                offset = 2
                println(op.apply(40))
                println(op.tag())
                println(use { it * 2 })
                val callback: (Int) -> Int = { it * 3 }
                println(use(callback))
                val transform = Transform<String> { it }
                println(transform.apply("sam"))
                val unit = Op { 7 }
                println(unit.apply(0))
            }
            """, expected: "42\n9\n42\n63\nsam\n7\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func inlineFunctionsExpandCallbacksAndNonLocalReturns(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            inline fun twice(value: Int, block: (Int) -> Int): Int = block(value) + block(value)
            inline fun guarded(block: () -> Int): Int {
                try { return block() } finally { println("guard") }
            }
            inline fun <T> T.pipe(block: (T) -> T): T = block(this)
            inline fun save(noinline block: () -> Int): () -> Int = block
            inline fun wrap(crossinline block: () -> Int): () -> Int = { block() }
            fun early(): Int { guarded { return 42 }; return 0 }
            fun local(): Int = guarded { if (true) return@guarded 7; 0 }
            fun main() {
                var calls = 0
                println(twice(10) { calls += 1; it + calls })
                println(calls)
                println(early())
                println(local())
                println(21.pipe { it * 2 })
                println(save { 8 }())
                println(wrap { 9 }())
            }
            """, expected: "23\n2\nguard\n42\nguard\n7\n42\n8\n9\n", mode: mode, root: root)
        }
    }

    @Test
    func samInlineAndSuspendAreCallableFromJavaAndOfficialKotlin() throws {
        try withWorkspace { root in
            let result = try compile("""
            package api
            class Box(val value: Int)
            fun interface Op { fun apply(value: Int): Int }
            fun run(op: Op): Int = op.apply(21)
            inline fun apply(value: Int, block: (Int) -> Int): Int = block(value)
            inline fun wrap(noinline block: () -> Int): () -> Int = { block() }
            inline fun cross(crossinline block: () -> Int): () -> Int = { block() }
            inline fun guarded(block: () -> Int): Int { try { return block() } finally { println("guard") } }
            inline fun box(value: Int): Box = Box(value + 1)
            suspend fun plus(left: Int, right: Int): Int = left + right
            fun task(value: Int): suspend () -> Int = { plus(value, value) }
            """, root: root, mode: .jvmJar)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }
            try """
            package consumer
            import api.*
            import kotlin.coroutines.*
            fun early(): Int { apply(21) { return it * 2 }; return 0 }
            fun leave(): Int { guarded { return 42 }; return 0 }
            fun main() {
                println(early())
                println(run(Op { it * 2 }))
                val completion = object : Continuation<Int> {
                    override val context: CoroutineContext = EmptyCoroutineContext
                    override fun resumeWith(result: Result<Int>) { println(result.getOrThrow()) }
                }
                val work: suspend () -> Int = { plus(20, 22) }
                work.startCoroutine(completion)
                val from: suspend () -> Int = task(21)
                from.startCoroutine(completion)
                println(wrap { 42 }())
                println(cross { 42 }())
                println(leave())
                println(box(41).value)
            }
            """.write(to: root.appendingPathComponent("Consumer.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["Consumer.kt", "-cp", "hello.jar", "-include-runtime", "-d", "consumer.jar"], root: root)
            let jar = root.appendingPathComponent("hello.jar").path
            let runtime = root.appendingPathComponent("consumer.jar").path
            for classpath in [runtime + ":" + jar, jar + ":" + runtime] {
                #expect(try java(["-cp", classpath, "consumer.ConsumerKt"]).stdout == "42\n42\n42\n42\n42\n42\nguard\n42\n42\n")
            }
            try """
            import api.HelloKt;
            import kotlin.coroutines.*;
            public class JavaConsumer {
                public static void main(String[] args) {
                    Continuation<Integer> completion = new Continuation<Integer>() {
                        public CoroutineContext getContext() { return EmptyCoroutineContext.INSTANCE; }
                        public void resumeWith(Object result) { throw new AssertionError("Unexpected suspension"); }
                    };
                    System.out.println(HelloKt.run(x -> x * 2));
                    System.out.println(HelloKt.apply(21, x -> x * 2));
                    System.out.println(HelloKt.plus(20, 22, completion));
                    System.out.println(HelloKt.task(21).invoke(completion));
                }
            }
            """.write(to: root.appendingPathComponent("JavaConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", jar + ":" + runtime, "JavaConsumer.java"], root: root)
            #expect(try java(["-cp", root.path + ":" + jar + ":" + runtime, "JavaConsumer"]).stdout == "42\n42\n42\n42\n")
        }
    }

    @Test
    func importedJavaSAMSupportsInheritedAbstractAndDefaultMethods() throws {
        try withWorkspace { root in
            try """
            public interface Parent { int apply(int value); }
            """.write(to: root.appendingPathComponent("Parent.java"), atomically: true, encoding: .utf8)
            try """
            public interface Child extends Parent {
                default int tag() { return 9; }
                static int use(Child op) { return op.apply(21); }
            }
            """.write(to: root.appendingPathComponent("Child.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["Parent.java", "Child.java"], root: root)
            _ = try jvmTool("jar", ["cf", "dependency.jar", "Parent.class", "Child.class"], root: root)
            let result = try compile("""
            fun main() {
                val op = Child { it * 2 }
                println(op.apply(21))
                println(op.tag())
                println(Child.use { it * 2 })
            }
            """, root: root, mode: .jvmJar, classpath: [root.appendingPathComponent("dependency.jar").path])
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }
            #expect(try java(["-cp", root.appendingPathComponent("hello.jar").path + ":" + root.path, "HelloKt"]).stdout == "42\n9\n42\n")
        }
    }

    @Test
    func inlineCallbacksProduceNoClosureOrInvokeAtTheCallSite() throws {
        try withWorkspace { root in
            let result = try compile("""
            inline fun twice(value: Int, block: (Int) -> Int): Int = block(value) + block(value)
            fun main() { println(twice(21) { it }) }
            """, root: root, mode: .jvmJar)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }
            let listing = try jvmTool("jar", ["tf", "hello.jar"], root: root).stdout
            #expect(!listing.contains("$Lambda"))
            let bytecode = try jvmTool("javap", ["-cp", "hello.jar", "-c", "HelloKt"], root: root).stdout
            let main = bytecode.components(separatedBy: "public static void main();").last?.components(separatedBy: "public static void main(java.lang.String[]);").first ?? ""
            #expect(!main.isEmpty)
            #expect(!main.contains("Method twice:"))
            #expect(!main.contains("invokeinterface"))
            #expect(try java(["-jar", root.appendingPathComponent("hello.jar").path]).stdout == "42\n")
        }
    }

    @Test(arguments: [
        "fun interface Bad { fun a(): Int; fun b(): Int }; fun main() { val op = Bad { 1 } }",
        "inline fun bad(noinline block: () -> Int): Int = block(); fun early(): Int = bad { return 1 }",
        "inline fun bad(crossinline block: () -> Int): Int = block(); fun early(): Int = bad { return 1 }",
        "inline fun recurse(block: () -> Int): Int = recurse(block); fun main() { println(recurse { 1 }) }",
        "suspend fun value(): Int = 1; fun main() { println(value()) }",
        "class Box(val value: Int); suspend fun value(): Int = 1; suspend fun main() { println(Box(value()).value) }",
        "class Context : kotlin.coroutines.CoroutineContext; fun main() {}",
        "class Box(val n: Int); suspend fun pause(): Int = 1; suspend fun test(flag: Boolean): Int { while (true) { Box(if (flag) break else pause()); break }; return 42 }",
        "suspend fun f(): Int = 1; fun f(c: kotlin.coroutines.Continuation<Int>): Any? = null",
    ])
    func invalidM7ProgramsPreservePreviousOutput(source: String) throws {
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
