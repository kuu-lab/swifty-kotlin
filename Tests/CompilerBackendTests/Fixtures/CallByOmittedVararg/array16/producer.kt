import kotlin.reflect.KFunction

val controlDefault: Array<String> = arrayOf("d", "e")
fun controlWords(vararg words: String = controlDefault): Array<out String> = words
fun controlInts(vararg values: Int): IntArray = values
fun controlNullable(vararg words: String?): Array<out String?> = words
fun <T> controlGeneric(vararg values: T): Array<out T> = values
fun <T : CharSequence> controlBound(vararg values: T): Array<out T> = values
class ControlCtor(vararg val words: String)
fun controlRejected(action: () -> Unit): String = try { action(); "OK" } catch (_: IllegalArgumentException) { "IAE" }
