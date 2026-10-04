// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.concurrent APIs require a Kotlin/Native reference target.
@file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)
@file:Suppress("DEPRECATION_ERROR")

import kotlin.native.concurrent.Future

fun waitForFutureCollection(
    futures: Collection<Future<Int>>
): Set<Future<Int>> = futures.waitForMultipleFutures(0)

fun main() {}
