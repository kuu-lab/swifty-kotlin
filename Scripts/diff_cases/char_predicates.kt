fun main() {
    println('A'.isLetter())
    println('1'.isDigit())
    println(' '.isWhitespace())
    println('7'.isLetterOrDigit())
    // KSP-661: Char 判定系（Kotlin 化）
    println('A'.isUpperCase())           // true
    println('a'.isUpperCase())           // false
    println('a'.isLowerCase())           // true
    println('A'.isLowerCase())           // false
    println('\u2160'.isUpperCase())      // true (Other_Uppercase: Roman numeral I)
    println('\u2170'.isLowerCase())      // true (Other_Lowercase: small roman numeral i)
    println('A'.isDefined())             // true
    println('\u0378'.isDefined())        // false (unassigned)
    println('\uD800'.isDefined())        // true (surrogate is defined)
    println('\uD800'.isHighSurrogate())  // true
    println('\uDC00'.isLowSurrogate())   // true
    println('\uD800'.isSurrogate())      // true
    println('A'.isSurrogate())           // false
    println('\u0001'.isISOControl())     // true
    println('A'.isISOControl())          // false
    println('\u01C5'.isTitleCase())      // true
    println('A'.isTitleCase())           // false
}
