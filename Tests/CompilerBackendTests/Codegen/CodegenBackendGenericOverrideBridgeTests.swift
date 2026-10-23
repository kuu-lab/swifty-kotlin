#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct CodegenBackendGenericOverrideBridgeTests {
    @Test
    func testGenericOverrideBridgeBoxesUnitForAnyReturn() throws {
        let source = """
        abstract class A { abstract fun foo(): Any }
        class B : A() { override fun foo() {} }
        fun main() {
            val value: A = B()
            println(value.foo() === Unit)
        }
        """
        try assertKotlinOutput(source, moduleName: "GenericOverrideUnitReturn", expected: "true\n")
    }

    @Test
    func testInheritedGenericPropertyImplementsConcreteInterfaceProperty() throws {
        let source = """
        interface HasSize { var size: Int }
        open class Generic<T>(open var size: T)
        class IntSize : Generic<Int>(56), HasSize
        fun main() {
            val value: IntSize = IntSize()
            val sized: HasSize = value
            sized.size = 81
            println(value.size)
            println(sized.size)
        }
        """
        try assertKotlinOutput(source, moduleName: "GenericOverridePropertyBridge", expected: "81\n81\n")
    }

    @Test
    func testGenericMemberExtensionOverrideBridge() throws {
        let source = """
        interface ExtensionScope<T> { fun <R> R.append(value: T): String }
        class StringScope : ExtensionScope<String> {
            override fun <R> R.append(value: String): String = value
        }
        fun ExtensionScope<String>.result(): String = "O".append("K")
        fun main() {
            val scope: ExtensionScope<String> = StringScope()
            println(scope.result())
        }
        """
        try assertKotlinOutput(source, moduleName: "GenericMemberExtensionBridge", expected: "K\n")
    }

    @Test
    func testGenericOverrideThroughIntermediateSuperCall() throws {
        let source = """
        open class A<T> { open fun foo(value: T): T = value }
        open class B : A<String>()
        class C : B() {
            override fun foo(value: String): String = super.foo(value) + "K"
        }
        fun main() {
            val value: A<String> = C()
            println(value.foo("O"))
        }
        """
        try assertKotlinOutput(source, moduleName: "GenericOverrideSuperBridge", expected: "OK\n")
    }

    @Test
    func testInheritedGenericMethodImplementsConcreteInterfaceMethod() throws {
        let source = """
        interface IntTransform { fun transform(value: Int): Int }
        open class GenericTransform<T> { open fun transform(value: T): T = value }
        class IntTransformImpl : GenericTransform<Int>(), IntTransform
        fun main() {
            val transform: IntTransform = IntTransformImpl()
            println(transform.transform(37))
        }
        """
        try assertKotlinOutput(source, moduleName: "GenericFakeOverrideBridge", expected: "37\n")
    }

    @Test
    func testGenericOverrideBridgeAcrossLongClassChain() throws {
        let source = """
        open class A<T> { open fun foo(value: T): String = "A" }
        open class B<T> : A<T>()
        open class C : B<String>() { override fun foo(value: String): String = "C" }
        open class D : C()
        class Z : D() { override fun foo(value: String): String = "Z" }
        fun main() {
            val value: A<String> = Z()
            println(value.foo("ignored"))
        }
        """
        try assertKotlinOutput(source, moduleName: "GenericLongOverrideBridge", expected: "Z\n")
    }

    @Test
    func testCovariantAbstractDeclarationsKeepMostSpecificImplementation() throws {
        let source = """
        abstract class A { abstract fun foo(): Any }
        abstract class B : A() { abstract override fun foo(): String }
        class C : B() { override fun foo(): String = "OK" }
        fun main() {
            val value: A = C()
            println(value.foo())
        }
        """
        try assertKotlinOutput(source, moduleName: "GenericCovariantAbstractBridge", expected: "OK\n")
    }
}
#endif
