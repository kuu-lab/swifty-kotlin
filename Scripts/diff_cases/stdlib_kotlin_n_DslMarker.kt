import kotlin.DslMarker

@DslMarker
annotation class HtmlDsl

@HtmlDsl
class HTML {
    var content = ""
    fun body(text: String) {
        content = text
    }
}

fun main() {
    val html = HTML()
    html.body("hello")
    println(html.content)
}
