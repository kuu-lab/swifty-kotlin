package golden.sema

import java.io.File

fun readWithBufferedReader(path: String): String {
    val file = File(path)
    return file.bufferedReader().use { reader ->
        reader.readText()
    }
}

fun readLinesWithBufferedReader(path: String): List<String> {
    val file = File(path)
    return file.bufferedReader().use { reader ->
        reader.readLines()
    }
}

fun readLineByLine(path: String) {
    val file = File(path)
    val reader = file.bufferedReader()
    val line: String? = reader.readLine()
    println(line)
    reader.close()
}
