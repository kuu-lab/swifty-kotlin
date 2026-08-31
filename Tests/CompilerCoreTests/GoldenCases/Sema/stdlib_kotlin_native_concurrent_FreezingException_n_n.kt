package golden.sema

@Suppress("DEPRECATION_ERROR")
fun construct(toFreeze: Any, blocker: Any): RuntimeException =
    kotlin.native.concurrent.FreezingException(toFreeze, blocker)
