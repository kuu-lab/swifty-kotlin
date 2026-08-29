@file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)

import kotlin.native.concurrent.Worker

fun workerCompanionType(): Worker.Companion = Worker.Companion

fun passWorker(worker: Worker): Worker = worker
