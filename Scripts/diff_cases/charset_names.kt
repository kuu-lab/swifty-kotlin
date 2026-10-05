import kotlin.text.Charsets

fun main() {
    println(Charsets.UTF_8)
    println(Charsets.ISO_8859_1)
    println(Charsets.US_ASCII)
    println(Charsets.UTF_16)
    println(Charsets.UTF_16BE)
    println(Charsets.UTF_16LE)
    println(Charsets.UTF_32)
    println(Charsets.UTF_32BE)
    println(Charsets.UTF_32LE)

    println(Charsets.UTF_8.name())
    println(Charsets.ISO_8859_1.name())
    println(Charsets.US_ASCII.name())
    println(Charsets.UTF_16.name())
    println(Charsets.UTF_16BE.name())
    println(Charsets.UTF_16LE.name())
    println(Charsets.UTF_32.name())
    println(Charsets.UTF_32BE.name())
    println(Charsets.UTF_32LE.name())

    println(Charsets.UTF_8.toString())
    println(Charsets.ISO_8859_1.toString())
    println(Charsets.US_ASCII.toString())
    println(Charsets.UTF_16.toString())
    println(Charsets.UTF_16BE.toString())
    println(Charsets.UTF_16LE.toString())
    println(Charsets.UTF_32.toString())
    println(Charsets.UTF_32BE.toString())
    println(Charsets.UTF_32LE.toString())

    val charset = Charsets.UTF_8
    print(charset)
    println()
    println("$charset / ${Charsets.UTF_16} / ${Charsets.ISO_8859_1}")
    println("charset=" + charset)
    var text = "charset="
    text += charset
    println(text)

    val present = if (charset.name() == "UTF-8") charset else null
    val absent = if (charset.name() == "UTF-8") null else charset
    println(present)
    println(present?.name())
    println(present?.toString())
    println("$present")
    println(absent)
    println(absent?.name())
    println(absent?.toString())
    println("$absent")

    println(charset == Charsets.UTF_8)
    println(charset != Charsets.UTF_16)
    println("é".toByteArray(charset).contentToString())
    println("é".toByteArray(Charsets.ISO_8859_1).contentToString())
}
