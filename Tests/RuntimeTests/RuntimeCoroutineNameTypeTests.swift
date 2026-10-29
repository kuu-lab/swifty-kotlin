@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.all))
struct RuntimeCoroutineNameTypeTests {
    @Test
    func coroutineNameCreationRetainsNominalAndContextTypes() {
        let direct = kk_coroutine_name_create(runtimeRegisterObject(RuntimeStringBox("first")))
        let generated = RuntimeCoroutineContext(name: "fallback").nameHandleRaw
        let nameType = nominalTypeToken(for: "kotlinx.coroutines.CoroutineName")
        let elementType = nominalTypeToken(for: "kotlin.coroutines.CoroutineContext.Element")
        let contextType = nominalTypeToken(for: "kotlin.coroutines.CoroutineContext")
        let otherType = nominalTypeToken(for: "kotlinx.coroutines.Job")
        let key = kk_coroutine_name_key()
        for value in [direct, generated] {
            #expect(kk_op_is(value, nameType) == 1)
            #expect(kk_op_is(value, elementType) == 1)
            #expect(kk_op_is(value, contextType) == 1)
            #expect(kk_op_is(value, otherType) == 0)
            var thrown = 0
            #expect(kk_op_cast(value, nameType, &thrown) == value)
            #expect(thrown == 0)
            #expect(kk_context_get(value, key) == value)
        }
        let combined = kk_context_plus(kk_dispatcher_default(), direct)
        #expect(kk_context_get(combined, key) == direct)
        #expect(kk_context_get(0, key) == 0)
    }
}
