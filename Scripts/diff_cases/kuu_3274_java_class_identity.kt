class JavaClassIdentityBox(val value: Int)

fun main() {
    println(JavaClassIdentityBox(5).javaClass == JavaClassIdentityBox(6).javaClass)
    println(JavaClassIdentityBox(5).javaClass === JavaClassIdentityBox(6).javaClass)
    println(5.javaClass == 6.javaClass)
    println(5.javaClass === 6.javaClass)
    println("x".javaClass == "y".javaClass)
    println("x".javaClass === "y".javaClass)
}
