class Host {
    companion object {
        public @JvmStatic
        fun create(): Int = 7
    }
}

fun main() {
    println(Host.create())
}
