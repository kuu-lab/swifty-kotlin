fun aggregate(numbers: Array<Int>) {
    val sum = numbers.reduce { a, b -> a + b }
    val count = numbers.count { it > 0 }
    val none = numbers.none { it < 0 }
}
