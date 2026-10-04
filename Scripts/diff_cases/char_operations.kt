
fun main() {
    println("=== Char Operations Test ===")
    
    // Basic char operations
    val charA = 'A'
    val charZ = 'Z'
    val char0 = '0'
    val char9 = '9'
    
    // Char plus string
    println("Char + string:")
    println(charA + "pple")
    println(char0 + "123")
    
    // Char rangeTo
    println("\nChar ranges:")
    println((charA..'D').toList())  // Should produce [A, B, C, D]
    println((char0..'3').toList())  // Should produce [0, 1, 2, 3]

    // Unicode char operations
    val unicodeChar = 'α'
    println("\nUnicode char:")
    println(unicodeChar + " greek")
    println((unicodeChar..'δ').toList())

    // Edge cases
    println("\nEdge cases:")
    val replacementChar = '\uFFFD'
    println(replacementChar + " invalid")

    // Empty range (when start > end)
    println("\nEmpty range:")
    println(('Z'..'A').toList())  // Should produce empty list
    
    // New numeric conversion functions
    println("\n=== Numeric Conversion Tests ===")
    println("charA.toInt(): ${charA.toInt()}")  // Should return 65 (Unicode code point)
    println("charA.toDouble(): ${charA.toDouble()}")  // Should return 65.0
    println("char0.digitToIntOrNull(): ${char0.digitToIntOrNull()}")  // Should return 0
    println("char9.digitToIntOrNull(): ${char9.digitToIntOrNull()}")  // Should return 9
    println("charA.digitToIntOrNull(): ${charA.digitToIntOrNull()}")  // Should return null

    // Code point and Unicode properties
    println("\n=== Unicode Properties Tests ===")
    println("charA.code: ${charA.code}")  // Should return 65
    println("char0.code: ${char0.code}")  // Should return 48
    println("unicodeChar.code: ${unicodeChar.code}")  // Should return 945
}
