import kotlin.io.path.Path
import kotlin.io.path.useLines

fun collectLines(path: String): List<String> {
    val p = Path(path)
    return p.useLines { lines ->
        lines.toList()
    }
}

fun countLines(path: String): Int {
    val p = Path(path)
    return p.useLines { lines ->
        lines.count()
    }
}
