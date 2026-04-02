import java.util.Locale
import java.util.getBundle

fun main() {
    val bundle = getBundle("messages", Locale("ja_JP"))
    println(bundle.getString("greeting"))
    println(bundle.getObject("greeting"))
    println(bundle.getKeys().joinToString(","))
}
