fun associateFamily(
    values: Sequence<String>,
    nullable: Sequence<String?>,
    destination: MutableMap<Any, Any>,
    intDestination: MutableMap<Int, String>,
    list: List<String>
) {
    val associated: Map<String, Int> = values.associate { it to it.length }
    val byKey: Map<String, String> = values.associateBy { it }
    val byKeyTransformed: Map<String, Int> = values.associateBy(
        { it },
        { it.length }
    )
    val nullableKeys: Map<String, Int> = nullable.associateBy { it ?: "null" }
    val withValues: Map<String, Int> = values.associateWith { it.length }
    val associatedTo: MutableMap<Any, Any> = values.associateTo(destination) {
        it to it.length
    }
    val byTo: MutableMap<Int, String> = values.associateByTo(intDestination) { it.length }
    val byToTransformed: MutableMap<Any, Any> = values.associateByTo(
        destination,
        { it },
        { it.length }
    )
    val withTo: MutableMap<Any, Any> = values.associateWithTo(destination) { it.length }
    val listAssociated: Map<String, Int> = list.asSequence().associateBy { it }
}
