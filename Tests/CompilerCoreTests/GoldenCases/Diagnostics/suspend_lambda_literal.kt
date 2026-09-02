package golden.diagnostics

suspend fun sourceSuspend(): String = "ok"

fun makeSuspendFunction(): suspend () -> String =
    suspend { sourceSuspend() }
