package java.awt.geom

/** `java.awt.geom.Point2D` — abstract double-precision point base. */
public abstract class Point2D {
    public abstract fun getX(): kotlin.Double
    public abstract fun getY(): kotlin.Double

    public open fun setLocation(x: kotlin.Double, y: kotlin.Double) {
        throw UnsupportedOperationException()
    }

    /** `java.awt.geom.Point2D.Double`. */
    public open class Double(public var x: kotlin.Double = 0.0, public var y: kotlin.Double = 0.0) : Point2D() {
        override fun getX(): kotlin.Double = x
        override fun getY(): kotlin.Double = y
        override fun setLocation(x: kotlin.Double, y: kotlin.Double) {
            this.x = x; this.y = y
        }

        override fun toString(): String = "Point2D.Double[$x, $y]"
    }

    public companion object {
        public fun distance(x1: kotlin.Double, y1: kotlin.Double, x2: kotlin.Double, y2: kotlin.Double): kotlin.Double {
            val dx = x1 - x2; val dy = y1 - y2
            return kotlin.math.sqrt(dx * dx + dy * dy)
        }

        public fun distanceSq(x1: kotlin.Double, y1: kotlin.Double, x2: kotlin.Double, y2: kotlin.Double): kotlin.Double {
            val dx = x1 - x2; val dy = y1 - y2
            return dx * dx + dy * dy
        }
    }
}
