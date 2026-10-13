@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
package platform.Foundation
import kotlin.internal.KsSymbolName
import kotlinx.cinterop.*
@KsSymbolName("__kk_foundation_attach")
internal external fun __foundation_attach(owner: Any, handle: Long): Unit

@KsSymbolName("__kk_foundation_object_create")
internal external fun __foundation_object_create(): Long

@KsSymbolName("__kk_foundation_object_kind")
internal external fun __foundation_object_kind(handle: Long): Int

@KsSymbolName("__kk_foundation_object_equals")
internal external fun __foundation_object_equals(lhs: Long, rhs: Long): Boolean

@KsSymbolName("__kk_foundation_object_hash")
internal external fun __foundation_object_hash(handle: Long): Int

@KsSymbolName("__kk_foundation_data_create")
internal external fun __foundation_data_create(bytes: CPointer<*>?, length: ULong, noCopy: Boolean, freeWhenDone: Boolean): Long

@KsSymbolName("__kk_foundation_data_base64")
internal external fun __foundation_data_base64(text: String, options: ULong): Long?

@KsSymbolName("__kk_foundation_data_length")
internal external fun __foundation_data_length(handle: Long): ULong

@KsSymbolName("__kk_foundation_data_bytes")
internal external fun __foundation_data_bytes(handle: Long): CPointer<ByteVar>?

@KsSymbolName("__kk_foundation_error_create")
internal external fun __foundation_error_create(domain: String, code: Long, description: String?, underlying: Any?): Long

@KsSymbolName("__kk_foundation_error_description")
internal external fun __foundation_error_description(handle: Long): String

@KsSymbolName("__kk_foundation_url_file")
internal external fun __foundation_url_file(path: String): Long

@KsSymbolName("__kk_foundation_input_create")
internal external fun __foundation_input_create(data: Long): Long

@KsSymbolName("__kk_foundation_input_url")
internal external fun __foundation_input_url(url: Long): Long

@KsSymbolName("__kk_foundation_output_create")
internal external fun __foundation_output_create(): Long

@KsSymbolName("__kk_foundation_stream_call")
internal external fun __foundation_stream_call(handle: Long, operation: Int, arg1: Any?, arg2: Any?): Any?

@KsSymbolName("__kk_foundation_stream_install")
internal external fun __foundation_stream_install(handle: Long, block: Any, input: Boolean): Unit

@KsSymbolName("__kk_foundation_stream_delegate")
internal external fun __foundation_stream_delegate(handle: Long, block: Any?): Unit

@KsSymbolName("__kk_foundation_stream_event")
internal external fun __foundation_stream_event(handle: Long, event: ULong): Unit

@KsSymbolName("__kk_foundation_runloop_current")
internal external fun __foundation_runloop_current(): Long

@KsSymbolName("__kk_foundation_runloop_perform")
internal external fun __foundation_runloop_perform(handle: Long, modes: Array<String>, block: Any): Unit

@KsSymbolName("__kk_foundation_runloop_run")
internal external fun __foundation_runloop_run(handle: Long): Unit

@KsSymbolName("__kk_foundation_runloop_stop")
internal external fun __foundation_runloop_stop(handle: CPointer<*>): Unit

@KsSymbolName("__kk_foundation_runloop_add_port")
internal external fun __foundation_runloop_add_port(handle: Long, port: Long, mode: String): Unit

@KsSymbolName("__kk_foundation_port_create")
internal external fun __foundation_port_create(): Long

@KsSymbolName("__kk_foundation_thread_create")
internal external fun __foundation_thread_create(block: Any): Long

@KsSymbolName("__kk_foundation_thread_current")
internal external fun __foundation_thread_current(): Long

@KsSymbolName("__kk_foundation_thread_name")
internal external fun __foundation_thread_name(handle: Long): String?

@KsSymbolName("__kk_foundation_thread_set_name")
internal external fun __foundation_thread_set_name(handle: Long, name: String?): Unit

@KsSymbolName("__kk_foundation_thread_start")
internal external fun __foundation_thread_start(handle: Long): Unit

@KsSymbolName("__kk_foundation_pinned_bytes_address")
internal external fun __foundation_pinned_bytes_address(pinned: Any, index: Int): CPointer<ByteVar>

@KsSymbolName("__kk_foundation_memcpy")
internal external fun __foundation_memcpy(dst: CPointer<*>?, src: CPointer<*>?, length: ULong): CPointer<*>?

@KsSymbolName("__kk_foundation_memset")
internal external fun __foundation_memset(dst: CPointer<*>?, value: Int, length: ULong): CPointer<*>?

@KsSymbolName("__kk_foundation_malloc")
internal external fun __foundation_malloc(length: ULong): CPointer<ByteVar>?

@KsSymbolName("__kk_foundation_free")
internal external fun __foundation_free(pointer: CPointer<*>?): Unit

@KsSymbolName("__kk_foundation_errno")
internal external fun __foundation_errno(): Int

@KsSymbolName("__kk_foundation_strerror")
internal external fun __foundation_strerror(code: Int): CPointer<ByteVar>?

@KsSymbolName("__kk_foundation_byte_pointer_add")
internal external fun __foundation_byte_pointer_add(pointer: CPointer<*>, offset: Int): CPointer<ByteVar>

@KsSymbolName("__kk_foundation_lock_create")
internal external fun __foundation_lock_create(): Long

@KsSymbolName("__kk_foundation_lock_lock")
internal external fun __foundation_lock_lock(handle: Long): Unit

@KsSymbolName("__kk_foundation_lock_unlock")
internal external fun __foundation_lock_unlock(handle: Long): Unit

@KsSymbolName("__kk_foundation_access")
internal external fun __foundation_access(path: String?, mode: Int): Int

@KsSymbolName("__kk_foundation_runloop_cf_pointer")
internal external fun __foundation_runloop_cf_pointer(handle: Long): CPointer<*>
