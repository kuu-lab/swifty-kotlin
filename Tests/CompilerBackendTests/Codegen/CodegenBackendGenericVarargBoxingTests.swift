#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendGenericVarargBoxingTests {
    @Test
    func genericIdentityDoesNotReexecuteBoundedValueClassInitializer() throws {
        try assertKotlinOutput(
            """
            @JvmInline
            value class IC<T: Int>(val i: T) {
                init { counter += i }
            }
            var counter = 0
            fun <T> id(t: T) = t

            fun main() {
                val ic = IC(42)
                counter = 0
                id(ic)
                println(counter)
            }
            """,
            moduleName: "KUU3409GenericValueClassInitThroughIdentity",
            expected: "0\n"
        )
    }

    @Test
    func genericIdentityDoesNotReexecuteBoundedValueClassInitializerWithoutStdlib() throws {
        try assertKotlinOutput(
            """
            annotation class JvmInline
            @JvmInline
            value class IC<T: Int>(val i: T) {
                init { counter += i }
            }
            var counter = 0
            fun <T> id(t: T) = t

            fun main() {
                val ic = IC(42)
                counter = 0
                id(ic)
                if (counter != 0) {
                    val failure: Any? = null
                    failure!!
                }
            }
            """,
            moduleName: "KUU3409GenericValueClassInitWithoutStdlib",
            expected: "",
            includeStdlib: false,
            allowDefaultStdlibLibrary: false,
            prepareTestStdlibCache: false
        )
    }

    @Test
    func boundedGenericValueClassInitializerControlWithoutIdentityCall() throws {
        try assertKotlinOutput(
            """
            annotation class JvmInline
            @JvmInline
            value class IC<T: Int>(val i: T) {
                init { counter += i }
            }
            var counter = 0

            fun main() {
                val ic = IC(42)
                if (counter != 42) {
                    val failure: Any? = null
                    failure!!
                }
                counter = 0
            }
            """,
            moduleName: "KUU3409GenericValueClassInitControlWithoutIdentity",
            expected: "",
            includeStdlib: false,
            allowDefaultStdlibLibrary: false,
            prepareTestStdlibCache: false
        )
    }

    @Test
    func primitiveAndBoundedValueClassValuesAreBoxedIntoGenericVararg() throws {
        try assertKotlinOutput(
            """
            fun <T> anyVararg(vararg x: T): Boolean = x[0] == 123f
            fun boxingNullablePrimitiveToAny(x: Float?) = x !== null && anyVararg(x)
            fun boxingPrimitiveToAny(x: Float) = anyVararg(x)
            value class InlineFloat(val value: Float)
            fun <T : InlineFloat> valueClassAnyVararg(vararg x: T): Boolean = x[0].value == 123f
            fun boxingInlineClassToAny(x: InlineFloat) = valueClassAnyVararg(x)

            fun main() {
                println(boxingPrimitiveToAny(123f))
                println(boxingNullablePrimitiveToAny(123f))
                println(boxingNullablePrimitiveToAny(null))
                println(boxingInlineClassToAny(InlineFloat(123f)))
            }
            """,
            moduleName: "KUU2922GenericVarargBoxing",
            expected: "true\ntrue\nfalse\ntrue\n"
        )
    }
}
#endif
