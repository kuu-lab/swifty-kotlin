@PublishedApi
internal fun publishedApiValue(): Int = 42

public inline fun callPublishedApi(): Int = publishedApiValue()

fun main() {
    println(callPublishedApi())
}
