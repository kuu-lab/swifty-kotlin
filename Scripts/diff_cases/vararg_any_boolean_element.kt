// SKIP-DIFF (DEBT-DIFF-008): a Boolean element boxed into a `vararg items: Any` array prints as
// its raw underlying int representation ("1"/"0") instead of going through Boolean.toString()
// ("true"/"false") once retrieved through the vararg array and iterated.
fun printAll(vararg items: Any) {
    items.forEach { println(it) }
}

fun main() {
    printAll("Hello", 42, true)
}
