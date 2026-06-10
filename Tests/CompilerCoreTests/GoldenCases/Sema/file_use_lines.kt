package golden.sema

import java.io.File

fun collectLines(path: String): List<String> {
    val file = File(path)
    return file.useLines { lines ->
        lines.toList()
    }
}

fun countLines(path: String): Int {
    val file = File(path)
    return file.useLines { lines ->
        lines.count()
    }
}
