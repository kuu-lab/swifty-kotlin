import kotlinx.serialization.*
@Required class BadRequired
@Transient class BadTransient
@EncodeDefault class BadDefault
@Required fun badRequiredFunction() {}
@Transient fun badTransientFunction() {}
@EncodeDefault fun badDefaultFunction() {}
class BadField(@field:Required val value: Int)
class BadGetter(@get:Transient val value: Int)
class BadParameter(@param:EncodeDefault val value: Int)
fun wrongArguments() {
    Required(1)
    Transient(1)
    EncodeDefault(null)
    EncodeDefault(1)
    EncodeDefault(value = EncodeDefault.Mode.ALWAYS)
}
@EncodeDefault(EncodeDefault.Mode.valueOf("ALWAYS")) val nonconstant: Int = 1
