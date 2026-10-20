#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func reflectedReturnTypesRenderLogicalKotlinMetadata(mode: EmitMode) throws {
        try withWorkspace { root in
            try runRuntimeParity("""
            import kotlin.reflect.KCallable
            class Sample(val value: Int)
            fun answer(): String = "answer"
            fun optional(): String? = null
            fun nested(): List<String?> = listOf("value", null)
            fun star(): List<*> = listOf(1)
            fun callback(): ((Int) -> String)? = null
            fun extension(): String.(Int) -> String = { n -> this + n.toString() }
            fun <T> identity(value: T): T = value
            fun read(callable: KCallable<*>): String = callable.returnType.toString()
            fun main() {
                println(read(::answer)); println(read(Sample::value))
                println(read(::optional)); println(read(::nested)); println(read(::star))
                println(read(::callback)); println(read(::extension))
                val generic: (String) -> String = ::identity
                println(read(generic as KCallable<*>))
                println(Sample::class.constructors.iterator().next().returnType.toString())
                println((null as KCallable<*>?)?.returnType == null)
            }
            """, expected: "kotlin.String\nkotlin.Int\nkotlin.String?\nkotlin.collections.List<kotlin.String?>\nkotlin.collections.List<*>\n((kotlin.Int) -> kotlin.String)?\nkotlin.String.(kotlin.Int) -> kotlin.String\nT\nSample\ntrue\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func reflectedFunctionReceiversMatchForeignSuspendMetadata(mode: EmitMode) throws {
        try withWorkspace { root in
            try runRuntimeParity("""
            fun callbackReceiver(): ((Int) -> String).() -> Unit = {}
            fun nullableCallbackReceiver(): (((Int) -> String)?).() -> Unit = {}
            fun suspendCallbackReceiver(): (suspend (Int) -> String).() -> Unit = {}
            fun nullableSuspendCallbackReceiver(): ((suspend (Int) -> String)?).() -> Unit = {}
            fun extensionReceiver(): (String.(Int) -> Boolean).() -> Unit = {}
            fun ordinaryReceiver(): String.() -> Unit = {}
            fun main() {
                println(::callbackReceiver.returnType.toString())
                println(::nullableCallbackReceiver.returnType.toString())
                println(::suspendCallbackReceiver.returnType.toString())
                println(::nullableSuspendCallbackReceiver.returnType.toString())
                println(::extensionReceiver.returnType.toString())
                println(::ordinaryReceiver.returnType.toString())
            }
            """, expected: "(kotlin.Int) -> kotlin.String.() -> kotlin.Unit\n((kotlin.Int) -> kotlin.String)?.() -> kotlin.Unit\nsuspend (kotlin.Int) -> kotlin.String.() -> kotlin.Unit\n(suspend (kotlin.Int) -> kotlin.String)?.() -> kotlin.Unit\nkotlin.String.(kotlin.Int) -> kotlin.Boolean.() -> kotlin.Unit\nkotlin.String.() -> kotlin.Unit\n", mode: mode, root: root)
        }
    }
}
#endif
