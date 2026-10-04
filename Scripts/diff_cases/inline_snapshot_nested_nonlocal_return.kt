inline fun around(block: () -> Unit) {
    block()
}

fun mandatory(block: () -> Unit) {
    block()
}

fun find(): Int {
    around {
        around {
            mandatory {}
            return 42
        }
    }
    return -1
}

fun returnFromCaller() {
    around {
        around {
            mandatory {}
            println("inside")
            return
        }
    }
    println("after")
}

fun main() {
    println(find())
    returnFromCaller()
}
