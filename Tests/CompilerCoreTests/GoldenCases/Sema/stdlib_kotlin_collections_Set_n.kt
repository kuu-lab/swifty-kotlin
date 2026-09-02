fun inspect(
    values: Set<Int?>,
    iterable: Iterable<Int?>,
    sequence: Sequence<Int?>,
    array: Array<Int?>,
    nullable: Set<Int?>?
): Set<Boolean> {
    val minusElement: Set<Int?> = values - null
    val minusIterable: Set<Int?> = values - iterable
    val minusSequence: Set<Int?> = values - sequence
    val minusArray: Set<Int?> = values - array
    val minusAlias: Set<Int?> = values.minusElement(null)
    val emptyOrNull: Set<Int?> = nullable.orEmpty()
    val plusElement: Set<Int?> = values + null
    val plusIterable: Set<Int?> = values + iterable
    val plusSequence: Set<Int?> = values + sequence
    val plusArray: Set<Int?> = values + array
    val plusAlias: Set<Int?> = values.plusElement(null)
    return setOf(
        minusElement.isEmpty(),
        minusIterable.isEmpty(),
        minusSequence.isEmpty(),
        minusArray.isEmpty(),
        minusAlias.isEmpty(),
        emptyOrNull.isEmpty(),
        plusElement.isEmpty(),
        plusIterable.isEmpty(),
        plusSequence.isEmpty(),
        plusArray.isEmpty(),
        plusAlias.isEmpty()
    )
}
