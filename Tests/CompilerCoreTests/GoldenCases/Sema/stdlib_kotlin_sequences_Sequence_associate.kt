import kotlin.sequences.associate as seqAssociate
import kotlin.sequences.associateBy as seqAssociateBy
import kotlin.sequences.associateByTo as seqAssociateByTo
import kotlin.sequences.associateTo as seqAssociateTo
import kotlin.sequences.associateWith as seqAssociateWith
import kotlin.sequences.associateWithTo as seqAssociateWithTo

fun associateFamily(
    values: Sequence<String>,
    nullable: Sequence<String?>,
    destination: MutableMap<Any, Any>,
    intDestination: MutableMap<Int, String>,
    list: List<String>
) {
    val associated: Map<String, Int> = values.seqAssociate { it to it.length }
    val byKey: Map<String, String> = values.seqAssociateBy { it }
    val byKeyTransformed: Map<String, Int> = values.seqAssociateBy(
        { it },
        { it.length }
    )
    val nullableKeys: Map<String, String?> = nullable.seqAssociateBy { it ?: "null" }
    val withValues: Map<String, Int> = values.seqAssociateWith(valueSelector = { it.length })
    val associatedTo: MutableMap<Any, Any> = values.seqAssociateTo(destination) {
        it to it.length
    }
    val byTo: MutableMap<Int, String> = values.seqAssociateByTo(intDestination) { it.length }
    val byToTransformed: MutableMap<Any, Any> = values.seqAssociateByTo(
        destination,
        { it },
        { it.length }
    )
    val withTo: MutableMap<Any, Any> = values.seqAssociateWithTo(destination, valueSelector = { it.length })
    val listAssociated: Map<String, String> = list.asSequence().associateBy { it }
}
