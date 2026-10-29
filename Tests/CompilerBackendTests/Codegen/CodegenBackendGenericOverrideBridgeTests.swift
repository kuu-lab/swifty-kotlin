#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct CodegenBackendGenericOverrideBridgeTests {
    private func source(_ filename: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent("Scripts/diff_cases/\(filename).kt"),
            encoding: .utf8
        )
    }

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
    func testGenericPropertyGetterBridgeRejectsWrongTypeArgument() throws {
        try assertKotlinOutput(
            source("kuu_3670_generic_property_bridge_test20"),
            moduleName: "KUU3670GenericPropertyGetterBridge",
            expected: "OK\n"
        )
    }

    @Test
    func testGenericNullablePropertySetterAndGetterBridgeRejectWrongType() throws {
        try assertKotlinOutput(
            source("kuu_3670_generic_property_bridge_test21"),
            moduleName: "KUU3670GenericNullablePropertyBridge",
            expected: "OK\n"
        )
    }

    @Test
    func testGenericOverrideBridgeWithNothingParameter() throws {
        try assertKotlinOutput(
            source("kuu_3670_generic_property_bridge_test24"),
            moduleName: "KUU3670GenericNothingOverrideBridge",
            expected: "OK\n"
        )
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
    func testNullableValueClassPayloadThroughGenericSuperclassCallback() throws {
        let source = """
        inline fun <T, R> T?.let(block: (T) -> R): R? {
            if (this == null) return null
            return block(this)
        }
        abstract class C<T> {
            fun foo(v: T?, x: (T) -> Any?) = v?.let { x(it) }
        }
        value class V(val value: Any?)
        class D : C<V>()
        class Payload
        fun main() {
            val expected = Payload()
            val result = D().foo(V(expected)) { it.value }
            if (result !== expected) {
                val divisor = 0
                1 / divisor
            }
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "NullableValueClassGenericSuperclassCallback",
            expected: "",
            includeStdlib: false,
            allowDefaultStdlibLibrary: false,
            prepareTestStdlibCache: false
        )
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

    // KUU-3670: kotlin/testData/codegen/box/bridges/test20.kt — a `val s: T`
    // declared in a generic base travels through the erased slot, so the read
    // at the substituted claim site (`A<Data>`) must checkcast the result.
    @Test
    func testGenericBaseValReadCheckcastsErasedResult() throws {
        let source = """
        open class A<T> {
            val s: T = "zzz" as T
        }
        interface C {
            val s: String
        }
        class B : C, A<String>()
        class Data(val x: Int)
        fun box(): String {
            val b = B()
            try {
                val s = (b as A<Data>).s
                return "FAIL: ${'$'}{s.x}"
            } catch (e: ClassCastException) {
                return "OK"
            }
        }
        fun main() {
            println(box())
        }
        """
        try assertKotlinOutput(source, moduleName: "GenericBaseValReadCheckcast", expected: "OK\n")
    }

    // KUU-3670: kotlin/testData/codegen/box/bridges/test21.kt — a raw write
    // through the wrongly-parameterized reference stores a Data into the
    // `var x: T?` slot; the typed `String?` read must then checkcast.
    @Test
    func testGenericBaseVarReadCheckcastsErasedResult() throws {
        let source = """
        open class Base<T> {
            open var x: T? = null
        }
        open class Derived : Base<String>()
        class Data(val x: Int)
        fun garble(d: Derived) {
            (d as Base<Data>).x = Data(42)
        }
        fun box(): String {
            val d = Derived()
            garble(d)
            try {
                val x = d.x
                return "FAIL: ${'$'}{x?.length}"
            } catch (e: ClassCastException) {
                return "OK"
            }
        }
        fun main() {
            println(box())
        }
        """
        try assertKotlinOutput(source, moduleName: "GenericBaseVarReadCheckcast", expected: "OK\n")
    }

    // KUU-3670: kotlin/testData/codegen/box/bridges/test24.kt — an override
    // narrowing an erased interface parameter to Nothing needs an itable
    // bridge that checkcasts the argument (always failing for non-null).
    @Test
    func testNothingParameterItableBridgeCheckcastsArgument() throws {
        let source = """
        interface I<T> {
            fun foo(p: T)
        }
        class C : I<Nothing> {
            override fun foo(p: Nothing) {
                println(p.toString())
            }
        }
        fun box(): String {
            val c = C()
            try {
                val x = (c as I<String>).foo("zzz")
                return "FAIL: ${'$'}x"
            } catch (e: ClassCastException) {
                return "OK"
            }
        }
        fun main() {
            println(box())
        }
        """
        try assertKotlinOutput(source, moduleName: "NothingParamItableBridgeCheckcast", expected: "OK\n")
    }
}
#endif
