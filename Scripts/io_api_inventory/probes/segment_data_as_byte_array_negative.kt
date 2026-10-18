import kotlinx.io.Segment

fun callInternalDataAsByteArrayFromConsumer(target: Segment, readOnly: Boolean): ByteArray =
    target.dataAsByteArray(readOnly)
