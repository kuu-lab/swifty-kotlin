package kotlin.text

// MIGRATION-ENC-002
// HexFormat extension functions: toHexString (Int, Long, ByteArray) and hexToByteArray,
// plus the full hexTo* family.
// Migration source: Sources/Runtime/RuntimeHexFormat.swift
//   (kk_int_toHexString, kk_long_toHexString, kk_bytearray_toHexString,
//    kk_string_hexToByteArray, kk_string_hexToInt, kk_string_hexToLong,
//    kk_string_hexToShort, kk_string_hexToUByte, kk_string_hexToUShort,
//    kk_string_hexToUInt, kk_string_hexToULong, kk_string_hexToUByteArray)
//
// NOTE: Not yet wired into the compiler pipeline as primary dispatch path.
// Sema stubs in HeaderHelpers+SyntheticHexFormatStubs.swift still dispatch
// directly to the kk_* ABI functions.  This file is the migration target;
// wiring (and removal of those stubs) happens in the follow-up RF-STDLIB task.
//
// The HexFormat class itself (companion object Default, upperCase property,
// bytes property, and the HexFormat { } builder DSL) remain as Sema stubs
// backed by Swift RuntimeHexFormatBox allocation, because the builder lambda
// ABI (fnPtr / closureRaw) cannot yet be expressed as a typed external fun.
//
// Implementation strategy:
//   toHexString (Int, Long, ByteArray)  — ABI bridge to kk_*_toHexString
//   hexToByteArray                      — ABI bridge to kk_string_hexToByteArray
//   hexToInt/Short/Long and unsigned variants
//                                       — ABI bridges to kk_string_hex* (throwing
//                                         variants; outThrown handling is performed
//                                         by the Swift bridge itself)

// ─── ABI bridges ─────────────────────────────────────────────────────────────

@Suppress("UNCHECKED_CAST")
private external fun kk_int_toHexString(receiver: Int, format: HexFormat): String

@Suppress("UNCHECKED_CAST")
private external fun kk_long_toHexString(receiver: Long, format: HexFormat): String

@Suppress("UNCHECKED_CAST")
private external fun kk_bytearray_toHexString(array: ByteArray, format: HexFormat): String

@Suppress("UNCHECKED_CAST")
private external fun kk_string_hexToByteArray(receiver: String, format: HexFormat): ByteArray

@Suppress("UNCHECKED_CAST")
private external fun kk_string_hexToInt(receiver: String, format: HexFormat): Int

@Suppress("UNCHECKED_CAST")
private external fun kk_string_hexToShort(receiver: String, format: HexFormat): Short

@Suppress("UNCHECKED_CAST")
private external fun kk_string_hexToLong(receiver: String, format: HexFormat): Long

@Suppress("UNCHECKED_CAST")
private external fun kk_string_hexToUByte(receiver: String, format: HexFormat): UByte

@Suppress("UNCHECKED_CAST")
private external fun kk_string_hexToUShort(receiver: String, format: HexFormat): UShort

@Suppress("UNCHECKED_CAST")
private external fun kk_string_hexToUInt(receiver: String, format: HexFormat): UInt

@Suppress("UNCHECKED_CAST")
private external fun kk_string_hexToULong(receiver: String, format: HexFormat): ULong

// ─── toHexString ─────────────────────────────────────────────────────────────

@ExperimentalStdlibApi
public fun Int.toHexString(format: HexFormat = HexFormat.Default): String =
    kk_int_toHexString(this, format)

@ExperimentalStdlibApi
public fun Long.toHexString(format: HexFormat = HexFormat.Default): String =
    kk_long_toHexString(this, format)

@ExperimentalStdlibApi
public fun ByteArray.toHexString(format: HexFormat = HexFormat.Default): String =
    kk_bytearray_toHexString(this, format)

// ─── hexToByteArray ──────────────────────────────────────────────────────────

@ExperimentalStdlibApi
public fun String.hexToByteArray(format: HexFormat = HexFormat.Default): ByteArray =
    kk_string_hexToByteArray(this, format)

// ─── hexTo* (signed) ─────────────────────────────────────────────────────────

@ExperimentalStdlibApi
public fun String.hexToInt(format: HexFormat = HexFormat.Default): Int =
    kk_string_hexToInt(this, format)

@ExperimentalStdlibApi
public fun String.hexToShort(format: HexFormat = HexFormat.Default): Short =
    kk_string_hexToShort(this, format)

@ExperimentalStdlibApi
public fun String.hexToLong(format: HexFormat = HexFormat.Default): Long =
    kk_string_hexToLong(this, format)

// ─── hexTo* (unsigned) ───────────────────────────────────────────────────────

@ExperimentalStdlibApi
public fun String.hexToUByte(format: HexFormat = HexFormat.Default): UByte =
    kk_string_hexToUByte(this, format)

@ExperimentalStdlibApi
public fun String.hexToUShort(format: HexFormat = HexFormat.Default): UShort =
    kk_string_hexToUShort(this, format)

@ExperimentalStdlibApi
public fun String.hexToUInt(format: HexFormat = HexFormat.Default): UInt =
    kk_string_hexToUInt(this, format)

@ExperimentalStdlibApi
public fun String.hexToULong(format: HexFormat = HexFormat.Default): ULong =
    kk_string_hexToULong(this, format)
