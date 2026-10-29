#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

extension BuildKIRRegressionTests {
    // KUU-3726: a value-class receiver is its unboxed payload at the call
    // site, not a `kk_object_new` object, so an inherited `kotlin.Any`
    // member must never dispatch through the nominal layout's inherited
    // Any vtable slot — the runtime reads the raw payload as a pointer and
    // `kk_vtable_lookup` traps (KSWIFTK-RUNTIME-0001). These tests need the
    // `.kklib` stdlib: the source-injected `kotlin.Any` keeps an empty
    // vtable, so only the artifact exposes the inherited slot that used to
    // trigger the bogus virtual dispatch.

    /// A primitive-backed value class (`Int` payload) lowers `hashCode()`
    /// to the tagged `kk_any_hashCode` bridge — the tag lets the runtime
    /// decode the raw scalar representation.
    @Test
    func valueClassHashCodeCallsTaggedAnyBridgeNotVtable() throws {
        TestStdlibCache.shared.prepare()
        let context = makeContextFromSource("""
        @JvmInline value class VC(val v: Int)
        fun probe(): Int = VC(5).hashCode()
        """, allowDefaultStdlibLibrary: true)
        try runToKIR(context)
        #expect(!context.diagnostics.hasError)
        let module = try #require(context.kir)
        let body = try findKIRFunctionBody(
            named: "probe", in: module, interner: context.interner
        )

        #expect(
            extractCallees(from: body, interner: context.interner)
                .contains("kk_any_hashCode"),
            "primitive-backed value-class hashCode must use the tagged Any bridge"
        )
        #expect(
            extractVirtualCallees(from: body, interner: context.interner)
                .isEmpty,
            "no member may dispatch through a vtable the unboxed payload does not carry"
        )
    }

    /// `equals` on a primitive-backed value class keeps the direct tagged
    /// `kk_any_equals` bridge rather than a vtable slot on the raw payload.
    @Test
    func valueClassEqualsCallsTaggedAnyBridgeNotVtable() throws {
        TestStdlibCache.shared.prepare()
        let context = makeContextFromSource("""
        @JvmInline value class VC(val v: Int)
        fun probe(): Boolean = VC(5).equals(VC(5))
        """, allowDefaultStdlibLibrary: true)
        try runToKIR(context)
        #expect(!context.diagnostics.hasError)
        let module = try #require(context.kir)
        let body = try findKIRFunctionBody(
            named: "probe", in: module, interner: context.interner
        )

        #expect(
            extractCallees(from: body, interner: context.interner)
                .contains("kk_any_equals"),
            "primitive-backed value-class equals must use the tagged Any bridge"
        )
        #expect(
            extractVirtualCallees(from: body, interner: context.interner)
                .isEmpty,
            "no member may dispatch through a vtable the unboxed payload does not carry"
        )
    }

    /// An object-backed value class (`String` payload) is not a primitive
    /// fallback representation, so it keeps the boxed direct member bridge —
    /// still never a vtable dispatch on the unboxed payload.
    @Test
    func objectBackedValueClassHashCodeSkipsVtableDispatch() throws {
        TestStdlibCache.shared.prepare()
        let context = makeContextFromSource("""
        @JvmInline value class WS(val s: String)
        fun probe(): Int = WS("a").hashCode()
        """, allowDefaultStdlibLibrary: true)
        try runToKIR(context)
        #expect(!context.diagnostics.hasError)
        let module = try #require(context.kir)
        let body = try findKIRFunctionBody(
            named: "probe", in: module, interner: context.interner
        )

        #expect(
            extractVirtualCallees(from: body, interner: context.interner)
                .isEmpty,
            "no member may dispatch through a vtable the unboxed payload does not carry"
        )
    }
}
#endif
