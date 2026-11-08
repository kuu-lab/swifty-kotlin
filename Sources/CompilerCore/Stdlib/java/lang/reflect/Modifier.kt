package java.lang.reflect

/** JVM `java.lang.reflect.Modifier` constants and bit tests. */
public class Modifier private constructor() {
    public companion object {
        public const val PUBLIC: Int = 0x0001
        public const val PRIVATE: Int = 0x0002
        public const val PROTECTED: Int = 0x0004
        public const val STATIC: Int = 0x0008
        public const val FINAL: Int = 0x0010
        public const val SYNCHRONIZED: Int = 0x0020
        public const val VOLATILE: Int = 0x0040
        public const val TRANSIENT: Int = 0x0080
        public const val NATIVE: Int = 0x0100
        public const val INTERFACE: Int = 0x0200
        public const val ABSTRACT: Int = 0x0400
        public const val STRICT: Int = 0x0800

        // JVM keeps these fields package-private; only the is* tests are public.
        internal const val SYNTHETIC: Int = 0x1000
        internal const val ANNOTATION: Int = 0x2000
        internal const val ENUM: Int = 0x4000
        internal const val MANDATED: Int = 0x8000

        public fun isPublic(modifiers: Int): Boolean = modifiers and PUBLIC != 0
        public fun isPrivate(modifiers: Int): Boolean = modifiers and PRIVATE != 0
        public fun isProtected(modifiers: Int): Boolean = modifiers and PROTECTED != 0
        public fun isStatic(modifiers: Int): Boolean = modifiers and STATIC != 0
        public fun isFinal(modifiers: Int): Boolean = modifiers and FINAL != 0
        public fun isSynchronized(modifiers: Int): Boolean = modifiers and SYNCHRONIZED != 0
        public fun isVolatile(modifiers: Int): Boolean = modifiers and VOLATILE != 0
        public fun isTransient(modifiers: Int): Boolean = modifiers and TRANSIENT != 0
        public fun isNative(modifiers: Int): Boolean = modifiers and NATIVE != 0
        public fun isInterface(modifiers: Int): Boolean = modifiers and INTERFACE != 0
        public fun isAbstract(modifiers: Int): Boolean = modifiers and ABSTRACT != 0
        public fun isStrict(modifiers: Int): Boolean = modifiers and STRICT != 0
        internal fun isSynthetic(modifiers: Int): Boolean = modifiers and SYNTHETIC != 0
        internal fun isAnnotation(modifiers: Int): Boolean = modifiers and ANNOTATION != 0
        internal fun isEnum(modifiers: Int): Boolean = modifiers and ENUM != 0

        public fun toString(modifiers: Int): String {
            val parts = mutableListOf<String>()
            if (isPublic(modifiers)) parts.add("public")
            if (isProtected(modifiers)) parts.add("protected")
            if (isPrivate(modifiers)) parts.add("private")
            if (isAbstract(modifiers)) parts.add("abstract")
            if (isStatic(modifiers)) parts.add("static")
            if (isFinal(modifiers)) parts.add("final")
            if (isSynchronized(modifiers)) parts.add("synchronized")
            if (isNative(modifiers)) parts.add("native")
            if (isStrict(modifiers)) parts.add("strictfp")
            if (isTransient(modifiers)) parts.add("transient")
            if (isVolatile(modifiers)) parts.add("volatile")
            if (isInterface(modifiers)) parts.add("interface")
            if (isAnnotation(modifiers)) parts.add("annotation")
            return parts.joinToString(" ")
        }
    }
}
