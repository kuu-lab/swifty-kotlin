// KUU-1386: kotlinx's Job implementations all extend JobSupport, so
// launch/Job()/SupervisorJob()/async results satisfy is JobSupport,
// is ChildJob and is ParentJob, and `as ParentJob` casts succeed.
@file:Suppress("DEPRECATION", "DEPRECATION_ERROR")

import kotlinx.coroutines.*

@OptIn(InternalCoroutinesApi::class)
fun family(j: Job, name: String) {
    println("$name JobSupport=${j is JobSupport} ChildJob=${j is ChildJob} ParentJob=${j is ParentJob}")
    val p = j as ParentJob
    println("$name cast=ok")
}

@OptIn(InternalCoroutinesApi::class)
fun main() = runBlocking {
    family(launch { }, "launch")
    family(Job(), "Job")
    family(SupervisorJob(), "SupervisorJob")
    family(async { 1 }, "async")

    val child = Job(Job())
    family(child, "parented-Job")

    // Job.Key singleton: key/get/fold/minusKey on raw job objects.
    val j: Job = Job()
    println("key-identity=${j.key == Job}")
    val ctx = j + CoroutineName("n")
    println("ctx-Job-same=${ctx[Job] == j}")
    println("ctx-minus=${ctx.minusKey(Job)[Job] == null}")

    // attachChild produces a ChildHandle whose dispose detaches.
    val parent = Job()
    val kid = Job() as ChildJob
    val handle = parent.attachChild(kid)
    println("attach=ok handle-parent=${handle.parent == parent}")
    handle.dispose()
    println("disposed=ok")
    println("done")
}
