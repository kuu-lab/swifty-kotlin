package golden.sema

abstract class CustomMap : Map<String?, Int?>

fun mapAsIterable(values: Map<String?, Int?>) = values.asIterable()

fun mapAsSequence(values: Map<String?, Int?>) = values.asSequence()

fun <K, V> genericMapAsIterable(values: Map<out K, V>) = values.asIterable()

fun <K, V> genericMapAsSequence(values: Map<out K, V>) = values.asSequence()

fun customMapAsSequence(values: CustomMap) = values.asSequence()
