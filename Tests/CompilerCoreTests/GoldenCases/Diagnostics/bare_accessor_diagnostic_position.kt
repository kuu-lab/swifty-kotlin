// KUU-4154: a bare `get`/`set` on its own line is still an accessor
// declaration node, so accessor diagnostics must anchor at the accessor
// keyword rather than collapsing onto the property's modifier position.
open class B { open var w: Int = 0 }
class C : B() {
    protected override var w: Int = 1
        get
}
