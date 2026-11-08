// KUU-4413: a data class's synthetic `copy` member must appear in
// KClass.members alongside componentN — the JVM lists it, and reflection
// driven code (callBy-style generic copying) looks it up by name.

data class K4413Point(val name: String, var age: Int)
data class K4413Single(val e: Int)
class K4413Regular(val x: Int) {
    fun f(): Int = x
}

fun main() {
    println(K4413Point::class.members.map { it.name }.sorted())
    println(K4413Single::class.members.map { it.name }.sorted())
    println(K4413Regular::class.members.map { it.name }.sorted())
    println(K4413Point::class.members.first { it.name == "copy" }.returnType)
}
