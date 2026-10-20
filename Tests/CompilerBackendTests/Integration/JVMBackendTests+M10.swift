#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    func runM10(_ source: String, expected: String, mode: EmitMode, root: URL) throws {
        let result = try compile(source, root: root, mode: mode)
        #expect(result.0 == 0, "\(result.1.map(\.message))")
        guard result.0 == 0 else { return }
        _ = try jvmTool("kotlinc", ["hello.kt", "-include-runtime", "-d", "reference.jar"], root: root)
        let reference = root.appendingPathComponent("reference.jar").path
        // Isolate official runtime classes so a missing generated user class
        // cannot silently fall back to the reference compiler's implementation.
        let archive = try ZipArchive(data: Data(contentsOf: URL(fileURLWithPath: reference)))
        let runtime = root.appendingPathComponent("official-runtime")
        for entry in archive.entries where entry.name.hasPrefix("kotlin/") && entry.name.hasSuffix(".class") {
            let file = runtime.appendingPathComponent(entry.name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(archive.contents(of: entry)).write(to: file)
        }
        let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
        #expect(try java(["-cp", artifact + ":" + runtime.path, "HelloKt"]).stdout == expected)
        #expect(try java(["-jar", reference]).stdout == expected)
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m10ClassDelegationAndOverrides(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM10("""
            interface Counter { var value: Int; fun next(step: Int = 1): Int; fun twice(): Int = next(2) }
            class Store(override var value: Int): Counter { override fun next(step: Int): Int { value += step; return value } }
            class Forward(var target: Counter): Counter by target
            class Override(target: Counter): Counter by target { override fun next(step: Int): Int = step * 10 }
            object Global: Counter by Store(20)
            class AnonymousDelegate: Counter by (object: Counter by Store(50) {}) { fun read(): Int = value }
            fun main() {
                val store = Store(10)
                val forward = Forward(store)
                println(forward.next()); forward.value = 30; println(store.value)
                forward.target = Store(100)
                println(forward.twice()); println(forward.value)
                val override = Override(store)
                println(override.next(3)); println(override.twice())
                println(Global.next())
                val anonymous: Counter = object: Counter by Store(40) {}
                println(anonymous.next())
                val captured: Counter = object: Counter by store {}
                println(captured.next()); println(AnonymousDelegate().read())
            }
            """, expected: "11\n30\n32\n32\n30\n34\n21\n41\n35\n50\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m10DelegatedPropertiesAndProvideDelegate(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM10("""
            import kotlin.reflect.KProperty
            class Value(private var stored: Int) {
                operator fun getValue(owner: Any?, property: KProperty<*>): Int { println(property.name); return stored }
                operator fun setValue(owner: Any?, property: KProperty<*>, value: Int) { println(property.name); stored = value }
            }
            class Provider {
                operator fun provideDelegate(owner: Any?, property: KProperty<*>): Value { println(property.name); return Value(10) }
            }
            var top: Int by Value(1)
            class Box { var number: Int by Provider() }
            fun main() {
                println(top); top = 2; println(top)
                val box = Box(); println(box.number); box.number += 5; println(box.number)
                var local: Int by Value(3)
                val change = { local += 4; local }
                println(change()); println(change())
            }
            """, expected: "top\n1\ntop\ntop\n2\nnumber\nnumber\n10\nnumber\nnumber\nnumber\n15\nlocal\nlocal\nlocal\n7\nlocal\nlocal\nlocal\n11\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m10LazyInitializationAndRetry(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM10("""
            var calls = 0
            val top: Int by lazy { calls += 1; 10 }
            class Box(val seed: Int) { val value: Int by lazy { calls += 1; seed * 2 } }
            fun main() {
                println(calls); println(top); println(top); println(calls)
                val first = Box(5); val second = Box(7)
                println(first.value); println(first.value); println(second.value); println(calls)
                var attempts = 0
                val retry by lazy(LazyThreadSafetyMode.NONE) { attempts += 1; if (attempts == 1) throw IllegalStateException("retry"); 42 }
                try { println(retry) } catch (e: IllegalStateException) { println(e.message) }
                println(retry); println(retry); println(attempts)
                val nullable: String? by lazy(LazyThreadSafetyMode.PUBLICATION) { calls += 1; null }
                println(nullable); println(nullable); println(calls)
                val state = lazy(lock = null) { 8 }
                println(state.isInitialized()); println(state.value); println(state.isInitialized())
            }
            """, expected: "0\n10\n10\n1\n10\n10\n14\n3\nretry\n42\n42\n2\nnull\nnull\n4\nfalse\n8\ntrue\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m10LateinitFieldsLocalsAndInitializationQuery(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM10("""
            lateinit var top: String
            class Box {
                lateinit var text: String
                fun ready(): Boolean = this::text.isInitialized
            }
            fun main() {
                val box = Box()
                println(::top.isInitialized); println(box.ready())
                try { println(top) } catch (e: UninitializedPropertyAccessException) { println(e.message) }
                try { println(box.text) } catch (e: UninitializedPropertyAccessException) { println(e.message) }
                top = "top"; box.text = "member"
                println(::top.isInitialized); println(box.ready()); println(top); println(box.text)
                lateinit var local: String
                val read = { local }
                try { println(read()) } catch (e: UninitializedPropertyAccessException) { println(e.message) }
                local = "local"; println(read())
            }
            """, expected: "false\nfalse\nlateinit property top has not been initialized\nlateinit property text has not been initialized\ntrue\ntrue\ntop\nmember\nlateinit property local has not been initialized\nlocal\n", mode: mode, root: root)
        }
    }
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m10GenericClassDelegationAndPropertyOperators(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM10("""
            import kotlin.reflect.KProperty
            import kotlin.properties.ReadWriteProperty
            interface Cell<T> { var value: T; fun exchange(next: T): T; fun <R> identity(value: R): R = value }
            class IntCell(override var value: Int): Cell<Int> {
                override fun exchange(next: Int): Int { val old = value; value = next; return old }
            }
            class Relay(delegate: Cell<Int>): Cell<Int> by delegate
            class Standard: ReadWriteProperty<Any?, Int> {
                private var stored = 4
                override operator fun getValue(thisRef: Any?, property: KProperty<*>): Int = stored
                override operator fun setValue(thisRef: Any?, property: KProperty<*>, value: Int) { stored = value }
            }
            class ExtensionDelegate<T>(var stored: T)
            operator fun <T> ExtensionDelegate<T>.getValue(thisRef: Any?, property: KProperty<*>): T = stored
            operator fun <T> ExtensionDelegate<T>.setValue(thisRef: Any?, property: KProperty<*>, value: T) { stored = value }
            class Holder { var member: Int by Standard() }
            fun main() {
                val relay = Relay(IntCell(10))
                val cell: Cell<Int> = relay
                println(cell.exchange(20)); println(relay.value); relay.value = 30; println(cell.value)
                println(relay.identity("generic"))
                val h = Holder(); println(h.member); h.member = 8; println(h.member)
                var x: Int by ExtensionDelegate(3)
                x += 5; println(x)
            }
            """, expected: "10\n20\n30\ngeneric\n4\n8\n8\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m10StandardDelegatesAndInitializationOrder(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM10("""
            import kotlin.properties.Delegates
            import kotlin.reflect.KProperty
            fun mark(n: Int): Int { println(n); return n }
            interface I { fun read(): Int }
            class Impl(val n: Int): I { override fun read(): Int = n }
            open class Base { init { println(1) } }
            class Wrapper: Base(), I by Impl(mark(2)) {
                val value: Int by lazy { mark(5) }
                val initial = mark(3)
                init { println(4) }
            }
            fun main() {
                val wrapper = Wrapper(); println(wrapper.read()); println(wrapper.value); println(wrapper.value)
                var observed: Int by Delegates.observable(1) { p, old, new -> println(p.name); println(old); println(new) }
                observed = 2; println(observed)
                var accepted: Int by Delegates.vetoable(10) { p, old, new -> new > old }
                accepted = 5; println(accepted); accepted = 20; println(accepted)
                var required: String by Delegates.notNull()
                try { println(required) } catch (e: IllegalStateException) { println("missing") }
                required = "ready"; println(required)
            }
            """, expected: "1\n2\n3\n4\n2\n5\n5\n5\nobserved\n1\n2\n2\n10\n20\nmissing\nready\n", mode: mode, root: root)
        }
    }

    @Test
    func m10JavaAndKotlinConsumersAndConcurrentLazy() throws {
        try withWorkspace { root in
            let result = try compile("""
            package api
            import kotlin.reflect.KProperty
            var calls = 0
            val top: Int by lazy { 42 }
            lateinit var status: String
            interface Counter { fun value(n: Int = 21): Int }
            class Base: Counter { override fun value(n: Int): Int = n * 2 }
            class Forward(delegate: Counter): Counter by delegate
            interface Operation { operator fun invoke(): Int }
            class SourceOperation: Operation { override fun invoke(): Int = 42 }
            class ForwardOperation(delegate: Operation): Operation by delegate
            class NumberDelegate(private var n: Int) {
                operator fun getValue(thisRef: Any?, property: KProperty<*>): Int = n
                operator fun setValue(thisRef: Any?, property: KProperty<*>, value: Int) { n = value }
            }
            class Box {
                val number: Int by lazy { calls += 1; 42 }
                lateinit var text: String
                lateinit var restricted: String
                    private set
                var delegated: Int by NumberDelegate(20)
                fun ready(): Boolean = this::text.isInitialized
            }
            """, root: root, mode: .jvmJar)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }
            try """
            import api.*
            fun main() {
                println(top); status = "ok"; println(status)
                val box = Box(); println(box.ready()); box.text = "member"; println(box.text)
                println(box.number); box.delegated += 2; println(box.delegated)
                var local by NumberDelegate(1); local = 42; println(local)
                println(Forward(Base()).value())
                println(ForwardOperation(SourceOperation())())
            }
            """.write(to: root.appendingPathComponent("consumer.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["consumer.kt", "-classpath", "hello.jar", "-include-runtime", "-d", "consumer.jar"], root: root)
            for order in ["hello.jar:consumer.jar", "consumer.jar:hello.jar"] {
                let cp = order.split(separator: ":").map { root.appendingPathComponent(String($0)).path }.joined(separator: ":")
                #expect(try java(["-cp", cp, "ConsumerKt"]).stdout == "42\nok\nfalse\nmember\n42\n22\n42\n42\n42\n")
            }
            try """
            import api.*;
            import java.util.concurrent.*;
            public class Consumer {
                public static void main(String[] args) throws Exception {
                    Box box = new Box();
                    try { box.getText(); throw new AssertionError(); }
                    catch (kotlin.UninitializedPropertyAccessException expected) {}
                    box.text = "java";
                    System.out.println(box.getText());
                    if (!java.lang.reflect.Modifier.isPrivate(Box.class.getDeclaredField("restricted").getModifiers())) throw new AssertionError();
                    box.setDelegated(42); System.out.println(box.getDelegated());
                    System.out.println(new Forward(new Base()).value(21));
                    CountDownLatch start = new CountDownLatch(1);
                    ExecutorService pool = Executors.newFixedThreadPool(16);
                    java.util.List<Future<Integer>> results = new java.util.ArrayList<>();
                    for (int i = 0; i < 64; i++) results.add(pool.submit(() -> { start.await(); return box.getNumber(); }));
                    start.countDown();
                    for (Future<Integer> result : results) if (result.get() != 42) throw new AssertionError();
                    pool.shutdown();
                    System.out.println(api.HelloKt.getCalls());
                }
            }
            """.write(to: root.appendingPathComponent("Consumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", "hello.jar:consumer.jar", "Consumer.java"], root: root)
            for order in ["hello.jar:consumer.jar", "consumer.jar:hello.jar"] {
                let cp = root.path + ":" + order.split(separator: ":").map { root.appendingPathComponent(String($0)).path }.joined(separator: ":")
                #expect(try java(["-cp", cp, "Consumer"]).stdout == "java\n42\n42\n1\n")
            }
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m10PrivateFieldsDelegateOrderAndMutableTokens(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM10("""
            import kotlin.reflect.KProperty
            import kotlin.reflect.KMutableProperty
            private lateinit var top: String
            interface A { fun a(): Int }
            interface B { fun b(): Int }
            class Impl: A, B { override fun a(): Int = 1; override fun b(): Int = 2 }
            fun makeA(): A { println(10); return Impl() }
            fun makeB(): B { println(20); return Impl() }
            class Multiple: B by makeB(), A by makeA() {
                fun ready(): Boolean = ::top.isInitialized
            }
            class Value {
                var token: KProperty<*>? = null
                operator fun provideDelegate(thisRef: Any?, p: KProperty<*>): Value { token = p; return this }
                operator fun getValue(thisRef: Any?, p: KProperty<*>): Int {
                    println(p == token); println(p is KMutableProperty<*>); println(thisRef == null); return 42
                }
                operator fun setValue(thisRef: Any?, p: KProperty<*>, value: Int) { println(p == token) }
            }
            class Owner { var number: Int by Value() }
            fun main() {
                val multiple = Multiple(); println(multiple.a() + multiple.b()); println(multiple.ready())
                top = "ok"; println(multiple.ready())
                val owner = Owner(); println(owner.number); owner.number = 1
                var local: Int by Value(); println(local); local = 1
            }
            """, expected: "20\n10\n3\nfalse\ntrue\ntrue\ntrue\nfalse\n42\ntrue\ntrue\ntrue\ntrue\n42\ntrue\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m10MemberExtensionDelegationAndNamedFactories(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM10("""
            import kotlin.properties.Delegates
            import kotlin.reflect.KProperty
            interface Extensions { fun Int.doubled(): Int }
            class Implementation: Extensions { override fun Int.doubled(): Int = this * 2 }
            class Forward(delegate: Extensions): Extensions by delegate { fun run(): Int = 21.doubled() }
            class Delegate(val value: Int)
            class Owner {
                operator fun Delegate.getValue(thisRef: Owner, p: KProperty<*>): Int = value
                val number: Int by Delegate(42)
            }
            var computed: Int = 1
                get() = field + 1
                private set(value) { field += value }
            fun main() {
                println(Forward(Implementation()).run()); println(Owner().number)
                var observed: Int by Delegates.observable(onChange = { p, old, new -> println(new) }, initialValue = 1)
                observed = 2; println(observed)
                var limited: Int by Delegates.vetoable(onChange = { p, old, new -> new > old }, initialValue = 10)
                limited = 5; println(limited)
                computed = 3; println(computed)
            }
            """, expected: "42\n42\n2\n2\n10\n5\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [
        "lateinit val value: String; fun main() {}",
        "lateinit var value: Int; fun main() {}",
        "lateinit var value: String?; fun main() {}",
        "class C { lateinit var value: String = \"invalid\" }; fun main() {}",
        "fun main() { val value by 42 }",
        "val number: Int = 1; fun getNumber(): Int = 2; fun main() {}",
        "val number: Int; fun main() { println(number) }"
    ])
    func m10InvalidDeclarationsPreserveExistingOutput(source: String) throws {
        try withWorkspace { root in
            let output = root.appendingPathComponent("hello.jar")
            let sentinel = Data("keep".utf8); try sentinel.write(to: output)
            let result = try compile(source, root: root, mode: .jvmJar)
            #expect(result.0 != 0)
            #expect(try Data(contentsOf: output) == sentinel)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m10ProvideDelegateReturningLazyReceivesPropertyToken(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM10("""
            import kotlin.reflect.KProperty
            class Provider {
                operator fun provideDelegate(thisRef: Any?, property: KProperty<*>): Lazy<Int> {
                    println(property.name); return lazy { println("initialize"); 42 }
                }
            }
            val top: Int by Provider()
            class Box { val number: Int by Provider() }
            fun main() {
                println(top); println(top)
                val box = Box(); println(box.number); println(box.number)
                val local: Int by Provider(); println(local); println(local)
            }
            """, expected: "top\ninitialize\n42\n42\nnumber\ninitialize\n42\n42\nlocal\ninitialize\n42\n42\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m10DelegatedInvokeAndLazyInterfaceBridges(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM10("""
            interface Operation { operator fun invoke(n: Int = 21): Int }
            class Implementation: Operation { override fun invoke(n: Int): Int = n * 2 }
            class Forward(delegate: Operation): Operation by delegate
            class Immediate: Lazy<Int> {
                override val value: Int get() = 42
                override fun isInitialized(): Boolean = true
            }
            class LazyForward(delegate: Lazy<Int>): Lazy<Int> by delegate
            fun main() {
                val operation = Forward(Implementation())
                println(operation()); println(Forward(Implementation())(20))
                val direct: Lazy<Int> = Immediate()
                println(direct.value)
                val forwarded: Lazy<Int> = LazyForward(direct)
                println(forwarded.value); println(forwarded.isInitialized())
                val delegated: Int by Immediate(); println(delegated)
            }
            """, expected: "42\n40\n42\n42\ntrue\n42\n", mode: mode, root: root)
        }
    }

}
#endif
