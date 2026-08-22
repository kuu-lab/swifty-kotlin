// A statically class-typed or value-class-typed value must call its own
// toString() when stringified via template interpolation ("$x"), the `+`
// concatenation operator, or `+=` compound assignment -- not just via an
// explicit `.toString()` call or a `println(x)` argument.
//
// Both interpolation/concatenation and data class toString() synthesis share
// the same underlying problem: a class reference is a heap pointer and a
// non-nullable value class is its raw unboxed underlying primitive, and
// neither representation carries enough information for the generic
// Any-fallback string conversion to recover on its own. A heap pointer this
// renderer doesn't recognize prints as "<object 0x...>"; a value class's raw
// primitive prints as if it were an ordinary Int/Long. This is the
// class/value-class counterpart to enum_string_interpolation.kt's bare-ordinal
// bug -- string conversion must resolve and call the value's own toString()
// instead of falling back to the generic tag-based path.
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

data class DurationBox(val d: Duration)
data class LabeledBox(val box: DurationBox, val tag: Int)

enum class Priority { LOW, MEDIUM, HIGH }
data class Task(val name: String, val priority: Priority)

class Wrapper(val value: Int) {
    override fun toString(): String = "Wrapper($value)"
}

fun main() {
    val f = DurationBox(5.seconds)
    println("literal: $f")
    println("concat: " + f.d)
    var appended = "value="
    appended += f
    println(appended)
    var appendedDuration = "dur="
    appendedDuration += f.d
    println(appendedDuration)
    println("explicit toString: " + f.toString())
    println(f)

    // Nested data class: the field renderer must recurse into DurationBox's
    // own (synthesized) toString() rather than stopping at the first level.
    val nested = LabeledBox(DurationBox(90.seconds), 3)
    println(nested)
    println("nested: $nested")

    // A data class property typed as an enum: DataEnumSealedSynthesisPass's
    // toString() synthesis must render the entry name, not the bare ordinal.
    val task = Task("ship", Priority.HIGH)
    println(task)
    println("task: $task")

    // A plain (non-data) class with a user-defined toString().
    val w = Wrapper(42)
    println("wrapper: $w")
    println("wrapper concat: " + w)

    // Nullable value class and nullable data class, both holding a real value.
    val d2: Duration? = 5.seconds
    println("nullable duration: $d2")
    val f2: DurationBox? = f
    println("nullable box: $f2")

    // Nullable value class and nullable data class, both actually null: must
    // still render "null", not attempt to call toString() on a null receiver.
    val d3: Duration? = null
    println("null duration: $d3")
    val f3: DurationBox? = null
    println("null box: $f3")
}
