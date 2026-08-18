package golden.sema

@DslMarker
annotation class HtmlDsl

@HtmlDsl
class HTML

fun useDslMarker(): HTML = HTML()
