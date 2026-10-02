fun f4(): Int {
    var i = 0
    try {
        i = 1
        return i
    } finally {
        i = 99
        println("i=$i")
    }
}

fun f7(): String {
    var s = "a"
    try {
        return s
    } finally {
        s = "z"
    }
}

fun f8(): Int {
    var i = 0
    try {
        i = 1
        return i + 1
    } finally {
        i = 99
    }
}

fun main() {
    println(f4())
    println(f7())
    println(f8())
}
