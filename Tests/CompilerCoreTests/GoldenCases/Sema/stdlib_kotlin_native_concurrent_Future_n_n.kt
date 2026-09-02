@file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)

import kotlin.native.concurrent.Future

fun preserveFuture(future: Future<Int>): Future<Int> = future
