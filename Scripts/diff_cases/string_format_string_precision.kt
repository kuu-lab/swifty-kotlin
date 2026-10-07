fun main() {
    fun codes(value: String) = value.map { it.code }.joinToString(",")

    // U+10000 is two UTF-16 units; precision 3 cuts after the high surrogate.
    val supplementary = "ab\uD800\uDC00cd"
    println(codes("%.3s".format(supplementary)))
    println(codes("%.2s".format(supplementary)))
    println(codes("%.4s".format(supplementary)))

    // NFD "é" is e + combining acute (two UTF-16 units).
    val combining = "e\u0301abc"
    println(codes("%.3s".format(combining)))
    println(codes("%.1s".format(combining)))

    println("%.3s".format("hello"))
    println("%.0s".format("hello").length)
    println("%.10s".format("hi"))
    println("%.2S".format("abcd"))
}
