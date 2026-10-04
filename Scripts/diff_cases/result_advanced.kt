fun main() {
    // 1. recoverCatching on failure - transform succeeds
    val fail1 = runCatching { throw RuntimeException("original") }
    val rec1 = fail1.recoverCatching { -1 }
    println("recoverCatching success: ${rec1.getOrNull()}")
    println("recoverCatching isSuccess: ${rec1.isSuccess}")

    // 2. recoverCatching on success - passes through
    val succ1 = runCatching { 42 }
    val rec2 = succ1.recoverCatching { -1 }
    println("recoverCatching passthrough: ${rec2.getOrNull()}")

    // 3. recoverCatching on failure - transform itself throws
    val fail2 = runCatching { throw RuntimeException("fail2") }
    val rec3 = fail2.recoverCatching { throw RuntimeException("transform threw") }
    println("recoverCatching transform threw isFailure: ${rec3.isFailure}")
    println("recoverCatching transform exception: ${rec3.exceptionOrNull()?.message}")

    // 4. recover on failure - basic
    val fail3 = runCatching { throw RuntimeException("recover me") }
    val rec4 = fail3.recover { 99 }
    println("recover value: ${rec4.getOrNull()}")
    println("recover isSuccess: ${rec4.isSuccess}")

    // 5. recover on success - passes through
    val succ2 = runCatching { 77 }
    val rec5 = succ2.recover { 0 }
    println("recover passthrough: ${rec5.getOrNull()}")

    // 5b. recover on failure - transform itself throws outward
    val failRecoverThrow = runCatching { throw RuntimeException("recover source") }
    val recoverThrowOutcome = runCatching {
        failRecoverThrow.recover { throw RuntimeException("recover transform threw") }.getOrThrow()
    }
    println("recover transform threw captured: ${recoverThrowOutcome.isFailure}")
    println("recover transform exception: ${recoverThrowOutcome.exceptionOrNull()?.message}")

    // 6. onSuccess on success
    val succ5 = runCatching { 10 }
    succ5.onSuccess { println("onSuccess: $it") }

    // 7. onFailure on failure
    val fail6 = runCatching { throw RuntimeException("side effect") }
    fail6.onFailure { println("onFailure: ${it.message}") }

    // 8. chained onSuccess + onFailure
    runCatching { 5 }
        .onSuccess { println("chain success: $it") }
        .onFailure { println("chain fail unexpected") }

    runCatching { throw RuntimeException("chain err") }
        .onSuccess { println("chain2 success unexpected") }
        .onFailure { println("chain2 fail: ${it.message}") }
}
