import kotlin.reflect.KClassifier
import kotlin.reflect.KType
import kotlin.reflect.KTypeParameter
import kotlin.reflect.KVariance

// KSP-1333: a user-implemented KTypeParameter exercises the source-backed
// interface surface end to end — each abstract property must dispatch through
// the itable to the concrete override.
class FakeTypeParameter(
    override val name: String,
    override val isReified: Boolean,
) : KTypeParameter {
    override val variance: KVariance get() = KVariance.INVARIANT
    override val upperBounds: List<KType> get() = emptyList()
}

fun describe(parameter: KTypeParameter): String =
    parameter.name + "|" + parameter.isReified.toString() + "|" +
        parameter.variance.toString() + "|" + parameter.upperBounds.size.toString()

fun main() {
    val parameter: KTypeParameter = FakeTypeParameter("T", true)
    println(describe(parameter))
    val classifier: KClassifier = parameter
    println(classifier is KTypeParameter)
}
