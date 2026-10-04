fun main() {
    val s = "こんにちは世界こんにちは"
    println(s.contains("世界"))
    println(s.contains("せかい"))
    println(s.indexOf("世界"))
    println(s.indexOf("こんにちは"))
    println(s.indexOf("こんにちは", 1))
    println(s.lastIndexOf("こんにちは"))
    println(s.lastIndexOf('ち'))
    println(s.indexOfAny(charArrayOf('世', '界')))
    println(s.lastIndexOfAny(charArrayOf('世', '界')))
    println(s.indexOfAny(listOf("世界", "こんにちは")))
    println(s.findAnyOf(listOf("世界", "こんにちは")))
    println(s.findLastAnyOf(listOf("世界", "こんにちは")))
    println(s.indexOfFirst { it == '世' })
    println(s.indexOfLast { it == 'こ' })

    val accented = "café résumé café"
    println(accented.contains("résumé"))
    println(accented.indexOf("café", 1))
    println(accented.lastIndexOf("café"))
    println(accented.indexOf('é'))
    println(accented.lastIndexOf('é'))
}
