val syncProp: String by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
    println("computing sync")
    "synchronized"
}

val pubProp: String by lazy(LazyThreadSafetyMode.PUBLICATION) {
    println("computing pub")
    "publication"
}

val noneProp: String by lazy(LazyThreadSafetyMode.NONE) {
    println("computing none")
    "none"
}

fun main() {
    println(syncProp)
    println(syncProp)
    println(pubProp)
    println(pubProp)
    println(noneProp)
    println(noneProp)
}
