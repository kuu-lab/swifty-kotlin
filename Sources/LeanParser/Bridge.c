#include <lean/lean.h>
#include <pthread.h>

typedef uint32_t (*read_token_fn)(void *, size_t);
typedef void (*record_cache_fn)(void *, size_t, size_t, uint8_t);
typedef void (*report_budget_fn)(void *, size_t);
typedef uint64_t (*parse_file_item_fn)(void *, uint8_t);
typedef size_t (*emit_file_item_fn)(void *, uint8_t, size_t);

typedef struct {
    void *state;
    read_token_fn read_token;
    record_cache_fn record_cache;
    report_budget_fn report_budget;
    void *file_state;
    parse_file_item_fn parse_file_item;
    emit_file_item_fn emit_file_item;
} parser_callbacks;

extern void lean_initialize_runtime_module(void);
extern void lean_initialize_thread(void);
extern void lean_finalize_thread(void);
extern lean_object *initialize_ParserProofs_Runtime_TypeArgumentsFFI(uint8_t builtin, lean_object *world);
extern uint8_t kswiftk_lean_can_start_type_arguments(size_t context, size_t count, size_t start,
                                                     uint8_t has_anchor);
extern size_t kswiftk_lean_parser_lookahead(size_t context, size_t count, size_t start,
                                          uint8_t operation, size_t argument);
extern uint8_t kswiftk_lean_parser_continues_before_newline(uint8_t kind);
extern uint8_t kswiftk_lean_parser_should_split_on_newline(uint8_t kind);
extern uint8_t kswiftk_lean_parser_should_stop_statement(uint8_t kind, uint8_t in_block, uint8_t newline);
extern lean_object *kswiftk_lean_type_arguments(size_t context, size_t count, size_t start,
                                               uint32_t work_limit, lean_object *world);
extern lean_object *kswiftk_lean_genuine_declaration(size_t context, size_t count, size_t start,
                                                    uint8_t mode, uint32_t work_limit,
                                                    lean_object *world);
extern lean_object *kswiftk_lean_parse_file(size_t context, size_t count, size_t start,
                                           uint32_t work_limit, lean_object *world);
extern lean_object *kswiftk_lean_property_accessor(size_t context, size_t count, size_t start,
                                                  uint8_t allows_bodyless, uint32_t work_limit,
                                                  lean_object *world);
extern lean_object *kswiftk_lean_annotation_prefix(size_t context, size_t count, size_t start,
                                                   uint32_t work_limit, lean_object *world);
extern lean_object *kswiftk_lean_balanced_group(size_t context, size_t count, size_t start,
                                               uint8_t opening, uint8_t closing, uint8_t options,
                                               uint32_t work_limit, lean_object *world);

static pthread_key_t thread_key;

static void finalize_thread(void *state) {
    (void)state;
    lean_finalize_thread();
}

static bool prepare_thread(void) {
    if (pthread_getspecific(thread_key) != NULL) {
        return true;
    }
    lean_initialize_thread();
    if (pthread_setspecific(thread_key, (void *)1) == 0) {
        return true;
    }
    lean_finalize_thread();
    return false;
}

int kswiftk_lean_parser_init(void) {
    lean_initialize_runtime_module();
    if (pthread_key_create(&thread_key, finalize_thread) != 0) {
        return 0;
    }
    lean_object *result = initialize_ParserProofs_Runtime_TypeArgumentsFFI(1, lean_io_mk_world());
    int ok = lean_io_result_is_ok(result);
    lean_dec_ref(result);
    lean_io_mark_end_initialization();
    return ok;
}

uint32_t kswiftk_lean_read_token(size_t context, size_t index) {
    parser_callbacks *callbacks = (parser_callbacks *)context;
    return callbacks->read_token(callbacks->state, index);
}

lean_object *kswiftk_lean_record_cache(size_t context, size_t start, size_t end,
                                      uint8_t declares, lean_object *world) {
    (void)world;
    parser_callbacks *callbacks = (parser_callbacks *)context;
    callbacks->record_cache(callbacks->state, start, end, declares);
    return lean_io_result_mk_ok(lean_box(0));
}

lean_object *kswiftk_lean_report_budget(size_t context, size_t index, lean_object *world) {
    (void)world;
    parser_callbacks *callbacks = (parser_callbacks *)context;
    callbacks->report_budget(callbacks->state, index);
    return lean_io_result_mk_ok(lean_box(0));
}

static uint64_t unpack_scan_result(lean_object *result) {
    uint64_t packed = lean_io_result_is_ok(result)
        ? lean_unbox_uint64(lean_io_result_get_value(result))
        : UINT64_MAX;
    lean_dec_ref(result);
    return packed;
}

lean_object *kswiftk_lean_parse_file_item(size_t context, uint8_t dispatch, lean_object *world) {
    (void)world;
    parser_callbacks *callbacks = (parser_callbacks *)context;
    return lean_io_result_mk_ok(lean_box_uint64(callbacks->parse_file_item(callbacks->file_state, dispatch)));
}

lean_object *kswiftk_lean_emit_file_item(size_t context, uint8_t action, size_t separators, lean_object *world) {
    (void)world;
    parser_callbacks *callbacks = (parser_callbacks *)context;
    return lean_io_result_mk_ok(lean_box_usize(callbacks->emit_file_item(callbacks->file_state, action, separators)));
}

uint64_t kswiftk_lean_parser_parse_file(void *state, void *file_state, read_token_fn read_token,
                                       record_cache_fn record_cache, report_budget_fn report_budget,
                                       parse_file_item_fn parse_file_item, emit_file_item_fn emit_file_item,
                                       size_t count, size_t start, uint32_t work_limit) {
    if (!prepare_thread()) {
        return UINT64_MAX;
    }
    parser_callbacks callbacks = {
        .state = state, .read_token = read_token, .record_cache = record_cache, .report_budget = report_budget,
        .file_state = file_state, .parse_file_item = parse_file_item, .emit_file_item = emit_file_item
    };
    return unpack_scan_result(kswiftk_lean_parse_file((size_t)&callbacks, count, start, work_limit, lean_io_mk_world()));
}

uint64_t kswiftk_lean_parser_scan_group(void *state, read_token_fn read_token,
                                       record_cache_fn record_cache, report_budget_fn report_budget,
                                       size_t count, size_t start, uint8_t opening, uint8_t closing,
                                       uint8_t options, uint32_t work_limit) {
    if (!prepare_thread()) {
        return UINT64_MAX;
    }
    parser_callbacks callbacks = {
        .state = state, .read_token = read_token, .record_cache = record_cache, .report_budget = report_budget
    };
    return unpack_scan_result(kswiftk_lean_balanced_group((size_t)&callbacks, count, start,
                                                         opening, closing, options, work_limit, lean_io_mk_world()));
}

int kswiftk_lean_parser_can_start_type_arguments(void *state, read_token_fn read_token,
                                                size_t count, size_t start, uint8_t has_anchor) {
    if (!prepare_thread()) {
        return -1;
    }
    parser_callbacks callbacks = {.state = state, .read_token = read_token};
    return kswiftk_lean_can_start_type_arguments((size_t)&callbacks, count, start, has_anchor);
}

size_t kswiftk_lean_parser_run_lookahead(void *state, read_token_fn read_token, size_t count,
                                       size_t start, uint8_t operation, size_t argument) {
    if (!prepare_thread()) {
        return SIZE_MAX;
    }
    parser_callbacks callbacks = {.state = state, .read_token = read_token};
    return kswiftk_lean_parser_lookahead((size_t)&callbacks, count, start, operation, argument);
}

int32_t kswiftk_lean_parser_classify_before_newline(uint8_t kind) {
    if (!prepare_thread()) {
        return -1;
    }
    return kswiftk_lean_parser_continues_before_newline(kind);
}

int32_t kswiftk_lean_parser_classify_split_on_newline(uint8_t kind) {
    if (!prepare_thread()) {
        return -1;
    }
    return kswiftk_lean_parser_should_split_on_newline(kind);
}

int32_t kswiftk_lean_parser_classify_statement_stop(uint8_t kind, uint8_t in_block, uint8_t newline) {
    if (!prepare_thread()) {
        return -1;
    }
    return kswiftk_lean_parser_should_stop_statement(kind, in_block, newline);
}

uint64_t kswiftk_lean_parser_scan(void *state, read_token_fn read_token,
                                record_cache_fn record_cache, report_budget_fn report_budget,
                                size_t count, size_t start, uint32_t work_limit) {
    if (!prepare_thread()) {
        return UINT64_MAX;
    }
    parser_callbacks callbacks = {
        .state = state, .read_token = read_token, .record_cache = record_cache, .report_budget = report_budget
    };
    return unpack_scan_result(kswiftk_lean_type_arguments((size_t)&callbacks, count, start,
                                                         work_limit, lean_io_mk_world()));
}

uint64_t kswiftk_lean_parser_declaration_prefix(void *state, read_token_fn read_token,
                                              record_cache_fn record_cache, report_budget_fn report_budget,
                                              size_t count, size_t start, uint8_t mode,
                                              uint32_t work_limit) {
    if (!prepare_thread()) {
        return UINT64_MAX;
    }
    parser_callbacks callbacks = {
        .state = state, .read_token = read_token, .record_cache = record_cache, .report_budget = report_budget
    };
    return unpack_scan_result(kswiftk_lean_genuine_declaration((size_t)&callbacks, count, start,
                                                             mode, work_limit, lean_io_mk_world()));
}

uint64_t kswiftk_lean_parser_annotation_prefix(void *state, read_token_fn read_token,
                                             report_budget_fn report_budget,
                                             size_t count, size_t start, uint32_t work_limit) {
    if (!prepare_thread()) {
        return UINT64_MAX;
    }
    parser_callbacks callbacks = {
        .state = state, .read_token = read_token, .report_budget = report_budget
    };
    return unpack_scan_result(kswiftk_lean_annotation_prefix((size_t)&callbacks, count, start,
                                                            work_limit, lean_io_mk_world()));
}

uint64_t kswiftk_lean_parser_property_accessor(void *state, read_token_fn read_token,
                                              record_cache_fn record_cache, report_budget_fn report_budget,
                                              size_t count, size_t start, uint8_t allows_bodyless,
                                              uint32_t work_limit) {
    if (!prepare_thread()) {
        return UINT64_MAX;
    }
    parser_callbacks callbacks = {
        .state = state, .read_token = read_token, .record_cache = record_cache, .report_budget = report_budget
    };
    return unpack_scan_result(kswiftk_lean_property_accessor((size_t)&callbacks, count, start,
                                                            allows_bodyless, work_limit, lean_io_mk_world()));
}
