package kotlin.jvm.internal

public class Ref {
    public class BooleanRef: java.io.Serializable {
        @kotlin.jvm.JvmField public var element: Boolean = false
        override fun toString(): String = "$element"
    }
    public class ByteRef: java.io.Serializable {
        @kotlin.jvm.JvmField public var element: Byte = 0
        override fun toString(): String = "$element"
    }
    public class ShortRef: java.io.Serializable {
        @kotlin.jvm.JvmField public var element: Short = 0
        override fun toString(): String = "$element"
    }
    public class CharRef: java.io.Serializable {
        @kotlin.jvm.JvmField public var element: Char = '\u0000'
        override fun toString(): String = "$element"
    }
    public class IntRef: java.io.Serializable {
        @kotlin.jvm.JvmField public var element: Int = 0
        override fun toString(): String = "$element"
    }
    public class LongRef: java.io.Serializable {
        @kotlin.jvm.JvmField public var element: Long = 0L
        override fun toString(): String = "$element"
    }
    public class FloatRef: java.io.Serializable {
        @kotlin.jvm.JvmField public var element: Float = 0.0f
        override fun toString(): String = "$element"
    }
    public class DoubleRef: java.io.Serializable {
        @kotlin.jvm.JvmField public var element: Double = 0.0
        override fun toString(): String = "$element"
    }
    public class ObjectRef<T>: java.io.Serializable {
        @kotlin.jvm.JvmField public var element: T? = null
        override fun toString(): String = "$element"
    }
}
