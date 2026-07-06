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
}
