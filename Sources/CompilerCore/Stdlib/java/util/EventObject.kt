package java.util

public open class EventObject(public val source: Any) {
    override fun toString(): String = "${this::class.simpleName ?: "EventObject"}[source=$source]"
}

public interface EventListener
