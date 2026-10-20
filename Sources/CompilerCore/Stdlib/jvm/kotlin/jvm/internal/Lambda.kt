package kotlin.jvm.internal

public interface FunctionBase<out R>: kotlin.Function<R> { public val arity: Int }

public abstract class Lambda<out R>(override val arity: Int): FunctionBase<R>, java.io.Serializable {
    override fun toString(): String {
        val interfaces = __jvmGenericInterfaces(__jvmClassOf(this))
        return interfaces[0].toString().removePrefix("kotlin.jvm.functions.")
    }
}
