// KSP-941: source-backed Map shell with residual query members.
abstract class CustomMap : Map<String, Int>

fun mapProbe(values: Map<String, Int>): Map<String, Number> = values

fun mapTypeProbe(value: Any): Boolean = value is Map<*, *>
