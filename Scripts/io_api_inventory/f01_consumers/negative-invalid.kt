// IO-GATE consumer fixture (ledger and generator retired); edit by hand.
// Each call is listed in negative-api-guards.tsv as absent from pinned kotlinx-io 0.9.1.
import kotlinx.io.*
import kotlinx.io.bytestring.*

fun f01_invalid(buffer: Buffer, bytes: ByteString) {
    // Guard invalid-01: Okio ByteString.hex is absent from pinned kotlinx-io 0.9.1.
    bytes.hex()
    // Guard invalid-02: Okio ByteString.utf8 is absent from pinned kotlinx-io 0.9.1.
    bytes.utf8()
    // Guard invalid-03: Okio ByteArray.encodeToByteString is absent from pinned kotlinx-io 0.9.1.
    byteArrayOf(1).encodeToByteString()
    // Guard invalid-04: Okio Buffer.snapshot(byteCount) is absent; kotlinx-io exposes only the zero-argument snapshot.
    buffer.snapshot(2)
    // Guard invalid-05: Okio select is absent from pinned kotlinx-io 0.9.1.
    select { }
}
