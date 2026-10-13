@testable import Runtime
import Testing

@Suite
struct RuntimeCoroutineContextKeyTypeTests {
    @Test
    func interceptorAndDispatcherKeysPreserveNominalTypes() {
        let interceptorKey = kk_continuation_interceptor_key()
        let dispatcherKey = kk_coroutine_dispatcher_key()
        let keyToken = nominalTypeToken(for: "kotlin.coroutines.CoroutineContext.Key")
        let interceptorToken = nominalTypeToken(for: "kotlin.coroutines.ContinuationInterceptor.Key")
        let dispatcherToken = nominalTypeToken(for: "kotlinx.coroutines.CoroutineDispatcher.Key")

        #expect(kk_continuation_interceptor_key() == interceptorKey)
        #expect(kk_coroutine_dispatcher_key() == dispatcherKey)
        #expect(interceptorKey != dispatcherKey)
        #expect(kk_op_is(interceptorKey, keyToken) == 1)
        #expect(kk_op_is(dispatcherKey, keyToken) == 1)
        #expect(kk_op_is(interceptorKey, interceptorToken) == 1)
        #expect(kk_op_is(dispatcherKey, dispatcherToken) == 1)
        #expect(kk_op_is(interceptorKey, dispatcherToken) == 0)
        #expect(kk_op_is(dispatcherKey, interceptorToken) == 0)
        for key in [interceptorKey, dispatcherKey] {
            #expect(kk_op_safe_cast(key, keyToken) == key)
            #expect(kk_op_is(key, nominalTypeToken(for: "kotlin.coroutines.CoroutineContext.Element")) == 0)
            #expect(kk_op_is(key, nominalTypeToken(for: "kotlin.coroutines.ContinuationInterceptor")) == 0)
        }
    }
}
