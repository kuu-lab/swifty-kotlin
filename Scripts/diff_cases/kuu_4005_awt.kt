import java.awt.Color
import java.awt.Dimension
import java.awt.Font
import java.awt.GraphicsEnvironment
import java.awt.MouseInfo
import java.awt.Point
import java.awt.Rectangle
import java.awt.event.MouseAdapter
import java.awt.event.MouseEvent
import java.awt.image.BufferedImage
import javax.swing.JFrame
import javax.swing.JLabel
import javax.swing.JPanel
import javax.swing.SwingConstants
import javax.swing.WindowConstants

fun main() {
    // Color construction, channels, ARGB packing, derived colors.
    val c = Color(10, 20, 30, 128)
    println("color ${c.red}/${c.green}/${c.blue}/${c.alpha} rgb=${c.rgb}")
    println("brighter=${c.brighter().rgb} darker=${c.darker().rgb}")
    println("decode=${Color.decode("#0A0B0C").rgb}")
    println("hsb=${Color.getHSBColor(0.5f, 0.5f, 0.5f).rgb}")
    println("float-ctor=${Color(0.5f, 0.5f, 0.5f).rgb}")

    // Geometry value types.
    val p = Point(3, 4)
    p.translate(2, 1)
    println("point=${p.x},${p.y} dist=${p.distance(0.0, 0.0)} distSq=${p.distanceSq(0.0, 0.0)}")
    p.move(9, 9)
    println("moved=${p.location.x},${p.location.y}")
    val d = Dimension(30, 40)
    println("dim=${d.width}x${d.height}")
    val r = Rectangle(10, 20, 30, 40)
    println("rect=${r.x},${r.y} ${r.width}x${r.height} contains=${r.contains(15, 25)},${r.contains(100, 100)}")
    println("rect containsRect=${r.contains(Rectangle(11, 21, 5, 5))} intersects=${r.intersects(Rectangle(39, 59, 5, 5))}")
    println("rect union=${r.union(Rectangle(100, 100, 10, 10)).bounds}")

    // Raster image + Graphics drawing pipeline.
    val img = BufferedImage(8, 6, BufferedImage.TYPE_INT_ARGB)
    println("img type=${img.type} ${img.width}x${img.height}")
    img.setRGB(1, 1, c.rgb)
    println("pixel=${img.getRGB(1, 1)}")
    val g = img.createGraphics()
    g.color = Color.RED
    g.fillRect(0, 0, 4, 3)
    g.color = Color.GREEN
    g.drawLine(0, 0, 7, 5)
    g.drawRect(1, 1, 3, 3)
    g.fillOval(4, 0, 4, 4)
    println("fill px(1,1)=${img.getRGB(1, 1)} px(2,2)=${img.getRGB(2, 2)} px(6,1)=${img.getRGB(6, 1)}")
    val sub = img.getSubimage(0, 0, 4, 3)
    println("sub=${sub.width}x${sub.height} px=${sub.getRGB(1, 1)}")
    // Glyph rasterization and Java2D stroke coverage are engine-specific;
    // only the presence of oval-drawn pixels is deterministic here.
    g.drawString("hi", 0, 5)
    g.color = Color.BLUE
    g.drawOval(0, 0, 7, 5)
    var bluePixels = 0
    for (py in 0 until img.height) {
        for (px in 0 until img.width) {
            if (img.getRGB(px, py) == Color.BLUE.rgb) bluePixels += 1
        }
    }
    println("blue=${bluePixels > 0}")

    // Font values.
    val f = Font("Dialog", Font.BOLD or Font.ITALIC, 14)
    println("font=${f.name}/${f.family}/${f.style}/${f.size} bold=${f.isBold} italic=${f.isItalic} plain=${f.isPlain}")
    println("font2=${Font("Serif", Font.PLAIN, 12).style} derive=${f.deriveFont(Font.PLAIN, 10f).size}")

    // Component hierarchy + layout-free Swing widgets (headless-safe).
    val panel = JPanel()
    val label = JLabel("hello", SwingConstants.CENTER)
    panel.add(label)
    println("panel count=${panel.componentCount} first=${panel.components[0] === label}")
    panel.setBounds(1, 2, 300, 200)
    println("panel bounds=${panel.bounds.x},${panel.bounds.y},${panel.bounds.width}x${panel.bounds.height}")
    println("panel vis=${panel.isVisible} en=${panel.isEnabled} loc=${panel.location.x},${panel.location.y} size=${panel.size.width}")
    println("label text=${label.text} align=${label.horizontalAlignment}")
    label.setBounds(0, 0, 10, 10)
    println("label contains=${label.contains(5, 5)},${label.contains(50, 50)}")

    // Event dispatch through adapters.
    var clicks = 0
    var moves = 0
    var wheels = 0
    panel.addMouseListener(object : MouseAdapter() {
        override fun mouseClicked(e: MouseEvent) {
            clicks += 1
            println("click at ${e.x},${e.y} button=${e.button} count=${e.clickCount} popup=${e.isPopupTrigger}")
        }
    })
    panel.addMouseMotionListener(object : java.awt.event.MouseMotionAdapter() {
        override fun mouseMoved(e: MouseEvent) { moves += 1 }
    })
    panel.addMouseWheelListener(object : java.awt.event.MouseWheelListener {
        override fun mouseWheelMoved(e: java.awt.event.MouseWheelEvent) { wheels += e.wheelRotation }
    })
    panel.dispatchEvent(MouseEvent(panel, MouseEvent.MOUSE_CLICKED, 0L, 0, 7, 9, 1, false, MouseEvent.BUTTON1))
    panel.dispatchEvent(MouseEvent(panel, MouseEvent.MOUSE_MOVED, 0L, 0, 1, 1, 0, false, MouseEvent.NOBUTTON))
    panel.dispatchEvent(java.awt.event.MouseWheelEvent(panel, java.awt.event.MouseEvent.MOUSE_WHEEL, 0L, 0, 5, 5, 0, false,
        java.awt.event.MouseWheelEvent.WHEEL_UNIT_SCROLL, 3, -2))
    println("clicks=$clicks moves=$moves wheels=$wheels")
    println("event toString=${MouseEvent(panel, MouseEvent.MOUSE_PRESSED, 0L, 0, 1, 2, 0, false, MouseEvent.BUTTON2).id == MouseEvent.MOUSE_PRESSED}")

    // JFrame: on a headless JVM this throws HeadlessException — the try keeps
    // output deterministic on both engines.
    try {
        val frame = JFrame("demo")
        frame.defaultCloseOperation = WindowConstants.EXIT_ON_CLOSE
        frame.contentPane.add(label)
        frame.setSize(320, 240)
        frame.title = "demo2"
        println("frame ${frame.title} ${frame.width}x${frame.height} ops=${frame.defaultCloseOperation} kids=${frame.contentPane.componentCount}")
    } catch (e: java.awt.HeadlessException) {
        println("frame headless")
    }
    println("headless=${GraphicsEnvironment.isHeadless()}")
    try {
        val mp = MouseInfo.getPointerInfo().location
        println("mouse present=${mp.x >= 0 && mp.y >= 0}")
    } catch (e: java.awt.HeadlessException) {
        println("mouse headless")
    }
}
