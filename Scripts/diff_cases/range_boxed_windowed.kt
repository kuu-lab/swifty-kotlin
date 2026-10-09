fun main() {
    println(('a'..'e').windowed(2))
    println(('a'..'e' step 2).windowed(2))
    println((1L..5L).windowed(2))
    println((5L downTo 1L).windowed(2))
}
