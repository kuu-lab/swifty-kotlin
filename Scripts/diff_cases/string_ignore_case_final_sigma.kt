fun main() {
    println("ς".startsWith("σ", ignoreCase = true))
    println("ς".endsWith("σ", ignoreCase = true))
    println("aςb".indexOf("σ", ignoreCase = true))
    println("aςb".lastIndexOf("σ", ignoreCase = true))
    println("ς".contentEquals("σ", ignoreCase = true))
    println("ς".equals("σ", ignoreCase = true))
    println("ς".compareTo("σ", ignoreCase = true))
}
