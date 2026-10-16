// KUU-2322: an inherited interface member-extension operator must outrank a
// top-level operator with the same extension receiver.
package kuu2322

interface Tag {
    operator fun String.unaryPlus() {
        print("interface:")
        print(this)
    }
}

class HtmlTag : Tag

fun HtmlTag.render(content: String) {
    +content
    content.unaryPlus()
}

class OverridingHtmlTag : Tag {
    override operator fun String.unaryPlus() {
        print("override:")
        print(this)
    }
}

fun OverridingHtmlTag.render(content: String) { +content }

operator fun String.unaryPlus() {
    print("top-level:")
    print(this)
}

fun topLevel(content: String) { +content }

fun main() {
    HtmlTag().render("inherited")
    OverridingHtmlTag().render("overridden")
    topLevel("top")
    println()
}
