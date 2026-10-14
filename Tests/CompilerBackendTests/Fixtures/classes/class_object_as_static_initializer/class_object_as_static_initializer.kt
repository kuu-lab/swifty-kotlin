var global = "A"

class C {
    init {
        global += "D"
    }

    companion object {
        init {
            global += "B"
        }

        init {
            global += "C"
        }
    }
}

fun main() {
    if (global != "A") {
        println("fail1: global = $global")
        return
    }

    C()
    if (global == "ABCD") println("OK") else println("fail2: global = $global")
}
