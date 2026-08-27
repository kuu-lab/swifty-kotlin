// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.concurrent APIs require a Kotlin/Native reference target.
@file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)

import kotlin.native.concurrent.Worker

fun workerCompanionType(): Worker.Companion = Worker.Companion

fun passWorker(worker: Worker): Worker = worker

fun main() {}
