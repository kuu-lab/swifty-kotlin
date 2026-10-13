fun main() {
    println("nonvararg-class:" + componentClass<String>("x"))
    println("nonvararg-default:" + componentDefault<String>())
    val strings = ::componentStrings
    println("reified-empty:" + strings.callBy(mapOf(strings.parameters[0] to componentEmpty<String>())))
    println("reified-captured-empty:" + strings.callBy(mapOf(strings.parameters[0] to componentViaLambda<String>())))
    val nested = ::componentNested
    println("reified-nested-empty:" + nested.callBy(mapOf(nested.parameters[0] to componentEmpty<Array<String>>())))
    println("reified-wrong-component:" + componentRejected { nested.callBy(mapOf(nested.parameters[0] to componentEmpty<Array<Int>>())) })
}
