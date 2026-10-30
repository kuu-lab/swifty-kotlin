#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

/// KUU-2365: an expression body may put the `if` else-branch expression on the
/// line after `else`, including when the declared return type is explicit.
@Suite
struct ExpressionBodyElseBranchNewlineTests {

    @Test
    func newlineElseBranchKeepsExpressionBodiesAndExistingContrasts() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSources([
            """
            package kuu2365

            class JSONObject {
                class Builder {
                }
                class Property {
                }
                companion object {
                    val EMPTY = JSONObject()
                    fun build(size: Int, block: Builder.() -> Unit): JSONObject = JSONObject()
                }
            }

            fun Map<String, Int?>.toJSONObject(): JSONObject = if (isEmpty()) JSONObject.EMPTY else
                JSONObject.build(size = size) {}

            fun JSONObject(vararg items: Pair<String, Int?>): JSONObject =
                if (items.isEmpty()) JSONObject.EMPTY else
                    JSONObject.build(size = items.size) {}

            fun JSONObject(vararg properties: JSONObject.Property): JSONObject =
                if (properties.isEmpty()) JSONObject.EMPTY else
                    JSONObject.build(size = properties.size) {}

            fun explicitSameLine(x: Boolean): Int = if (x) 0 else 1

            fun blockBody(x: Boolean): Int {
                return if (x) 0 else
                    1
            }

            fun inferred(x: Boolean) = if (x) 0 else
                1
            """
        ], allowDefaultStdlibLibrary: true)

        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
