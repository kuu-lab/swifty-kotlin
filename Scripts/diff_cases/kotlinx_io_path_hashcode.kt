import kotlinx.io.files.Path

fun main() {
    val original = Path("folder", "leaf")
    val equalPath = Path("folder/leaf")
    val differentPath = Path("folder", "other")

    check(original.toString() == "folder/leaf")
    check(original.hashCode() == original.toString().hashCode())
    check(original == equalPath)
    check(original.hashCode() == equalPath.hashCode())

    val paths = HashSet<Path>()
    check(paths.add(original))
    check(!paths.add(equalPath))
    check(equalPath in paths)
    check(differentPath !in paths)

    val values = HashMap<Path, String>()
    values[original] = "found"
    check(values[equalPath] == "found")
    check(values[differentPath] == null)

    println("path-hashcode:OK")
}
