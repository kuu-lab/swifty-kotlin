package golden.sema

import kotlin.native.runtime.NativeRuntimeApi

@OptIn(NativeRuntimeApi::class)
@NativeRuntimeApi
fun nativeRuntimeApiSurface() {}

@OptIn(NativeRuntimeApi::class)
fun main() {
    nativeRuntimeApiSurface()
    println("native_runtime_api_ok=true")
}
