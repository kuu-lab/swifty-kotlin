fun main() {
    val s = "abcde"

    println(s.reduce { acc, c -> if (c > acc) c else acc })
    println(s.reduceOrNull { acc, c -> if (c > acc) c else acc })
    println("".reduceOrNull { acc, c -> if (c > acc) c else acc })

    println(s.reduceIndexed { index, acc, c -> if (index % 2 == 0) acc else "$acc$c"[0] })
    println(s.reduceIndexedOrNull { index, acc, c -> if (index % 2 == 0) acc else "$acc$c"[0] })
    println("".reduceIndexedOrNull { index, acc, c -> if (index % 2 == 0) acc else "$acc$c"[0] })

    println(s.reduceRight { c, acc -> if (c > acc) c else acc })
    println(s.reduceRightOrNull { c, acc -> if (c > acc) c else acc })
    println("".reduceRightOrNull { c, acc -> if (c > acc) c else acc })

    println(s.reduceRightIndexed { index, c, acc -> if (index % 2 == 0) acc else c })
    println(s.reduceRightIndexedOrNull { index, c, acc -> if (index % 2 == 0) acc else c })
    println("".reduceRightIndexedOrNull { index, c, acc -> if (index % 2 == 0) acc else c })

    try {
        "".reduce { acc, c -> acc }
    } catch (e: UnsupportedOperationException) {
        println("reduce empty: ${e.message}")
    }

    try {
        "".reduceIndexed { index, acc, c -> acc }
    } catch (e: UnsupportedOperationException) {
        println("reduceIndexed empty: ${e.message}")
    }

    try {
        "".reduceRight { c, acc -> acc }
    } catch (e: UnsupportedOperationException) {
        println("reduceRight empty: ${e.message}")
    }

    try {
        "".reduceRightIndexed { index, c, acc -> acc }
    } catch (e: UnsupportedOperationException) {
        println("reduceRightIndexed empty: ${e.message}")
    }

    println("x".reduce { acc, c -> acc })
    println("x".reduceRight { c, acc -> acc })
}
