// KUU-1971: same-named local classes must keep their own members.
fun main() {
    run {
        class S { val a = 1 }
        val s = S(); println("a=${s.a}")
    }
    run {
        class S { var got = 0 }
        val s = S()
        s.got = 5
        println("got=${s.got}")
    }

    run {
        class S { fun first() = "first"; fun shared() = 10 }
        val s: S = S()
        println(s.first())
        println(s.shared())
    }
    run {
        class S { fun second() = "second"; fun shared() = 20 }
        val s: S = S()
        println(s.second())
        println(s.shared())
    }

    class S { val outer = 70 }
    run {
        class S { val inner = 80 }
        val s: S = S()
        println(s.inner)
    }
    val s: S = S()
    println(s.outer)
}
