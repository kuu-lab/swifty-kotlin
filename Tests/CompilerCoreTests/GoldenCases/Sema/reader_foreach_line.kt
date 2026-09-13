package golden.sema

import java.io.File

fun printEachLine(path: String) {
    val file = File(path)
    file.forEachLine { line ->
        println(line)
    }
}
