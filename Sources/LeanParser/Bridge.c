#include <lean/lean.h>
#include <pthread.h>

typedef uint8_t (*read_token_fn)(void *, size_t);
typedef struct {
    void *state;
    read_token_fn read_token;
} parser_callbacks;

extern void lean_initialize_runtime_module(void);
extern void lean_initialize_thread(void);
extern void lean_finalize_thread(void);
extern lean_object *initialize_ParserProofs_TypeArgumentOffset(uint8_t builtin, lean_object *world);
extern uint8_t kswiftk_lean_can_start_type_arguments(size_t context, size_t count, uint8_t has_anchor);

extern size_t kswiftk_lean_offset_past_type_arguments(size_t context, size_t count, size_t start);

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
    lean_object *result = initialize_ParserProofs_TypeArgumentOffset(1, lean_io_mk_world());
    int ok = lean_io_result_is_ok(result);
    lean_dec_ref(result);
    lean_io_mark_end_initialization();
    return ok;
}

uint8_t kswiftk_lean_read_parser_token(size_t context, size_t index) {
    const parser_callbacks *callbacks = (const parser_callbacks *)context;
    return callbacks->read_token(callbacks->state, index);
}

int32_t kswiftk_lean_parser_can_start_type_arguments(void *state, read_token_fn read_token,
                                                    size_t count, uint8_t has_anchor) {
    if (!prepare_thread()) {
        return -1;
    }
    const parser_callbacks callbacks = { .state = state, .read_token = read_token };
    return kswiftk_lean_can_start_type_arguments((size_t)&callbacks, count, has_anchor);
}

size_t kswiftk_lean_parser_offset_past_type_arguments(void *state, read_token_fn read_token,
                                                      size_t count, size_t start) {
    if (!prepare_thread()) {
        return SIZE_MAX;
    }
    const parser_callbacks callbacks = { .state = state, .read_token = read_token };
    return kswiftk_lean_offset_past_type_arguments((size_t)&callbacks, count, start);
}
