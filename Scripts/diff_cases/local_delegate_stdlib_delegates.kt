// BUG-147: local `by Delegates.*` used to bind the local to the delegate handle itself.
import kotlin.properties.Delegates

fun main() {
    var observed by Delegates.observable(1) { _, old, new ->
        println("observed $old -> $new")
    }
    println(observed)
    observed = 5
    println(observed)
    observed += 4
    println(observed)

    var vetoed by Delegates.vetoable(1) { _, _, new -> new > 0 }
    vetoed = 7
    println(vetoed)

    var required by Delegates.notNull<Int>()
    required = 3
    println(required)
}
