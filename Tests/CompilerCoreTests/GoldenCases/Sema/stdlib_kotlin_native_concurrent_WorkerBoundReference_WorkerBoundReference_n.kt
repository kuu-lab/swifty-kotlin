@file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)
@file:Suppress("DEPRECATION_ERROR")

import kotlin.native.concurrent.Worker
import kotlin.native.concurrent.WorkerBoundReference

fun workerBoundReferenceValue(ref: WorkerBoundReference<String>): String = ref.value
fun workerBoundReferenceValueOrNull(ref: WorkerBoundReference<String>): String? = ref.valueOrNull
fun workerBoundReferenceWorker(ref: WorkerBoundReference<String>): Worker = ref.worker
