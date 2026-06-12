import kotlinx.cinterop.ByteVar
import kotlinx.cinterop.CPointer
import kotlinx.cinterop.CValues
import kotlinx.cinterop.CPointerVarOf
import kotlinx.cinterop.toCValues

fun listToValues(ptrs: List<CPointer<ByteVar>?>): CValues<CPointerVarOf<ByteVar>> {
    return ptrs.toCValues()
}
