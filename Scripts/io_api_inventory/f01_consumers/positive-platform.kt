// IO-GATE consumer fixture (ledger and generator retired); edit by hand.
@file:OptIn(
    kotlinx.io.DelicateIoApi::class,
    kotlinx.io.InternalIoApi::class,
    kotlinx.io.UnsafeIoApi::class,
    kotlinx.io.bytestring.unsafe.UnsafeByteStringApi::class,
    kotlin.ExperimentalUnsignedTypes::class,
    kotlin.contracts.ExperimentalContracts::class,
)
import kotlinx.io.*
import kotlinx.io.files.*
import kotlinx.io.bytestring.*
import kotlinx.io.unsafe.*
import kotlinx.io.bytestring.unsafe.*
import kotlin.io.encoding.*
import kotlin.time.*
import kotlin.text.*

// Ledger klib-8fe21b6650324264: annotation class UnsafeByteStringApi
@kotlinx.io.bytestring.unsafe.UnsafeByteStringApi
fun f01_klib_8fe21b6650324264() {
}

// Ledger klib-9f0ca3fb595dae3d: annotation class DelicateIoApi
@kotlinx.io.DelicateIoApi
fun f01_klib_9f0ca3fb595dae3d() {
}
