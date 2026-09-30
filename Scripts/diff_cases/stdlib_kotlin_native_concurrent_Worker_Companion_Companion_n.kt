// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.concurrent APIs require a Kotlin/Native reference target.
@file:OptIn(
    kotlin.native.concurrent.ObsoleteWorkersApi::class,
    kotlin.ExperimentalStdlibApi::class
)

import kotlinx.cinterop.COpaquePointer
import kotlin.native.concurrent.Worker

fun workerCompanionSurface(): Worker {
    val current: Worker = Worker.current
    val viaCompanion: Worker = Worker.Companion.current
    val active: List<Worker> = Worker.activeWorkers
    val activeViaCompanion: List<Worker> = Worker.Companion.activeWorkers
    val started: Worker = Worker.start()
    val named: Worker = Worker.Companion.start(errorReporting = false, name = "companion-worker")
    named.requestTermination()
    return if (active.isEmpty() || activeViaCompanion.isEmpty() || current.id == viaCompanion.id) {
        started
    } else {
        viaCompanion
    }
}

fun workerFromCPointerSurface(worker: Worker): Worker {
    val pointer: COpaquePointer? = worker.asCPointer()
    val resolved: Worker = Worker.fromCPointer(pointer)
    val resolvedViaCompanion: Worker = Worker.Companion.fromCPointer(pointer)
    return if (resolved.id == resolvedViaCompanion.id) resolved else worker
}

fun main() {}
