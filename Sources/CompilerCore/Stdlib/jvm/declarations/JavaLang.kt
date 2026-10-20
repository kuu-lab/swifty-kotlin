package java.lang

typealias IllegalArgumentException = kotlin.IllegalArgumentException

class Math private constructor() {
    companion object {
        const val PI: Double = 3.141592653589793
        const val E: Double = 2.718281828459045
    }
}

class System private constructor() {
    companion object {
        fun arraycopy(src: Any?, srcPos: Int, dest: Any?, destPos: Int, length: Int): Unit {}
    }
}
