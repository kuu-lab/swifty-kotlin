package kswiftk.internal

// MARK: - System calls

@KSwiftKRuntimeName("kk_sys_write")
external fun __sys_write(fd: Int, buffer: ByteArray, count: Int): Int

@KSwiftKRuntimeName("kk_readln_from_syscall")
external fun __readln_from_syscall(outThrown: Int): String?

@KSwiftKRuntimeName("kk_system_exitProcess")
external fun __exitProcess(status: Int): Nothing

// MARK: - Time functions (system-level APIs)

@KSwiftKRuntimeName("kk_system_getTimeMicros")
external fun __getTimeMicros(): Long

@KSwiftKRuntimeName("kk_system_getTimeMillis")
external fun __getTimeMillis(): Long

@KSwiftKRuntimeName("kk_system_getTimeNanos")
external fun __getTimeNanos(): Long

// MARK: - Synchronization (necessary for thread safety)

@KSwiftKRuntimeName("kk_synchronized")
external fun __synchronized(lock: Any, block: () -> Any?): Any

// MARK: - Floating point bit operations (low-level bit manipulation)

@KSwiftKRuntimeName("kk_double_toBits")
external fun __doubleToBits(value: Double): Long

@KSwiftKRuntimeName("kk_double_toRawBits")
external fun __doubleToRawBits(value: Double): Long

@KSwiftKRuntimeName("kk_float_toBits")
external fun __floatToBits(value: Float): Int

@KSwiftKRuntimeName("kk_float_toRawBits")
external fun __floatToRawBits(value: Float): Int

@KSwiftKRuntimeName("kk_double_fromBits")
external fun __doubleFromBits(bits: Long): Double

@KSwiftKRuntimeName("kk_float_fromBits")
external fun __floatFromBits(bits: Int): Float
