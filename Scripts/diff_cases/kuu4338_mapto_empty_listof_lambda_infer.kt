// KUU-4338: an empty generic call (`mutableListOf()`) passed as an argument
// must take its type arguments from sibling constraints — here the lambda
// return type — instead of failing with KSWIFTK-SEMA-INFER. Mirrors the
// okio ForwardingFileSystem `result.mapTo(mutableListOf()) { ... }` idiom.
open class ForwardingFileSystemLike {
    open fun onPathResult(path: String, functionName: String): String = path

    fun list(result: List<String>): List<String> {
        val paths = result.mapTo(mutableListOf()) { onPathResult(it, "list") }
        paths.sort()
        return paths
    }

    fun listOrNull(result: List<String>?): List<String>? {
        val r = result ?: return null
        val paths = r.mapTo(mutableListOf()) { onPathResult(it, "listOrNull") }
        paths.sort()
        return paths
    }
}

fun lengths(result: List<String>): List<Int> {
    return result.mapTo(mutableListOf()) { it.length }
}

fun main() {
    val fs = ForwardingFileSystemLike()
    println(fs.list(listOf("b", "a", "c")))
    println(fs.listOrNull(null))
    println(fs.listOrNull(listOf("y", "x")))
    println(lengths(listOf("ab", "c")))
}
