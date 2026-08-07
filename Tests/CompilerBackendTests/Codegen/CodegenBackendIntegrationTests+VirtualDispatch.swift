@testable import CompilerBackend
@testable import CompilerCore
import XCTest

extension CodegenBackendIntegrationTests {
    func testOpenClassVirtualDispatchChoosesConcreteOverride() throws {
        let source = """
        open class Animal {
            open fun speak(): String = "base"
        }
        class Dog : Animal() {
            override fun speak(): String = "dog"
        }
        class Cat : Animal() {
            override fun speak(): String = "cat"
        }
        fun callSpeak(animal: Animal): String = animal.speak()
        fun main() {
            println(callSpeak(Dog()))
            println(callSpeak(Cat()))
            println(callSpeak(Animal()))
        }
        """
        try assertKotlinOutput(source, moduleName: "OpenClassVirtualDispatchRuntime", expected: "dog\ncat\nbase\n")
    }

    // BUG-156: the interface method implemented by the abstract base must be
    // reachable through the concrete subclass' itable, and the base's
    // unqualified `compute()` must reach the subclass override.
    func testInterfaceMethodInheritedFromAbstractBaseDispatchesThroughItable() throws {
        let source = """
        interface Box<T> {
            fun get(): T
        }
        abstract class AbstractBox<T> : Box<T> {
            abstract fun compute(): T
            override fun get(): T = compute()
        }
        class IntBox(val v: Int) : AbstractBox<Int>() {
            override fun compute(): Int = v
        }
        fun accept(b: Box<Int>): Int = b.get()
        fun main() {
            val box = IntBox(7)
            println(box.get())
            println(accept(box))
        }
        """
        try assertKotlinOutput(source, moduleName: "InheritedInterfaceItableDispatchRuntime", expected: "7\n7\n")
    }

    func testUnqualifiedSelfCallDispatchesToSubclassOverride() throws {
        let source = """
        abstract class Greeter {
            abstract fun name(): String
            fun greet(): String = "hello " + name()
        }
        class Named : Greeter() {
            override fun name(): String = "world"
        }
        fun main() {
            println(Named().greet())
        }
        """
        try assertKotlinOutput(source, moduleName: "UnqualifiedSelfCallDispatchRuntime", expected: "hello world\n")
    }
}
