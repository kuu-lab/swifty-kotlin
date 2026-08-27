package kotlin.native

import kotlin.internal.KsSymbolName

/**
 * Object describing the current platform program executes upon.
 */
@kotlin.experimental.ExperimentalNativeApi
public object Platform {
    /** Check if the current architecture allows unaligned access wider than a byte. */
    public val canAccessUnaligned: Boolean
        get() = __canAccessUnaligned() != 0

    /** Check whether the current platform uses little-endian byte order. */
    public val isLittleEndian: Boolean
        get() = __isLittleEndian() != 0

    /** Operating system family on which the program executes. */
    public val osFamily: OsFamily
        get() = __osFamily()

    /** CPU architecture on which the program executes. */
    public val cpuArchitecture: CpuArchitecture
        get() = __cpuArchitecture()

    /** Memory model used by the binary. Current runtimes always report EXPERIMENTAL. */
    @Deprecated(
        "This property always returns MemoryModel.EXPERIMENTAL, its usages can be safely removed.",
        ReplaceWith("MemoryModel.EXPERIMENTAL")
    )
    @Suppress("DEPRECATION")
    public val memoryModel: MemoryModel
        get() = MemoryModel.EXPERIMENTAL

    /** Whether the binary was compiled in debug mode. */
    public val isDebugBinary: Boolean
        get() = __isDebugBinary() != 0

    /** Whether legacy freezing is enabled. It is always false in the current memory manager. */
    @Deprecated(
        "Support for the legacy memory manager has been completely removed. Consequently, this property is always `false`.",
        ReplaceWith("false")
    )
    @DeprecatedSinceKotlin(errorSince = "2.1")
    public val isFreezingEnabled: Boolean
        get() = false

    /** Name used to invoke the program executable, or null for a native library. */
    public val programName: String?
        get() = __programName()

    /** Whether the memory leak checker is active. */
    public var isMemoryLeakCheckerActive: Boolean
        get() = __getMemoryLeakChecker() != 0
        set(value) {
            __setMemoryLeakChecker(if (value) 1 else 0)
        }

    @Deprecated("Cleaners leak checking is deprecated and should not be relied upon anymore")
    public var isCleanersLeakCheckerActive: Boolean = false

    /** Return the number of logical processors available to the program. */
    public fun getAvailableProcessors(): Int {
        val fromEnv = __getAvailableProcessorsEnv()
        val value = fromEnv ?: return __getAvailableProcessors()
        val processors = __parseAvailableProcessors(value)
        if (processors == null) {
            throw __invalidAvailableProcessors(
                "Available processors has incorrect environment override: $value"
            )
        }
        val nonNullProcessors = processors!!
        if (nonNullProcessors <= 0) {
            throw __invalidAvailableProcessors(
                "Available processors has incorrect environment override: $value"
            )
        }
        return nonNullProcessors
    }

    @KsSymbolName("kk_platform_canAccessUnaligned")
    private external fun __canAccessUnaligned(): Int

    @KsSymbolName("kk_platform_isLittleEndian")
    private external fun __isLittleEndian(): Int

    @KsSymbolName("kk_platform_osFamily")
    private external fun __osFamily(): OsFamily

    @KsSymbolName("kk_platform_cpuArchitecture")
    private external fun __cpuArchitecture(): CpuArchitecture

    @KsSymbolName("kk_platform_isDebugBinary")
    private external fun __isDebugBinary(): Int

    @KsSymbolName("kk_platform_programName")
    private external fun __programName(): String?

    @KsSymbolName("kk_platform_isMemoryLeakCheckerActive_load")
    private external fun __getMemoryLeakChecker(): Int

    @KsSymbolName("kk_platform_isMemoryLeakCheckerActive_store")
    private external fun __setMemoryLeakChecker(value: Int): Unit

    @KsSymbolName("kk_platform_getAvailableProcessorsEnv")
    private external fun __getAvailableProcessorsEnv(): String?

    @KsSymbolName("kk_platform_getAvailableProcessors")
    private external fun __getAvailableProcessors(): Int

    @KsSymbolName("__kk_string_toIntOrNull")
    private external fun __parseAvailableProcessors(value: String): Int?

    @KsSymbolName("__kk_illegal_state_exception_new_message")
    private external fun __invalidAvailableProcessors(message: String?): IllegalStateException
}
