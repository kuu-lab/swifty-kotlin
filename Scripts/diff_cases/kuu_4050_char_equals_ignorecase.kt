import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.Job
import kotlinx.coroutines.job
import kotlinx.coroutines.isActive

// KUU-4050: Char.equals(other, ignoreCase) extension + CoroutineContext.job
// extension property. `ctx.job()` is intentionally absent — upstream exposes
// `job` as a val, so the call form is invalid Kotlin on JVM too.

fun checkContext(ctx: CoroutineContext) {
    println(ctx.job.isActive)
    println(ctx.job.isCompleted)
    println(ctx.isActive)
}

fun main() {
    // Char.equals(Char, ignoreCase) — positional and named-argument forms
    println('A'.equals('a', true))              // true
    println('A'.equals('a', ignoreCase = true)) // true
    println('A'.equals('b', true))              // false
    println('a'.equals('a', false))             // true
    println('a'.equals('A', false))             // false
    println('A'.equals('a'))                    // false (member equals, ignoreCase=false)
    println('a'.equals('a'))                    // true

    // Case-fold edges: two-step upper-then-lower comparison
    println('K'.equals('K', true))    // true: Kelvin sign folds to 'k'
    println('K'.equals('K'))           // false
    println('i'.equals('I', true))              // true
    println('i'.equals('İ', true))     // true: lower(upper('İ')) == 'i'
    println('ı'.equals('I', true))     // true: upper('ı') == 'I'
    println('ß'.equals('ẞ', true))    // true: lower(upper('ẞ')) == 'ß'
    println('ß'.equals('S', true))              // false
    println('ﬀ'.equals('F', true))    // false: ligature has no char-level fold
    println('σ'.equals('Σ', true))              // true
    println('ς'.equals('Σ', true))              // true
    println('σ'.equals('ς', true))              // true
    println('ǅ'.equals('Ǆ', true))    // true: titlecase vs uppercase
    println('ǅ'.equals('ǆ', true))    // true
    println('x'.equals('Y', true))              // false

    // CoroutineContext.job extension property resolves and reports the job
    val job = Job()
    checkContext(job)
    println(job.isActive)                       // true
    job.complete()
    println(job.isActive)                       // false
    checkContext(job)
}
