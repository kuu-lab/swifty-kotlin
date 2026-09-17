@file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)
@file:Suppress("DEPRECATION_ERROR")

package golden.sema

import kotlin.native.concurrent.Future

fun waitForFutureCollection(
    futures: Collection<Future<Int>>
): Set<Future<Int>> = futures.waitForMultipleFutures(0)
