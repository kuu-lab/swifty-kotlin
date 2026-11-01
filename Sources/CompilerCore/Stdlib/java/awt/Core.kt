package java.awt

import kotlin.math.floor

import kotlin.internal.KsSymbolName

/** JVM-shaped `java.awt.Color`: immutable ARGB color. */
public class Color {
    public val value: Int

    public constructor(r: Int, g: Int, b: Int) : this(r, g, b, 255)

    public constructor(r: Int, g: Int, b: Int, a: Int) {
        value = ((a and 0xff) shl 24) or ((r and 0xff) shl 16) or ((g and 0xff) shl 8) or (b and 0xff)
        if ((r and 0xff.inv()) != 0 || (g and 0xff.inv()) != 0 || (b and 0xff.inv()) != 0 || (a and 0xff.inv()) != 0) {
            throw IllegalArgumentException("Color parameter outside of expected range")
        }
    }

    public constructor(rgb: Int) {
        value = 0xff shl 24 or (rgb and 0xffffff)
    }

    public constructor(rgba: Int, hasAlpha: Boolean) {
        value = if (hasAlpha) rgba else 0xff shl 24 or (rgba and 0xffffff)
    }

    public constructor(r: Float, g: Float, b: Float) : this(
        (r.coerceIn(0f, 1f) * 255 + 0.5f).toInt(),
        (g.coerceIn(0f, 1f) * 255 + 0.5f).toInt(),
        (b.coerceIn(0f, 1f) * 255 + 0.5f).toInt()
    )

    public constructor(r: Float, g: Float, b: Float, a: Float) : this(
        (r.coerceIn(0f, 1f) * 255 + 0.5f).toInt(),
        (g.coerceIn(0f, 1f) * 255 + 0.5f).toInt(),
        (b.coerceIn(0f, 1f) * 255 + 0.5f).toInt(),
        (a.coerceIn(0f, 1f) * 255 + 0.5f).toInt()
    )

    public val red: Int get() = (value shr 16) and 0xff
    public val green: Int get() = (value shr 8) and 0xff
    public val blue: Int get() = value and 0xff
    public val alpha: Int get() = (value shr 24) and 0xff
    public val rgb: Int get() = value

    public fun getRed(): Int = red
    public fun getGreen(): Int = green
    public fun getBlue(): Int = blue
    public fun getAlpha(): Int = alpha
    public fun getRGB(): Int = value

    public fun brighter(): Color {
        val f = 0.7
        var r = red; var g = green; var b = blue
        val i = (1.0 / (1.0 - f)).toInt()
        if (r == 0 && g == 0 && b == 0) {
            return Color(i, i, i, alpha)
        }
        if (r in 1 until i) r = i
        if (g in 1 until i) g = i
        if (b in 1 until i) b = i
        return Color(
            minOf((r / f).toInt(), 255),
            minOf((g / f).toInt(), 255),
            minOf((b / f).toInt(), 255),
            alpha
        )
    }

    public fun darker(): Color {
        val f = 0.7
        return Color(
            maxOf((red * f).toInt(), 0),
            maxOf((green * f).toInt(), 0),
            maxOf((blue * f).toInt(), 0),
            alpha
        )
    }

    override fun equals(other: Any?): Boolean = other is Color && other.value == value
    override fun hashCode(): Int = value
    override fun toString(): String = "java.awt.Color[r=$red,g=$green,b=$blue]"

    public companion object {
        public val WHITE: Color = Color(255, 255, 255)
        public val LIGHT_GRAY: Color = Color(192, 192, 192)
        public val GRAY: Color = Color(128, 128, 128)
        public val DARK_GRAY: Color = Color(64, 64, 64)
        public val BLACK: Color = Color(0, 0, 0)
        public val RED: Color = Color(255, 0, 0)
        public val PINK: Color = Color(255, 175, 175)
        public val ORANGE: Color = Color(255, 200, 0)
        public val YELLOW: Color = Color(255, 255, 0)
        public val GREEN: Color = Color(0, 255, 0)
        public val MAGENTA: Color = Color(255, 0, 255)
        public val CYAN: Color = Color(0, 255, 255)
        public val BLUE: Color = Color(0, 0, 255)

        /** JVM-style `r,g,b` constants also exposed under UPPER_SNAKE names. */
        public val white: Color get() = WHITE
        public val lightGray: Color get() = LIGHT_GRAY
        public val gray: Color get() = GRAY
        public val darkGray: Color get() = DARK_GRAY
        public val black: Color get() = BLACK
        public val red: Color get() = RED
        public val pink: Color get() = PINK
        public val orange: Color get() = ORANGE
        public val yellow: Color get() = YELLOW
        public val green: Color get() = GREEN
        public val magenta: Color get() = MAGENTA
        public val cyan: Color get() = CYAN
        public val blue: Color get() = BLUE

        public fun decode(numericString: String): Color {
            val s = numericString.removePrefix("#").removePrefix("0x").removePrefix("0X")
            val rgb = s.toIntOrNull(16) ?: throw NumberFormatException("For input string: \"$numericString\"")
            return Color(rgb)
        }

        public fun getColor(name: String): Color? = null
        public fun getColor(name: String, default: Color?): Color? = default
        public fun getColor(name: String, default: Int): Color = Color(default)

        public fun getHSBColor(h: Float, s: Float, b: Float): Color = hsb(h, s, b)

        internal fun hsb(h: Float, s: Float, v: Float): Color {
            var r = 0f; var g = 0f; var b = 0f
            val hh = (h - floor(h.toDouble()).toFloat()) * 6f
            val f = hh - floor(hh.toDouble()).toFloat()
            val p = v * (1f - s)
            val q = v * (1f - s * f)
            val t = v * (1f - s * (1f - f))
            when (hh.toInt()) {
                0 -> { r = v; g = t; b = p }
                1 -> { r = q; g = v; b = p }
                2 -> { r = p; g = v; b = t }
                3 -> { r = p; g = q; b = v }
                4 -> { r = t; g = p; b = v }
                else -> { r = v; g = p; b = q }
            }
            return Color(r, g, b)
        }
    }
}

/** JVM-shaped `java.awt.Point`: mutable integer location. `x`/`y` are public
 * fields as in the JDK. */
public open class Point {
    public var x: Int
    public var y: Int

    public constructor() {
        x = 0; y = 0
    }

    public constructor(x: Int, y: Int) {
        this.x = x; this.y = y
    }

    public constructor(p: Point) {
        x = p.x; y = p.y
    }

    public val location: Point get() = Point(x, y)
    public fun setLocation(x: Int, y: Int) {
        this.x = x; this.y = y
    }

    public fun setLocation(p: Point) {
        x = p.x; y = p.y
    }

    public fun distance(x2: kotlin.Double, y2: kotlin.Double): kotlin.Double {
        val dx = x.toDouble() - x2; val dy = y.toDouble() - y2
        return kotlin.math.sqrt(dx * dx + dy * dy)
    }

    public fun distance(p: Point): kotlin.Double = distance(p.x.toDouble(), p.y.toDouble())

    public fun distanceSq(x2: kotlin.Double, y2: kotlin.Double): kotlin.Double {
        val dx = x.toDouble() - x2; val dy = y.toDouble() - y2
        return dx * dx + dy * dy
    }

    public fun distanceSq(p: Point): kotlin.Double = distanceSq(p.x.toDouble(), p.y.toDouble())

    public fun move(x: Int, y: Int) {
        this.x = x; this.y = y
    }

    public fun translate(dx: Int, dy: Int) {
        x += dx; y += dy
    }

    override fun equals(other: Any?): Boolean = other is Point && other.x == x && other.y == y
    override fun hashCode(): Int = 31 * x + y
    override fun toString(): String = "java.awt.Point[x=$x,y=$y]"
}

public open class Dimension {
    public var width: Int
    public var height: Int

    public constructor() {
        width = 0; height = 0
    }

    public constructor(width: Int, height: Int) {
        this.width = width; this.height = height
    }

    public constructor(d: Dimension) {
        width = d.width; height = d.height
    }

    public val size: Dimension get() = Dimension(width, height)
    public fun setSize(width: Int, height: Int) {
        this.width = width; this.height = height
    }

    public fun setSize(d: Dimension) {
        width = d.width; height = d.height
    }


    override fun equals(other: Any?): Boolean =
        other is Dimension && other.width == width && other.height == height
    override fun hashCode(): Int = width + height
    override fun toString(): String = "java.awt.Dimension[width=$width,height=$height]"
}

public open class Rectangle {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public constructor() : this(0, 0, 0, 0)
    public constructor(width: Int, height: Int) : this(0, 0, width, height)
    public constructor(x: Int, y: Int, width: Int, height: Int) {
        this.x = x; this.y = y; this.width = width; this.height = height
    }

    public constructor(p: Point, d: Dimension) : this(p.x, p.y, d.width, d.height)
    public constructor(d: Dimension) : this(0, 0, d.width, d.height)
    public constructor(p: Point) : this(p.x, p.y, 0, 0)
    public constructor(r: Rectangle) : this(r.x, r.y, r.width, r.height)

    public val location: Point get() = Point(x, y)
    public fun setLocation(x: Int, y: Int) {
        this.x = x; this.y = y
    }

    public fun setLocation(p: Point) {
        x = p.x; y = p.y
    }

    public val size: Dimension get() = Dimension(width, height)
    public fun setSize(w: Int, h: Int) {
        width = w; height = h
    }

    public fun setSize(d: Dimension) {
        width = d.width; height = d.height
    }


    public fun setBounds(x: Int, y: Int, width: Int, height: Int) {
        this.x = x; this.y = y; this.width = width; this.height = height
    }

    public fun setBounds(r: Rectangle) = setBounds(r.x, r.y, r.width, r.height)
    public val bounds: Rectangle get() = Rectangle(x, y, width, height)

    public fun contains(px: Int, py: Int): Boolean =
        px >= x && py >= y && px < x + width && py < y + height

    public fun contains(p: Point): Boolean = contains(p.x, p.y)
    public fun contains(rx: Int, ry: Int, rw: Int, rh: Int): Boolean =
        contains(rx, ry) && contains(rx + rw - 1, ry + rh - 1)

    public fun contains(r: Rectangle): Boolean = contains(r.x, r.y, r.width, r.height)
    public fun inside(px: Int, py: Int): Boolean = contains(px, py)

    public fun intersects(r: Rectangle): Boolean =
        r.width > 0 && r.height > 0 && width > 0 && height > 0 &&
            r.x < x + width && r.x + r.width > x &&
            r.y < y + height && r.y + r.height > y

    public fun isEmpty(): Boolean = width <= 0 || height <= 0

    public fun grow(h: Int, v: Int) {
        x -= h; y -= v; width += 2 * h; height += 2 * v
    }

    public fun translate(dx: Int, dy: Int) {
        x += dx; y += dy
    }

    public fun add(px: Int, py: Int) {
        val x2 = minOf(x, px); val y2 = minOf(y, py)
        width = maxOf(x + width, px + 1) - x2
        height = maxOf(y + height, py + 1) - y2
        x = x2; y = y2
    }

    public fun add(p: Point) = add(p.x, p.y)

    public fun union(r: Rectangle): Rectangle {
        val x2 = minOf(x, r.x); val y2 = minOf(y, r.y)
        return Rectangle(x2, y2, maxOf(x + width, r.x + r.width) - x2, maxOf(y + height, r.y + r.height) - y2)
    }

    public fun intersection(r: Rectangle): Rectangle {
        val x2 = maxOf(x, r.x); val y2 = maxOf(y, r.y)
        return Rectangle(x2, y2, maxOf(0, minOf(x + width, r.x + r.width) - x2), maxOf(0, minOf(y + height, r.y + r.height) - y2))
    }

    override fun equals(other: Any?): Boolean =
        other is Rectangle && other.x == x && other.y == y && other.width == width && other.height == height
    override fun hashCode(): Int = x + 31 * (y + 31 * (width + 31 * height))
    override fun toString(): String = "java.awt.Rectangle[x=$x,y=$y,width=$width,height=$height]"
}
