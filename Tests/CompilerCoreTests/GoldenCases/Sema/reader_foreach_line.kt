package golden.sema

import java.io.File

fun printEachLine(path: String) {
    val file = File(path)
    file.forEachLine { line ->
        println(line)
    }
}

fun collectLinesFromReader(path: String): List<String> {
    val result = mutableListOf<String>()
    val file = File(path)
    val reader = file.bufferedReader()
    reader.forEachLine { line ->
        result.add(line)
    }
    return result
}
