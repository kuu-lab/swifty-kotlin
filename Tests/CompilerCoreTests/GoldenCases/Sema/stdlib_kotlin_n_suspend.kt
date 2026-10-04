package golden.sema

suspend fun sourceSuspend(): String = "ok"

fun makeSuspendFunction(): suspend () -> String =
    suspend { sourceSuspend() }
