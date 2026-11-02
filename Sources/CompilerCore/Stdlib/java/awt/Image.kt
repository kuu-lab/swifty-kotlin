package java.awt

/** `java.awt.Image` — the abstract image base. */
public abstract class Image {
    public abstract val width: Int
    public abstract val height: Int


    public open fun getGraphics(): Graphics? = null

    public companion object {
        public const val SCALE_DEFAULT: Int = 1
        public const val SCALE_FAST: Int = 2
        public const val SCALE_SMOOTH: Int = 4
        public const val SCALE_REPLICATE: Int = 8
        public const val SCALE_AREA_AVERAGING: Int = 16
    }
}

