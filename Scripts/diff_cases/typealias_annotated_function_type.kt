@Target(AnnotationTarget.TYPE)
annotation class TypeAnno

// KUU-4109: `(…)` after an annotation name is the function type's parameter
// list when the matching `)` is followed by `->`, not annotation arguments.
typealias Handler = @TypeAnno (navigator: Int) -> Unit
typealias EmptyHandler = @TypeAnno () -> Unit
typealias SuspendedHandler = @TypeAnno suspend () -> Unit
typealias NullableHandler = (@TypeAnno () -> Unit)?
typealias AnnotatedParam = (item: @TypeAnno () -> Int) -> Unit

fun accept(f: SuspendedHandler) = println("susp accepted")

fun main() {
    val handler: Handler = { navigator -> println("nav=$navigator") }
    handler(7)
    val empty: EmptyHandler = { println("empty") }
    empty()
    val suspended: SuspendedHandler = { println("susp") }
    accept(suspended)
    val nullable: NullableHandler = { println("nullable") }
    nullable?.invoke()
    val param: AnnotatedParam = { item -> println("param=${item()}") }
    param { 3 }
}
