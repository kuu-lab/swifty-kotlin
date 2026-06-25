package golden.diagnostics

@RequiresOptIn(level = RequiresOptIn.Level.WARNING)
annotation class ExperimentalUnsignedTypesMarker

@RequiresOptIn(level = RequiresOptIn.Level.WARNING)
annotation class ExperimentalUuidApiMarker

@RequiresOptIn(level = RequiresOptIn.Level.WARNING)
annotation class ExperimentalEncodingApiMarker

@RequiresOptIn(level = RequiresOptIn.Level.WARNING)
annotation class ExperimentalMultiplatformMarker

@RequiresOptIn(level = RequiresOptIn.Level.WARNING)
annotation class ExperimentalSubclassOptInMarker

@ExperimentalUnsignedTypesMarker
fun inventoryUnsigned(): UInt = 0u

@ExperimentalUuidApiMarker
fun inventoryUuid(): String = "uuid"

@ExperimentalEncodingApiMarker
fun inventoryEncoding(): ByteArray = ByteArray(0)

@ExperimentalMultiplatformMarker
fun inventoryMultiplatform(): Int = 0

@ExperimentalSubclassOptInMarker
fun inventorySubclassOptIn(): Int = 0

// All five calls without opt-in — five warning diagnostics expected
fun useAllMarkers() {
    inventoryUnsigned()
    inventoryUuid()
    inventoryEncoding()
    inventoryMultiplatform()
    inventorySubclassOptIn()
}
