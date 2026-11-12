// DIFF_JVM: Char.titlecase() returns a full Unicode titlecase String.
fun main() {
    println('a'.titlecase())
    println('ǆ'.titlecase())
    println('ß'.titlecase())
    println('ŉ'.titlecase())
    println('ﬃ'.titlecase())
    println('\u1F88'.titlecase())
    println('\uD800'.titlecase() == "\uD800")
    println('\u0000'.titlecase() == "\u0000")
}
