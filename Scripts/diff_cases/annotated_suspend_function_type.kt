@Target(AnnotationTarget.TYPE)
annotation class TypeAnno

@Target(AnnotationTarget.TYPE)
annotation class OtherAnno

// KUU-4107: `suspend` is a type modifier, so type-position annotations may
// still follow it (`suspend @Anno () -> Unit`), exactly as they precede it.
val plain: suspend @TypeAnno () -> Unit = {}
val typed: suspend @TypeAnno (Int) -> Unit = { }
val receiver: suspend @TypeAnno Int.() -> Unit = { }
val nullableReceiver: suspend @TypeAnno Int?.() -> Unit = { }
val sandwiched: @TypeAnno suspend @OtherAnno () -> Unit = {}
val nullableWhole: (suspend @TypeAnno () -> Unit)? = null

fun takesSuspend(f: suspend @TypeAnno (Int) -> Unit) = f
fun returnsSuspend(): suspend @TypeAnno () -> Unit = plain

fun main() {
    takesSuspend { }
    println("ok")
}
