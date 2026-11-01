package java.util

/** `java.util.EventObject` — root of all event classes. */
public open class EventObject(public val source: Any) {
    override fun toString(): String = "${this::class.simpleName ?: "EventObject"}[source=$source]"
}

/** `java.util.EventListener` — marker interface for all listeners. */
public interface EventListener
