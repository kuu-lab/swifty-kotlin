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

@KsSymbolName("__kk_foundation_object_description")
internal external fun __foundation_object_description(handle: Long): String

@KsSymbolName("__kk_foundation_object_probe")
internal external fun __foundation_object_probe(raw: Any?): Long

@KsSymbolName("__kk_foundation_data_create")
internal external fun __foundation_data_create(bytes: CPointer<*>?, length: ULong, noCopy: Boolean, freeWhenDone: Boolean): Long

@KsSymbolName("__kk_foundation_data_base64")
internal external fun __foundation_data_base64(text: String, options: ULong): Long?

@KsSymbolName("__kk_foundation_data_length")
internal external fun __foundation_data_length(handle: Long): ULong

@KsSymbolName("__kk_foundation_data_bytes")
internal external fun __foundation_data_bytes(handle: Long): CPointer<ByteVar>?

@KsSymbolName("__kk_foundation_mutable_data_create")
internal external fun __foundation_mutable_data_create(): Long

@KsSymbolName("__kk_foundation_mutable_data_append")
internal external fun __foundation_mutable_data_append(handle: Long, bytes: CPointer<*>?, length: ULong): Unit

@KsSymbolName("__kk_foundation_mutable_data_create_length")
internal external fun __foundation_mutable_data_create_length(length: ULong): Long?

@KsSymbolName("__kk_foundation_data_compressed")
internal external fun __foundation_data_compressed(handle: Long, algorithm: Long): Long?

@KsSymbolName("__kk_foundation_data_decompressed")
internal external fun __foundation_data_decompressed(handle: Long, algorithm: Long): Long?

@KsSymbolName("__kk_foundation_string_data_using_encoding")
internal external fun __foundation_string_data_using_encoding(text: String, encoding: ULong): Long?

@KsSymbolName("__kk_foundation_string_from_data")
internal external fun __foundation_string_from_data(handle: Long, encoding: ULong): String?

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
internal external fun __foundation_byte_pointer_add(pointer: CPointer<*>, offset: Long): CPointer<ByteVar>

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

@KsSymbolName("__kk_foundation_date_now")
internal external fun __foundation_date_now(): Long

@KsSymbolName("__kk_foundation_date_create_reference")
internal external fun __foundation_date_create_reference(seconds: Double): Long

@KsSymbolName("__kk_foundation_date_create_since")
internal external fun __foundation_date_create_since(seconds: Double, since: Long): Long

@KsSymbolName("__kk_foundation_date_interval")
internal external fun __foundation_date_interval(handle: Long, kind: Int): Double

@KsSymbolName("__kk_foundation_date_add")
internal external fun __foundation_date_add(handle: Long, seconds: Double): Long

@KsSymbolName("__kk_foundation_date_extreme")
internal external fun __foundation_date_extreme(handle: Long, other: Long, kind: Int): Long

@KsSymbolName("__kk_foundation_date_compare")
internal external fun __foundation_date_compare(handle: Long, other: Long): Long

@KsSymbolName("__kk_foundation_date_is_equal")
internal external fun __foundation_date_is_equal(handle: Long, other: Long): Boolean

@KsSymbolName("__kk_foundation_date_interval_since")
internal external fun __foundation_date_interval_since(handle: Long, other: Long): Double

@KsSymbolName("__kk_foundation_date_description")
internal external fun __foundation_date_description(handle: Long): String

@KsSymbolName("__kk_foundation_date_distant")
internal external fun __foundation_date_distant(kind: Int): Long

@KsSymbolName("__kk_foundation_date_factory_since1970")
internal external fun __foundation_date_factory_since1970(seconds: Double): Long

@KsSymbolName("__kk_foundation_date_factory_since_now")
internal external fun __foundation_date_factory_since_now(seconds: Double): Long

@KsSymbolName("__kk_foundation_date_factory_since")
internal external fun __foundation_date_factory_since(seconds: Double, since: Long): Long

@KsSymbolName("__kk_foundation_date_formatter_create")
internal external fun __foundation_date_formatter_create(): Long

@KsSymbolName("__kk_foundation_date_formatter_date_format")
internal external fun __foundation_date_formatter_date_format(handle: Long): String?

@KsSymbolName("__kk_foundation_date_formatter_set_date_format")
internal external fun __foundation_date_formatter_set_date_format(handle: Long, format: String?): Unit

@KsSymbolName("__kk_foundation_date_formatter_style")
internal external fun __foundation_date_formatter_style(handle: Long, kind: Int): ULong

@KsSymbolName("__kk_foundation_date_formatter_set_style")
internal external fun __foundation_date_formatter_set_style(handle: Long, kind: Int, value: ULong): Unit

@KsSymbolName("__kk_foundation_date_formatter_bool")
internal external fun __foundation_date_formatter_bool(handle: Long, kind: Int): Boolean

@KsSymbolName("__kk_foundation_date_formatter_set_bool")
internal external fun __foundation_date_formatter_set_bool(handle: Long, kind: Int, value: Boolean): Unit

@KsSymbolName("__kk_foundation_date_formatter_object")
internal external fun __foundation_date_formatter_object(handle: Long, kind: Int): Any?

@KsSymbolName("__kk_foundation_date_formatter_set_object")
internal external fun __foundation_date_formatter_set_object(handle: Long, kind: Int, value: Long): Unit

@KsSymbolName("__kk_foundation_date_formatter_string_from_date")
internal external fun __foundation_date_formatter_string_from_date(handle: Long, date: Long): String

@KsSymbolName("__kk_foundation_date_formatter_date_from_string")
internal external fun __foundation_date_formatter_date_from_string(handle: Long, string: String): Any?

@KsSymbolName("__kk_foundation_date_formatter_localized_string")
internal external fun __foundation_date_formatter_localized_string(date: Long, dateStyle: ULong, timeStyle: ULong): String

@KsSymbolName("__kk_foundation_date_formatter_format_from_template")
internal external fun __foundation_date_formatter_format_from_template(template: String, options: ULong, locale: Long): String?

@KsSymbolName("__kk_foundation_timezone_create_name")
internal external fun __foundation_timezone_create_name(name: String): Long

@KsSymbolName("__kk_foundation_timezone_name")
internal external fun __foundation_timezone_name(handle: Long): String

@KsSymbolName("__kk_foundation_timezone_abbreviation")
internal external fun __foundation_timezone_abbreviation(handle: Long): String?

@KsSymbolName("__kk_foundation_timezone_seconds_from_gmt")
internal external fun __foundation_timezone_seconds_from_gmt(handle: Long): Long

@KsSymbolName("__kk_foundation_timezone_seconds_from_gmt_for_date")
internal external fun __foundation_timezone_seconds_from_gmt_for_date(handle: Long, date: Long): Long

@KsSymbolName("__kk_foundation_timezone_abbreviation_for_date")
internal external fun __foundation_timezone_abbreviation_for_date(handle: Long, date: Long): String?

@KsSymbolName("__kk_foundation_timezone_is_equal")
internal external fun __foundation_timezone_is_equal(handle: Long, other: Long): Boolean

@KsSymbolName("__kk_foundation_timezone_local")
internal external fun __foundation_timezone_local(): Long

@KsSymbolName("__kk_foundation_timezone_system")
internal external fun __foundation_timezone_system(): Long

@KsSymbolName("__kk_foundation_timezone_with_name")
internal external fun __foundation_timezone_with_name(name: String): Any?

@KsSymbolName("__kk_foundation_timezone_with_abbreviation")
internal external fun __foundation_timezone_with_abbreviation(abbreviation: String): Any?

@KsSymbolName("__kk_foundation_timezone_for_seconds_from_gmt")
internal external fun __foundation_timezone_for_seconds_from_gmt(seconds: Long): Long

@KsSymbolName("__kk_foundation_locale_create_identifier")
internal external fun __foundation_locale_create_identifier(identifier: String): Long

@KsSymbolName("__kk_foundation_locale_identifier")
internal external fun __foundation_locale_identifier(handle: Long): String

@KsSymbolName("__kk_foundation_locale_language_code")
internal external fun __foundation_locale_language_code(handle: Long): String?

@KsSymbolName("__kk_foundation_locale_country_code")
internal external fun __foundation_locale_country_code(handle: Long): String?

@KsSymbolName("__kk_foundation_locale_current")
internal external fun __foundation_locale_current(): Long

@KsSymbolName("__kk_foundation_locale_autoupdating")
internal external fun __foundation_locale_autoupdating(): Long

@KsSymbolName("__kk_foundation_locale_with_identifier")
internal external fun __foundation_locale_with_identifier(identifier: String): Long

@KsSymbolName("__kk_foundation_defaults_standard")
internal external fun __foundation_defaults_standard(): Long

@KsSymbolName("__kk_foundation_defaults_create_suite")
internal external fun __foundation_defaults_create_suite(suiteName: String): Long

@KsSymbolName("__kk_foundation_defaults_object_for_key")
internal external fun __foundation_defaults_object_for_key(handle: Long, key: String): Any?

@KsSymbolName("__kk_foundation_defaults_string_for_key")
internal external fun __foundation_defaults_string_for_key(handle: Long, key: String): String?

@KsSymbolName("__kk_foundation_defaults_bool_for_key")
internal external fun __foundation_defaults_bool_for_key(handle: Long, key: String): Boolean

@KsSymbolName("__kk_foundation_defaults_integer_for_key")
internal external fun __foundation_defaults_integer_for_key(handle: Long, key: String): Long

@KsSymbolName("__kk_foundation_defaults_double_for_key")
internal external fun __foundation_defaults_double_for_key(handle: Long, key: String): Double

@KsSymbolName("__kk_foundation_defaults_float_for_key")
internal external fun __foundation_defaults_float_for_key(handle: Long, key: String): Float

@KsSymbolName("__kk_foundation_defaults_set_object")
internal external fun __foundation_defaults_set_object(handle: Long, value: Any?, key: String): Unit

@KsSymbolName("__kk_foundation_defaults_set_bool")
internal external fun __foundation_defaults_set_bool(handle: Long, value: Boolean, key: String): Unit

@KsSymbolName("__kk_foundation_defaults_set_integer")
internal external fun __foundation_defaults_set_integer(handle: Long, value: Long, key: String): Unit

@KsSymbolName("__kk_foundation_defaults_set_double")
internal external fun __foundation_defaults_set_double(handle: Long, value: Double, key: String): Unit

@KsSymbolName("__kk_foundation_defaults_set_float")
internal external fun __foundation_defaults_set_float(handle: Long, value: Float, key: String): Unit

@KsSymbolName("__kk_foundation_defaults_remove_object_for_key")
internal external fun __foundation_defaults_remove_object_for_key(handle: Long, key: String): Unit

@KsSymbolName("__kk_foundation_defaults_synchronize")
internal external fun __foundation_defaults_synchronize(handle: Long): Boolean

@KsSymbolName("__kk_foundation_defaults_dictionary_representation")
internal external fun __foundation_defaults_dictionary_representation(handle: Long): Any?

@KsSymbolName("__kk_foundation_defaults_persistent_domain_for_name")
internal external fun __foundation_defaults_persistent_domain_for_name(handle: Long, name: String): Any?

@KsSymbolName("__kk_foundation_defaults_set_persistent_domain")
internal external fun __foundation_defaults_set_persistent_domain(handle: Long, domain: Map<Any?, Any?>, name: String): Unit

@KsSymbolName("__kk_foundation_defaults_remove_persistent_domain_for_name")
internal external fun __foundation_defaults_remove_persistent_domain_for_name(handle: Long, name: String): Unit

@KsSymbolName("__kk_foundation_defaults_register_defaults")
internal external fun __foundation_defaults_register_defaults(handle: Long, domain: Map<Any?, Any?>): Unit

@KsSymbolName("__kk_foundation_defaults_volatile_domain_names")
internal external fun __foundation_defaults_volatile_domain_names(handle: Long): List<String>

@KsSymbolName("__kk_foundation_defaults_persistent_domain_names")
internal external fun __foundation_defaults_persistent_domain_names(handle: Long): List<String>

@KsSymbolName("__kk_foundation_defaults_object_is_forced_for_key")
internal external fun __foundation_defaults_object_is_forced_for_key(handle: Long, key: String): Boolean

@KsSymbolName("__kk_foundation_uuid_create")
internal external fun __foundation_uuid_create(): Long

@KsSymbolName("__kk_foundation_uuid_string")
internal external fun __foundation_uuid_string(handle: Long): String

@KsSymbolName("__kk_foundation_thread_callstack")
internal external fun __foundation_thread_callstack(): List<String>

@KsSymbolName("__kk_foundation_thread_is_main")
internal external fun __foundation_thread_is_main(): Boolean

@KsSymbolName("__kk_foundation_thread_sleep")
internal external fun __foundation_thread_sleep(seconds: Double): Unit

@KsSymbolName("__kk_foundation_nslog")
internal external fun __foundation_nslog(format: String, arguments: Array<out Any?>): Unit
