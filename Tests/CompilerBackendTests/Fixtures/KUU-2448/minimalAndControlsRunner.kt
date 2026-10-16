class Normal {
    infix fun combine(s: String): String = "O" + s
}

class Dot {
    infix fun infix(s: String): String = "O" + s
}

fun main() {
    if (box() != "OK") {
        println("FAIL minimal infix call")
        return
    }
    if (Normal() combine "K" != "OK") {
        println("FAIL ordinary infix call")
        return
    }
    if (Dot().infix("K") != "OK") {
        println("FAIL soft-keyword dot call")
        return
    }
    println("OK")
}
