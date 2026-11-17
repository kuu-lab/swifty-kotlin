@testable import Runtime
import Testing

extension RuntimeBoxingTests {
    @Test
    func boxIntScalarAliasingUnrelatedObjectAddressBoxesNormally() {
        // The nullable/ambiguous Int entry points share the Long/Double hazard:
        // a 32-bit Int scalar can coincide with a low heap address (seen in the
        // O2 kotlinc diff as 0x40000000 rendering as `kotlin.Array@40000000`).
        let collider = registerRuntimeObject(RuntimeStringBox("kotlin.Any?"))
        let boxed = kk_box_int(collider)
        #expect(boxed != collider)
        #expect(kk_unbox_int(boxed) == collider)

        let boxedStatic = kk_box_int_static(collider)
        #expect(boxedStatic != collider)
        #expect(kk_unbox_int_static(boxedStatic) == collider)
    }
}
