class LambdaOuter {
    inner class Inner(val block: String.() -> String) {
        fun render(text: String) = block(text)
    }

    inner class WithDefault(val n: Int = 7, val block: String.() -> String) {
        fun render(text: String) = block(text) + n
    }
}

fun render(suffix: String) {
    val outer = LambdaOuter()
    val inner = outer.Inner { this + suffix }
    println(inner.render("direct"))
    val withDefault = outer.WithDefault { this + suffix }
    println(withDefault.render("default"))

    val present: LambdaOuter? = outer
    val safeInner = present?.Inner { this + suffix }
    println(safeInner?.render("safe"))
    val safeDefault = present?.WithDefault { this + suffix }
    println(safeDefault?.render("safe-default"))
    val absent: LambdaOuter? = null
    val skipped = absent?.Inner { this + suffix }
    println(skipped?.render("absent"))
}

fun main() {
    render("-one")
    render("-two")
}
