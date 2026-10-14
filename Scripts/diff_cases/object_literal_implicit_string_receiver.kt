interface Reader { fun read(): Int }
fun String.reader(): Reader = object : Reader {
    override fun read(): Int = get(0).code
}
fun main() { println("A".reader().read()) }
