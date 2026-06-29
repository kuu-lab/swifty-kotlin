import kotlin.io.path.Path
import kotlin.io.path.useLines

fun collectLines(path: Path): List<String> {
    return path.useLines { lines ->
        lines.toList()
    }
}

fun countLines(path: Path): Int {
    return path.useLines { lines ->
        lines.count()
    }
}
