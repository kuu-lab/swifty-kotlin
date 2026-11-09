@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)

package platform.posix

import kotlin.internal.KsSymbolName
import kotlinx.cinterop.ByteVar
import kotlinx.cinterop.CFunction
import kotlinx.cinterop.COpaquePointer
import kotlinx.cinterop.COpaquePointerVar
import kotlinx.cinterop.CPointer
import kotlinx.cinterop.CStructVar
import kotlinx.cinterop.IntVar
import kotlinx.cinterop.LongVar
import kotlinx.cinterop.UIntVar
import kotlinx.cinterop.plus
import kotlinx.cinterop.reinterpret
import kotlinx.cinterop.value

public typealias pthread_mutex_t = CStructVar
public typealias pthread_mutexattr_t = CStructVar
public typealias pthread_cond_t = CStructVar
public typealias pthread_condattr_t = CStructVar
public typealias pthread_attr_t = CStructVar
public typealias timespec = CStructVar
public typealias pthread_t = COpaquePointer
public typealias pthread_tVar = COpaquePointerVar
public typealias pthread_override_t = COpaquePointer
public typealias qos_class_t = UInt

public const val CLOCK_REALTIME: Int = 0
public const val CLOCK_MONOTONIC: Int = 6
public const val PTHREAD_MUTEX_ERRORCHECK: Int = 1

@KsSymbolName("pthread_mutex_init")
public external fun pthread_mutex_init(
    mutex: CPointer<pthread_mutex_t>,
    attr: CPointer<pthread_mutexattr_t>?
): Int

@KsSymbolName("pthread_mutex_lock")
public external fun pthread_mutex_lock(mutex: CPointer<pthread_mutex_t>): Int

@KsSymbolName("pthread_mutex_unlock")
public external fun pthread_mutex_unlock(mutex: CPointer<pthread_mutex_t>): Int

@KsSymbolName("pthread_mutex_destroy")
public external fun pthread_mutex_destroy(mutex: CPointer<pthread_mutex_t>): Int

@KsSymbolName("pthread_mutexattr_init")
public external fun pthread_mutexattr_init(attr: CPointer<pthread_mutexattr_t>): Int

@KsSymbolName("pthread_mutexattr_settype")
public external fun pthread_mutexattr_settype(
    attr: CPointer<pthread_mutexattr_t>,
    type: Int
): Int

@KsSymbolName("pthread_mutexattr_destroy")
public external fun pthread_mutexattr_destroy(attr: CPointer<pthread_mutexattr_t>): Int

@KsSymbolName("pthread_cond_init")
public external fun pthread_cond_init(
    condition: CPointer<pthread_cond_t>,
    attr: CPointer<pthread_condattr_t>?
): Int

@KsSymbolName("pthread_condattr_init")
public external fun pthread_condattr_init(attr: CPointer<pthread_condattr_t>): Int

@KsSymbolName("pthread_condattr_destroy")
public external fun pthread_condattr_destroy(attr: CPointer<pthread_condattr_t>): Int

@KsSymbolName("pthread_cond_wait")
public external fun pthread_cond_wait(
    condition: CPointer<pthread_cond_t>,
    mutex: CPointer<pthread_mutex_t>
): Int

@KsSymbolName("pthread_cond_timedwait")
public external fun pthread_cond_timedwait(
    condition: CPointer<pthread_cond_t>,
    mutex: CPointer<pthread_mutex_t>,
    timeout: CPointer<timespec>
): Int

@KsSymbolName("pthread_cond_signal")
public external fun pthread_cond_signal(condition: CPointer<pthread_cond_t>): Int

@KsSymbolName("pthread_cond_broadcast")
public external fun pthread_cond_broadcast(condition: CPointer<pthread_cond_t>): Int

@KsSymbolName("pthread_cond_destroy")
public external fun pthread_cond_destroy(condition: CPointer<pthread_cond_t>): Int

@KsSymbolName("pthread_create")
public external fun pthread_create(
    thread: CPointer<pthread_tVar>,
    attr: CPointer<pthread_attr_t>?,
    startRoutine: CPointer<CFunction<(COpaquePointer?) -> COpaquePointer?>>?,
    argument: COpaquePointer?
): Int

@KsSymbolName("pthread_self")
public external fun pthread_self(): pthread_t

@KsSymbolName("pthread_equal")
public external fun pthread_equal(first: pthread_t, second: pthread_t): Int

@KsSymbolName("pthread_join")
public external fun pthread_join(
    thread: pthread_t,
    result: CPointer<COpaquePointerVar>?
): Int

@KsSymbolName("clock_gettime")
public external fun clock_gettime(clock: Int, result: CPointer<timespec>): Int

public var timespec.tv_sec: Long
    get() = ptr.reinterpret<LongVar>().pointed.value
    set(value) {
        ptr.reinterpret<LongVar>().pointed.value = value
    }

// Darwin's 64-bit timespec stores tv_nsec eight bytes after tv_sec.
public var timespec.tv_nsec: Long
    get() = (ptr.reinterpret<ByteVar>() + 8L).reinterpret<LongVar>().pointed.value
    set(value) {
        (ptr.reinterpret<ByteVar>() + 8L).reinterpret<LongVar>().pointed.value = value
    }

@KsSymbolName("pthread_get_qos_class_np")
public external fun pthread_get_qos_class_np(
    thread: pthread_t,
    qosClass: CPointer<UIntVar>,
    relativePriority: CPointer<IntVar>
): Int

@KsSymbolName("pthread_override_qos_class_start_np")
public external fun pthread_override_qos_class_start_np(
    thread: pthread_t,
    qosClass: qos_class_t,
    relativePriority: Int
): pthread_override_t?

@KsSymbolName("pthread_override_qos_class_end_np")
public external fun pthread_override_qos_class_end_np(
    override: pthread_override_t?
): Int

@KsSymbolName("qos_class_self")
public external fun qos_class_self(): qos_class_t
