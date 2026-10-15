package java.lang.reflect

/** JVM modifier flags used by native reflection consumers. */
public class Modifier private constructor() {
    public companion object {
        public const val PUBLIC: Int = 0x0001
        public const val STATIC: Int = 0x0008
        public const val FINAL: Int = 0x0010
    }
}
