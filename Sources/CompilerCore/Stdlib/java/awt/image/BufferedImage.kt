package java.awt.image

import java.awt.Color
import java.awt.Image

/** `java.awt.image.ImageObserver` callback interface. */
public interface ImageObserver {

    public companion object {
        public const val WIDTH: Int = 1
        public const val HEIGHT: Int = 2
        public const val PROPERTIES: Int = 4
        public const val SOMEBITS: Int = 8
        public const val FRAMEBITS: Int = 16
        public const val ALLBITS: Int = 32
        public const val ERROR: Int = 64
        public const val ABORT: Int = 128
    }
}

/** `java.awt.image.BufferedImage`: an ARGB integer raster. All pixel
 * operations are real — reads and writes update the raster exactly like the
 * JDK's `TYPE_INT_ARGB`/`TYPE_INT_RGB` images. */
public open class BufferedImage : java.awt.Image() {
    public val imageType: Int
    private val raster: IntArray
    private var graphics: java.awt.Graphics? = null

    public constructor(width: Int, height: Int, imageType: Int) {
        if (width <= 0 || height <= 0) throw IllegalArgumentException("Width ($width) and height ($height) must be > 0")
        this.imageType = imageType
        raster = IntArray(width * height)
        this.internalWidth = width
        this.internalHeight = height
    }

    private val internalWidth: Int
    private val internalHeight: Int

    public override val width: Int get() = internalWidth
    public override val height: Int get() = internalHeight

    public val type: Int get() = imageType
    public fun getType(): Int = imageType

    public fun getRGB(x: Int, y: Int): Int {
        if (x < 0 || y < 0 || x >= internalWidth || y >= internalHeight) {
            throw ArrayIndexOutOfBoundsException("Coordinate out of bounds!")
        }
        return raster[y * internalWidth + x]
    }

    public fun setRGB(x: Int, y: Int, rgb: Int) {
        if (x < 0 || y < 0 || x >= internalWidth || y >= internalHeight) {
            throw ArrayIndexOutOfBoundsException("Coordinate out of bounds!")
        }
        raster[y * internalWidth + x] = rgb
    }

    public fun getRGB(startX: Int, startY: Int, w: Int, h: Int, rgbArray: IntArray?, offset: Int, scansize: Int): IntArray {
        val target = rgbArray ?: IntArray(offset + (h - 1) * scansize + w)
        for (row in 0 until h) {
            for (col in 0 until w) {
                target[offset + row * scansize + col] = getRGB(startX + col, startY + row)
            }
        }
        return target
    }

    public fun setRGB(startX: Int, startY: Int, w: Int, h: Int, rgbArray: IntArray, offset: Int, scansize: Int) {
        for (row in 0 until h) {
            for (col in 0 until w) {
                setRGB(startX + col, startY + row, rgbArray[offset + row * scansize + col])
            }
        }
    }


    /** ARGB pixel at `(x, y)`, or the alpha-composited value. */




    public fun getSubimage(x: Int, y: Int, w: Int, h: Int): BufferedImage {
        val sub = BufferedImage(w, h, imageType)
        for (row in 0 until h) {
            for (col in 0 until w) {
                sub.setRGB(col, row, getRGB(x + col, y + row))
            }
        }
        return sub
    }

    /** Returns a [java.awt.Graphics] drawing onto this raster. */
    public fun createGraphics(): java.awt.Graphics {
        val g = java.awt.RasterGraphics(this)
        graphics = g
        return g
    }

    public override fun getGraphics(): java.awt.Graphics = createGraphics()

    internal fun rawPixel(x: Int, y: Int): Int = raster[y * internalWidth + x]
    internal fun writePixel(x: Int, y: Int, value: Int) {
        raster[y * internalWidth + x] = value
    }
    internal fun inBounds(x: Int, y: Int): Boolean = x >= 0 && y >= 0 && x < internalWidth && y < internalHeight

    override fun toString(): String =
        "BufferedImage@" + hashCode().toString(16) + ": type = $imageType"

    public companion object {
        public const val TYPE_CUSTOM: Int = 0
        public const val TYPE_INT_RGB: Int = 1
        public const val TYPE_INT_ARGB: Int = 2
        public const val TYPE_INT_ARGB_PRE: Int = 3
        public const val TYPE_INT_BGR: Int = 4
        public const val TYPE_3BYTE_BGR: Int = 5
        public const val TYPE_4BYTE_ABGR: Int = 6
        public const val TYPE_4BYTE_ABGR_PRE: Int = 7
        public const val TYPE_BYTE_GRAY: Int = 10
        public const val TYPE_BYTE_BINARY: Int = 12
        public const val TYPE_BYTE_INDEXED: Int = 13
    }
}

internal fun argbOf(color: Color): Int = color.rgb
