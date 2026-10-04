fun probe(input: String): String? {
    val match = Regex("(a)(b)?(c)(d)(e)(f)(g)(h)(i)(j)").find(input) ?: return null
    val destructured = match.destructured
    val captures = destructured.toList()
    return destructured.component10() + captures.size
}
