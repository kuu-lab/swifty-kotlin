#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    func runM4(_ source: String, expected: String, mode: EmitMode, root: URL, mainClass: String = "HelloKt") throws {
        let result = try compile(source, root: root, mode: mode)
        #expect(result.0 == 0, "\(result.1.map(\.message))")
        guard result.0 == 0 else { return }
        let args = mode == .jvmJar ? ["-jar", root.appendingPathComponent("hello.jar").path] : ["-cp", root.appendingPathComponent("classes").path, mainClass]
        let run = try java(args)
        #expect(run.stdout == expected)
        if mode == .jvmJar {
            _ = try jvmTool("kotlinc", ["hello.kt", "-include-runtime", "-d", "reference.jar"], root: root)
            let reference = try java(["-jar", root.appendingPathComponent("reference.jar").path])
            #expect(reference.stdout == run.stdout)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func classesConstructorsPropertiesAndDynamicDispatch(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            interface Named {
                val name: String
                fun label(): String = name
            }
            open class Base(val start: Int) {
                protected fun adjusted(value: Int): Int = value + start
                open fun score(): Int = start
            }
            class Counter(var count: Int): Base(count), Named {
                override val name: String = "counter"
                val doubled: Int get() = count * 2
                init { count += 1 }
                constructor(): this(10) { count += 2 }
                override fun score(): Int = super.score() + count
                fun add(n: Int): Int { count += n; return count }
                fun protectedCall(): Int = adjusted(count)
                private fun secret(): Int = 3
                fun privateCall(): Int = secret()
            }
            fun show(x: Named): String = x.label()
            fun main() {
                val c = Counter()
                println(c.count)
                c.count = 20
                println(c.add(2))
                println(c.doubled)
                println(c.score())
                println(show(c))
                val b: Base = c
                println(b.score())
                println(c.protectedCall())
                println(c.privateCall())
            }
            """, expected: "13\n22\n44\n32\ncounter\n32\n32\n3\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func initializationOrderCustomAccessorsAndConstructorChains(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            fun trace(n: Int): Int { println(n); return n }
            open class Parent(open val number: Int) {
                val copied = number
                init { println(copied) }
            }
            class Child(override val number: Int): Parent(number)
            class Storage {
                var value = trace(1)
                    get() { field += 1; return field }
                    set(v) { field = v * 2 }
                init { value = 5; println(2) }
                val fixed: Int
                init { this.fixed = trace(3) }
                var raw: Int
                    get() = field
                init { raw = 4 }
                constructor(n: Int) { value = n }
                constructor(): this(6) { value = 7 }
                fun readRaw(): Int = raw
            }
            fun main() {
                val child = Child(7)
                println(child.number)
                println(child.copied)
                val store = Storage()
                println(store.value)
                println(store.fixed)
                println(store.readRaw())
                store.value += 1
                println(store.value)
            }
            """, expected: "0\n7\n0\n1\n2\n3\n15\n3\n4\n35\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func abstractClassesCovariantBridgesAndInterfaceSuper(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            open class Item { open fun number(): Int = 1 }
            class ChildItem: Item() { override fun number(): Int = 2 }
            interface Factory { fun create(): Item; val current: Item }
            abstract class AbstractFactory: Factory {
                abstract override fun create(): ChildItem
                abstract override val current: ChildItem
            }
            class Maker: AbstractFactory() {
                override fun create(): ChildItem = ChildItem()
                override val current: ChildItem get() = ChildItem()
            }
            open class InheritedFactoryBase {
                fun create(): ChildItem = ChildItem()
                val current: ChildItem = ChildItem()
            }
            class InheritedMaker: InheritedFactoryBase(), Factory
            interface A { val amount: Int get() = 3; fun score(): Int = 4 }
            interface B: A
            class C: B {
                override val amount: Int get() = super<B>.amount + 1
                override fun score(): Int = super<B>.score() + 1
            }
            fun main() {
                val factory: Factory = Maker()
                println(factory.create().number())
                println(factory.current.number())
                val abstractFactory: AbstractFactory = Maker()
                println(abstractFactory.create().number())
                val c: A = C()
                println(c.amount)
                println(c.score())
                val inherited: Factory = InheritedMaker()
                println(inherited.create().number())
                println(inherited.current.number())
            }
            """, expected: "2\n2\n2\n4\n5\n2\n2\n", mode: mode, root: root)
        }
    }

    @Test
    func generatedClassesAreConsumableFromJavaAndKotlin() throws {
        try withWorkspace { root in
            let result = try compile("""
            package api
            interface Named { val name: String; fun label(): String = name }
            open class Base(val seed: Int) { open fun score(): Int = seed }
            class Counter(var count: Int): Base(count), Named {
                override val name: String = "counter"
                override fun score(): Int = super.score() + count
                var isText: String = "text"
                var restricted: Int = 1
                    private set
                fun increment() { restricted += 1 }
            }
            private class Hidden
            internal class InternalClass
            """, root: root, mode: .jvmJar)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }
            try """
            public class JavaConsumer {
                public static void main(String[] args) {
                    api.Counter counter = new api.Counter(6);
                    counter.setCount(7);
                    api.Base base = counter;
                    System.out.println(base.score());
                    System.out.println(counter.isText());
                    counter.setText("changed");
                    System.out.println(counter.isText());
                    api.Named named = counter;
                    System.out.println(named.label());
                }
            }
            """.write(to: root.appendingPathComponent("JavaConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", "hello.jar", "JavaConsumer.java"], root: root)
            #expect(try java(["-cp", root.path + ":" + root.appendingPathComponent("hello.jar").path, "JavaConsumer"]).stdout == "13\ntext\nchanged\ncounter\n")
            try """
            import api.Counter
            import api.Named
            class Other: Named { override val name: String = "other" }
            fun main() {
                val counter = Counter(count = 5)
                counter.count = 7
                println(counter.score())
                println(counter.name)
                counter.isText = "Kotlin"
                println(counter.isText)
                counter.increment()
                println(counter.restricted)
                println(Other().label())
            }
            """.write(to: root.appendingPathComponent("Consumer.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["Consumer.kt", "-cp", "hello.jar", "-include-runtime", "-d", "consumer.jar"], root: root)
            #expect(try java(["-cp", root.appendingPathComponent("consumer.jar").path + ":" + root.appendingPathComponent("hello.jar").path, "ConsumerKt"]).stdout == "12\ncounter\nKotlin\n2\nother\n")
            for invalid in ["fun bad() { api.Counter(1).restricted = 2 }", "fun bad() = api.InternalClass()", "fun bad() = api.Hidden()"] {
                try invalid.write(to: root.appendingPathComponent("Bad.kt"), atomically: true, encoding: .utf8)
                do {
                    _ = try jvmTool("kotlinc", ["Bad.kt", "-cp", "hello.jar", "-d", "bad.jar"], root: root)
                    Issue.record("Kotlin accepted inaccessible M4 declaration")
                } catch CommandRunnerError.nonZeroExit(let error) { #expect(error.exitCode != 0) }
            }
        }
    }

    @Test
    func nullLiteralComparisonDoesNotCallUserEquals() throws {
        try withWorkspace { root in
            try runM4("""
            class Strange {
                override fun equals(other: Any?): Boolean { println("equals"); return true }
            }
            fun main() {
                val strange = Strange()
                println(strange == null)
                println(null == strange)
                println(strange.equals(null))
            }
            """, expected: "false\nfalse\nequals\ntrue\n", mode: .jvmJar, root: root)
        }
    }

    @Test
    func generatedClassExtendsExternalJavaClass() throws {
        try withWorkspace { root in
            let dependency = try javaFixture(root)
            let result = try compile("""
            import dep.Counter
            import dep.Named
            class Local(value: Int): Counter(value) {
                override fun name(): String = "local"
                override fun add(amount: Int): Int = super.add(amount) + 1
            }
            fun main() {
                val counter: Counter = Local(4)
                println(counter.add(2))
                val named: Named = counter
                println(named.name())
            }
            """, root: root, mode: .jvmJar, classpath: [dependency.path])
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }
            #expect(try java(["-cp", root.appendingPathComponent("hello.jar").path + ":" + dependency.path, "HelloKt"]).stdout == "7\nlocal\n")
        }
    }

    @Test(arguments: [
        "class Generic<reified T>",
        "class C(val x: Nothing?)", "class C { val x = null }",
        "interface I { private fun helper(): Int = 1; fun run(): Int = helper() }",
        "interface I { fun missing(): Int }; class C: I", "class C(val x: Int); fun main() { C(1).x = 2 }",
        "class C { private val x = 1 }; fun main() { println(C().x) }",
        "class C { fun getX(): Int = 1; val x = 2 }",
        "class C { @Missing val x = 1 }", "class C { init { println(1) garbage } }",
        "class C { val x: Int = 0; get() { field++; return field } }",
    ])
    func rejectsUnsupportedOrInvalidM4WithoutOutput(source: String) throws {
        try withWorkspace { root in
            let output = root.appendingPathComponent("hello.jar"), previous = Data("previous output".utf8)
            try previous.write(to: output)
            let result = try compile(source, root: root, mode: .jvmJar)
            #expect(result.0 == 1)
            #expect(!result.1.contains { $0.code.hasPrefix("KSWIFTK-ICE") })
            #expect(try Data(contentsOf: output) == previous)
        }
    }
}
#endif
