fun main() {
    val string = "x"
    val stringIdentityHash = java.lang.System.identityHashCode(string)
    println(stringIdentityHash == java.lang.System.identityHashCode(string))
    println(System.identityHashCode(string) == stringIdentityHash)
    println(java.lang.System.identityHashCode(null) == 0)

    val value = Any()
    val valueIdentityHash = System.identityHashCode(value)
    println(valueIdentityHash == System.identityHashCode(value))
}
