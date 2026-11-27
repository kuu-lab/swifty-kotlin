package kotlin.text
fun CharSequence.indexOf(string: String, startIndex: Int = 0, ignoreCase: Boolean = false): Int = 0
fun CharSequence.indexOf(char: Char, startIndex: Int = 0, ignoreCase: Boolean = false): Int = 0
fun CharSequence.indexOfAny(chars: CharArray, startIndex: Int = 0, ignoreCase: Boolean = false): Int = 0
fun CharSequence.indexOfAny(strings: Collection<String>, startIndex: Int = 0, ignoreCase: Boolean = false): Int = 0
fun CharSequence.lastIndexOf(string: String, startIndex: Int = 0, ignoreCase: Boolean = false): Int = 0
fun CharSequence.lastIndexOf(char: Char, startIndex: Int = 0, ignoreCase: Boolean = false): Int = 0
fun CharSequence.lastIndexOfAny(chars: CharArray, startIndex: Int = length - 1, ignoreCase: Boolean = false): Int = 0
fun CharSequence.lastIndexOfAny(strings: Collection<String>, startIndex: Int = length - 1, ignoreCase: Boolean = false): Int = 0
fun CharSequence.findAnyOf(strings: Collection<String>, startIndex: Int = 0, ignoreCase: Boolean = false): Pair<Int, String>? = null
fun CharSequence.findLastAnyOf(strings: Collection<String>, startIndex: Int = length - 1, ignoreCase: Boolean = false): Pair<Int, String>? = null
