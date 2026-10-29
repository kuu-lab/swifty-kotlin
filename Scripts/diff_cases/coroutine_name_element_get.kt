// KUU-3752: `CoroutineContext.get`/`[key]` on a CoroutineName- or Job-typed
// receiver bridged to kk_context_get, which returned raw 0 for an absent
// key. Raw 0 crosses the erased `E?` boundary as kotlin.Unit, so the erased
// cast threw ClassCastException instead of yielding null.
import kotlin.coroutines.ContinuationInterceptor
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext
import kotlinx.coroutines.CoroutineName
import kotlinx.coroutines.Job

fun main() {
    val cn = CoroutineName("x")
    // Absent key on a CoroutineName receiver: null, not Unit.
    println(cn.get(ContinuationInterceptor) == null)
    println(cn[ContinuationInterceptor] == null)
    println(cn.get(Job) == null)
    // Matching key returns the element itself.
    println(cn.get(CoroutineName) === cn)
    println(cn[CoroutineName] === cn)
    println(cn.get(CoroutineName)?.name)

    // Same absent/found split through a Job receiver — Job() is a source
    // object whose inherited `get` also bridged to kk_context_get.
    val j: Job = Job()
    println(j.get(CoroutineName) == null)
    println(j[CoroutineName] == null)
    println(j.get(ContinuationInterceptor) == null)
    println(j.get(Job) != null)
    println(j[Job] != null)

    // The static CoroutineContext/Element supertypes dispatch through the
    // interface path; keep the same lookups covered there.
    val asContext: CoroutineContext = cn
    println(asContext.get(CoroutineName)?.name)
    println(asContext.get(ContinuationInterceptor) == null)
    val asElement: CoroutineContext.Element = cn
    println(asElement.get(ContinuationInterceptor) == null)
    val asJobContext: CoroutineContext = j
    println(asJobContext.get(CoroutineName) == null)
    println(asJobContext.get(Job) != null)

    // Element lookup inside a combined context.
    val named = EmptyCoroutineContext + cn
    println(named[CoroutineName]?.name)
    println(named[ContinuationInterceptor] == null)
    println(named[Job] == null)
}
