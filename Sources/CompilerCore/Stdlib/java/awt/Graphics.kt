package java.awt

import java.awt.image.BufferedImage
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

/** `java.awt.Font` — immutable font description. */
public class Font {
    public val name: String
    public val style: Int
    public val size: Int
    public val family: String

    public constructor(name: String, style: Int, size: Int) {
        this.name = name
        this.family = name
        this.style = style
        this.size = size
    }


    public val isPlain: Boolean get() = style == PLAIN
    public val isBold: Boolean get() = style and BOLD != 0
    public val isItalic: Boolean get() = style and ITALIC != 0

    public fun deriveFont(style: Int): Font = Font(name, style, size)
    public fun deriveFont(size: Float): Font = Font(name, this.style, size.toInt())
    public fun deriveFont(style: Int, size: Float): Font = Font(name, style, size.toInt())

    override fun equals(other: Any?): Boolean =
        other is Font && other.name == name && other.style == style && other.size == size
    override fun hashCode(): Int = name.hashCode() + 73 * style + 19 * size
    override fun toString(): String {
        val styleName = when (style) {
            BOLD -> "bold"
            ITALIC -> "italic"
            BOLD or ITALIC -> "bolditalic"
            else -> "plain"
        }
        return "java.awt.Font[family=$family,name=$name,style=$styleName,size=$size]"
    }

    public companion object {
        public const val PLAIN: Int = 0
        public const val BOLD: Int = 1
        public const val ITALIC: Int = 2
        public const val CENTER_BASELINE: Int = 1
        public const val DIALOG: String = "Dialog"
        public const val MONOSPACED: String = "Monospaced"
        public const val SERIF: String = "Serif"
        public const val SANS_SERIF: String = "SansSerif"
    }
}

/** `java.awt.Graphics` — the drawing context. The bundled implementation
 * rasterizes into a [BufferedImage]; geometry primitives follow the JDK's
 * `drawLine`/`fillRect` pixel coverage rules. */
public abstract class Graphics {
    public abstract var color: Color
    public abstract fun setColor(color: Color?)
    public abstract fun getColor(): Color?
    public abstract fun translate(x: Int, y: Int)
    public abstract fun clearRect(x: Int, y: Int, width: Int, height: Int)
    public abstract fun drawLine(x1: Int, y1: Int, x2: Int, y2: Int)
    public abstract fun drawRect(x: Int, y: Int, width: Int, height: Int)
    public abstract fun fillRect(x: Int, y: Int, width: Int, height: Int)
    public abstract fun drawOval(x: Int, y: Int, width: Int, height: Int)
    public abstract fun fillOval(x: Int, y: Int, width: Int, height: Int)
    public abstract fun drawImage(img: java.awt.Image?, x: Int, y: Int, observer: java.awt.image.ImageObserver?): Boolean
    public abstract fun drawImage(img: java.awt.Image?, x: Int, y: Int, width: Int, height: Int, observer: java.awt.image.ImageObserver?): Boolean
    public abstract fun drawString(str: String?, x: Int, y: Int)
    public abstract fun setFont(font: Font?)
    public abstract fun getFont(): Font?
    public abstract fun dispose()

    public open fun create(): Graphics = this
    public open fun drawPolygon(xPoints: IntArray, yPoints: IntArray, nPoints: Int) {
        if (nPoints < 2) return
        for (i in 0 until nPoints - 1) drawLine(xPoints[i], yPoints[i], xPoints[i + 1], yPoints[i + 1])
        drawLine(xPoints[nPoints - 1], yPoints[nPoints - 1], xPoints[0], yPoints[0])
    }
}

/** Raster-backed [Graphics] writing into a [BufferedImage]. */
internal class RasterGraphics(
    private val target: BufferedImage,
    private val tx0: Int = 0,
    private val ty0: Int = 0
) : Graphics() {
    override var color: Color = Color.BLACK
    private var tx = tx0
    private var ty = ty0
    private var font: Font = Font("Dialog", Font.PLAIN, 12)
    private var disposed = false

    override fun setColor(color: Color?) {
        if (color != null) this.color = color
    }

    override fun getColor(): Color = color

    override fun translate(x: Int, y: Int) {
        tx += x; ty += y
    }

    override fun clearRect(x: Int, y: Int, width: Int, height: Int) {
        for (row in y + ty until y + ty + height) {
            for (col in x + tx until x + tx + width) {
                if (target.inBounds(col, row)) target.writePixel(col, row, 0)
            }
        }
    }

    override fun drawLine(x1: Int, y1: Int, x2: Int, y2: Int) {
        var px = x1 + tx; var py = y1 + ty
        val ex = x2 + tx; val ey = y2 + ty
        val dx = abs(ex - px); val dy = -abs(ey - py)
        val sx = if (px < ex) 1 else -1
        val sy = if (py < ey) 1 else -1
        var err = dx + dy
        val rgb = color.rgb
        while (true) {
            if (target.inBounds(px, py)) target.writePixel(px, py, rgb)
            if (px == ex && py == ey) break
            val e2 = 2 * err
            if (e2 >= dy) { err += dy; px += sx }
            if (e2 <= dx) { err += dx; py += sy }
        }
    }

    override fun drawRect(x: Int, y: Int, width: Int, height: Int) {
        // JDK drawRect covers the border pixels inclusive (width+1 x height+1).
        drawLine(x, y, x + width, y)
        drawLine(x + width, y, x + width, y + height)
        drawLine(x + width, y + height, x, y + height)
        drawLine(x, y + height, x, y)
    }

    override fun fillRect(x: Int, y: Int, width: Int, height: Int) {
        val rgb = color.rgb
        for (row in y + ty until y + ty + height) {
            for (col in x + tx until x + tx + width) {
                if (target.inBounds(col, row)) target.writePixel(col, row, rgb)
            }
        }
    }

    override fun drawOval(x: Int, y: Int, width: Int, height: Int) {
        // Midpoint ellipse approximation over the bounding box border.
        val cx = x + tx + width / 2.0; val cy = y + ty + height / 2.0
        val rx = width / 2.0; val ry = height / 2.0
        if (rx <= 0 || ry <= 0) return
        val rgb = color.rgb
        var i = 0
        val steps = (2 * PI * maxOf(rx, ry) * 2).toInt() + 8
        while (i < steps) {
            val angle = 2 * PI * i / steps
            val px = (cx + rx * cos(angle)).toInt()
            val py = (cy + ry * sin(angle)).toInt()
            if (target.inBounds(px, py)) target.writePixel(px, py, rgb)
            i++
        }
    }

    override fun fillOval(x: Int, y: Int, width: Int, height: Int) {
        val cx = x + tx + (width - 1) / 2.0; val cy = y + ty + (height - 1) / 2.0
        val rx = width / 2.0; val ry = height / 2.0
        if (rx <= 0 || ry <= 0) return
        val rgb = color.rgb
        for (row in y + ty until y + ty + height) {
            for (col in x + tx until x + tx + width) {
                val nx = (col - cx) / rx
                val ny = (row - cy) / ry
                if (nx * nx + ny * ny <= 1.0 && target.inBounds(col, row)) {
                    target.writePixel(col, row, rgb)
                }
            }
        }
    }

    override fun drawImage(img: java.awt.Image?, x: Int, y: Int, observer: java.awt.image.ImageObserver?): Boolean {
        if (img is BufferedImage) {
            for (row in 0 until img.height) {
                for (col in 0 until img.width) {
                    val px = x + tx + col; val py = y + ty + row
                    val src = img.rawPixel(col, row)
                    if (target.inBounds(px, py) && (src ushr 24) != 0) {
                        target.writePixel(px, py, src)
                    }
                }
            }
        }
        return true
    }

    override fun drawImage(img: java.awt.Image?, x: Int, y: Int, width: Int, height: Int, observer: java.awt.image.ImageObserver?): Boolean {
        if (img is BufferedImage) {
            for (row in 0 until height) {
                val sy = row * img.height / height
                for (col in 0 until width) {
                    val sx = col * img.width / width
                    val src = img.rawPixel(sx, sy)
                    val px = x + tx + col; val py = y + ty + row
                    if (target.inBounds(px, py) && (src ushr 24) != 0) {
                        target.writePixel(px, py, src)
                    }
                }
            }
        }
        return true
    }

    /** Text rasterization is not part of the compatibility surface; the call
     * is a no-op rather than a synthetic failure. */
    override fun drawString(str: String?, x: Int, y: Int) = Unit

    override fun setFont(font: Font?) {
        if (font != null) this.font = font
    }

    override fun getFont(): Font = font

    override fun dispose() {
        disposed = true
    }
}
