import java.util.Locale
import kotlin.reflect.KFunction

fun sourceWords(vararg words: String): Array<out String> = words
inline fun forwardedWords(vararg words: String): Array<out String> = words
