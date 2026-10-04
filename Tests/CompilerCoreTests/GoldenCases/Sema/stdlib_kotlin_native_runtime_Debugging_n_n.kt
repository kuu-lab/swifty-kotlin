package golden.sema

import kotlin.native.runtime.Debugging

@OptIn(kotlin.native.runtime.NativeRuntimeApi::class)
fun debuggingSingleton(): Debugging = Debugging
