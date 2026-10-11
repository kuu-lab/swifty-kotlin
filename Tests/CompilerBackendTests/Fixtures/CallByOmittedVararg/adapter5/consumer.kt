fun main() {
    val scalar: (String) -> Array<out String> = ::genericArrayIdentity
    val packedNested: (Array<out Array<String>>) -> Array<out Array<String>> = ::concreteNestedIdentity
    val scalarInt: (Int) -> Array<out Int> = ::genericArrayIdentity
    val scalarNullable: (String?) -> Array<out String?> = ::genericArrayIdentity
    val boxedInt = ::scalarBoxedIntWords
    val nullable = ::scalarNullableWords
    val strings = ::scalarStringWords
    val nested = ::scalarNestedWords
    val direct = concreteNestedIdentity(arrayOf("x"))
    val whole = arrayOf(arrayOf("x"))
    val reflected = packedNested(whole)
    println("generic-scalar-component:" + strings.callBy(mapOf(strings.parameters[0] to scalar("x"))))
    println("concrete-nested-direct-packed:" + nested.callBy(mapOf(nested.parameters[0] to direct)) + "/" + nested.callBy(mapOf(nested.parameters[0] to reflected)) + ":" + (reflected === whole))
    println("generic-int-reference-component:" + boxedInt.callBy(mapOf(boxedInt.parameters[0] to scalarInt(7))))
    println("generic-nullable-reference-component:" + nullable.callBy(mapOf(nullable.parameters[0] to scalarNullable(null))))
    println("inline-vararg-default:" + inlineDefaultWords().joinToString())
}
