fun main() {
    val source = "HelloWorld"
    val other = "helloKotlin"

    println(source.commonPrefixWith(other))
    println(source.commonPrefixWith(other, true))
    println(source.commonPrefixWith(other, false))
    println("".commonPrefixWith("abc"))
    println("abc".commonPrefixWith(""))
    println("kotlin-native".commonPrefixWith("kotlin-js"))
    println("same".commonPrefixWith("same"))

    println(source.commonSuffixWith("MyWorld"))
    println("HelloWORLD".commonSuffixWith("MyWorld", true))
    println("HelloWORLD".commonSuffixWith("MyWorld", false))
    println("".commonSuffixWith("abc"))
    println("abc".commonSuffixWith(""))
    println("prefix-core".commonSuffixWith("suffix-core"))
    println("same".commonSuffixWith("same"))
}
