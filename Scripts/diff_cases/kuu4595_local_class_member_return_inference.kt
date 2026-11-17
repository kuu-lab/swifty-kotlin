// KUU-4595: inside a local class (or object literal), an initializer that
// calls an expression-bodied member function used to see the header's `Any`
// return placeholder instead of the inferred return type.
fun main() {
    class Annotated {
        val x: String = computed()
        private fun computed() = "c-x"
    }

    class LazyBox {
        val x: String by lazy { computed() }
        fun computed() = "c-lazy"
    }

    class Inferred {
        val x = computed()
        fun computed() = "c-inf"
    }

    class Indirect {
        val y: String = via()
        fun via() = seed
        val seed = "c-seed"
    }

    val obj = object {
        val x: String = computed()
        fun computed() = "o-x"
    }

    println(Annotated().x)
    println(LazyBox().x)
    println(Inferred().x.length)
    println(Indirect().y)
    println(obj.x)
}
