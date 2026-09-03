fun filterFamily(values: Iterable<Any?>, nullable: Iterable<String?>) {
    values.filter { it != null }
    values.filterIndexed { index, _ -> index % 2 == 0 }

    val indexedDestination = mutableListOf<Any?>()
    values.filterIndexedTo(indexedDestination) { index, _ -> index % 2 == 0 }

    values.filterIsInstance<String>()
    val instanceDestination = mutableListOf<String>()
    values.filterIsInstanceTo(instanceDestination)

    values.filterNot { it == null }
    nullable.filterNotNull()

    val notNullDestination = mutableListOf<String>()
    nullable.filterNotNullTo(notNullDestination)

    val notDestination = mutableListOf<Any?>()
    values.filterNotTo(notDestination) { it == null }

    val destination = mutableListOf<Any?>()
    values.filterTo(destination) { it != null }
}
