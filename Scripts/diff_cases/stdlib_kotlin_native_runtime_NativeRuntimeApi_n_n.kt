// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.* APIs are Kotlin/Native-only and are not available in JVM kotlinc.
import kotlin.native.runtime.NativeRuntimeApi

@OptIn(NativeRuntimeApi::class)
@NativeRuntimeApi
fun nativeRuntimeApiSurface() {}

fun main() {
    nativeRuntimeApiSurface()
    println("native_runtime_api_ok=true")
}
