package java.awt

import java.awt.event.ComponentEvent
import java.awt.event.FocusEvent
import java.awt.event.InputEvent
import java.awt.event.KeyEvent
import java.awt.event.KeyListener
import java.awt.event.MouseEvent
import java.awt.event.MouseListener
import java.awt.event.MouseMotionListener
import java.awt.event.MouseWheelEvent
import java.awt.event.MouseWheelListener
import java.awt.event.WindowEvent
import java.awt.event.WindowListener
import java.awt.image.BufferedImage
import kotlin.internal.KsSymbolName

/** `java.awt.AWTEvent` — root of all AWT events. */
public open class AWTEvent(source: Any, public val id: Int) : java.util.EventObject(source) {
    public fun getID(): Int = id

    override fun toString(): String = "AWTEvent[id=$id] on $source"

    public companion object {
        public const val COMPONENT_EVENT_MASK: Long = 0x01
        public const val CONTAINER_EVENT_MASK: Long = 0x02
        public const val FOCUS_EVENT_MASK: Long = 0x04
        public const val KEY_EVENT_MASK: Long = 0x08
        public const val MOUSE_EVENT_MASK: Long = 0x10
        public const val MOUSE_MOTION_EVENT_MASK: Long = 0x20
        public const val WINDOW_EVENT_MASK: Long = 0x40
        public const val ACTION_EVENT_MASK: Long = 0x80
        public const val ITEM_EVENT_MASK: Long = 0x200
        public const val TEXT_EVENT_MASK: Long = 0x400
        public const val RESERVED_ID_MAX: Int = 1999
    }
}

/** `java.awt.HeadlessException` — thrown when a display-dependent operation
 * runs without a display. */
public open class HeadlessException : UnsupportedOperationException {
    public constructor() : super()
    public constructor(message: String?) : super(message)
}

/** `java.awt.GraphicsEnvironment`. */
public open class GraphicsEnvironment {
    public fun isHeadless(): Boolean = isHeadlessEnvironment()
    public fun isHeadlessInstance(): Boolean = isHeadlessEnvironment()

    public companion object {
        private val localInstance = GraphicsEnvironment()

        public fun getLocalGraphicsEnvironment(): GraphicsEnvironment = localInstance
        public fun isHeadless(): Boolean = isHeadlessEnvironment()
    }
}

private fun isHeadlessEnvironment(): Boolean = awtIsHeadless() != 0

/** `java.awt.PointerInfo` — snapshot of the pointer position. */
public class PointerInfo internal constructor(private val locationPoint: Point) {
    public val location: Point get() = locationPoint
}

/** `java.awt.MouseInfo` — global pointer information. */
public object MouseInfo {

    public fun getNumberOfButtons(): Int = 3

    /** Snapshot of the current pointer position. Throws [HeadlessException]
     * on a headless platform like the JDK. */
    public fun getPointerInfo(): PointerInfo {
        val packed = awtPointerLocation()
        val x = (packed ushr 32).toInt()
        val y = (packed and 0xffffffffL).toInt()
        return PointerInfo(Point(x, y))
    }
}

/** `java.awt.Component` — the root of the widget hierarchy. The component
 * tree, geometry, visibility, and event dispatch are fully functional; on a
 * headless platform `Frame`/`Window` construction throws [HeadlessException]
 * like the JDK. */
public abstract class Component {
    public var x = 0
    public var y = 0
    public var width = 0
    public var height = 0
    private var visible = true
    private var enabled = true
    public var name: String = ""
    public var font: Font = Font("Dialog", Font.PLAIN, 12)
    public var foreground: Color? = null
    public var background: Color? = null
    internal var parent: Container? = null

    private val mouseListeners = mutableListOf<MouseListener>()
    private val mouseMotionListeners = mutableListOf<MouseMotionListener>()
    private val mouseWheelListeners = mutableListOf<MouseWheelListener>()
    private val keyListeners = mutableListOf<KeyListener>()


    public val bounds: Rectangle get() = Rectangle(x, y, width, height)
    public val location: Point get() = Point(x, y)
    public val size: Dimension get() = Dimension(width, height)
    public val isVisible: Boolean get() = visible
    public val isEnabled: Boolean get() = enabled
    public val isShowing: Boolean get() = visible
    public val parentComponent: Container? get() = parent

    public fun getX(): Int = x
    public fun getY(): Int = y
    public fun getWidth(): Int = width
    public fun getHeight(): Int = height

    public open fun setLocation(x: Int, y: Int) {
        this.x = x; this.y = y
    }

    public open fun setLocation(p: Point) = setLocation(p.x, p.y)

    public open fun setSize(width: Int, height: Int) {
        this.width = width; this.height = height
    }

    public open fun setSize(d: Dimension) = setSize(d.width, d.height)

    public open fun setBounds(x: Int, y: Int, width: Int, height: Int) {
        this.x = x; this.y = y; this.width = width; this.height = height
    }

    public open fun setBounds(r: Rectangle) = setBounds(r.x, r.y, r.width, r.height)

    public open fun setVisible(visible: Boolean) {
        this.visible = visible
    }

    public open fun show() = setVisible(true)
    public open fun hide() = setVisible(false)

    public open fun setEnabled(enabled: Boolean) {
        this.enabled = enabled
    }


    public open fun getParent(): Container? = parent

    public open fun addMouseListener(l: MouseListener) {
        mouseListeners.add(l)
    }

    public open fun removeMouseListener(l: MouseListener) {
        mouseListeners.remove(l)
    }

    public open fun getMouseListeners(): Array<MouseListener> = mouseListeners.toTypedArray()

    public open fun addMouseMotionListener(l: MouseMotionListener) {
        mouseMotionListeners.add(l)
    }

    public open fun removeMouseMotionListener(l: MouseMotionListener) {
        mouseMotionListeners.remove(l)
    }

    public open fun getMouseMotionListeners(): Array<MouseMotionListener> = mouseMotionListeners.toTypedArray()

    public open fun addMouseWheelListener(l: MouseWheelListener) {
        mouseWheelListeners.add(l)
    }

    public open fun getMouseWheelListeners(): Array<MouseWheelListener> = mouseWheelListeners.toTypedArray()

    public open fun addKeyListener(l: KeyListener) {
        keyListeners.add(l)
    }

    public open fun getKeyListeners(): Array<KeyListener> = keyListeners.toTypedArray()

    /** Dispatches an event to this component's listeners, exactly like the
     * JDK's `dispatchEvent` → `processEvent` chain. */
    public open fun dispatchEvent(e: AWTEvent) {
        processEvent(e)
    }

    protected open fun processEvent(e: AWTEvent) {
        when (e) {
            is MouseWheelEvent -> for (l in mouseWheelListeners.toList()) l.mouseWheelMoved(e)
            is MouseEvent -> when (e.id) {
                MouseEvent.MOUSE_CLICKED -> for (l in mouseListeners.toList()) l.mouseClicked(e)
                MouseEvent.MOUSE_PRESSED -> for (l in mouseListeners.toList()) l.mousePressed(e)
                MouseEvent.MOUSE_RELEASED -> for (l in mouseListeners.toList()) l.mouseReleased(e)
                MouseEvent.MOUSE_ENTERED -> for (l in mouseListeners.toList()) l.mouseEntered(e)
                MouseEvent.MOUSE_EXITED -> for (l in mouseListeners.toList()) l.mouseExited(e)
                MouseEvent.MOUSE_DRAGGED -> for (l in mouseMotionListeners.toList()) l.mouseDragged(e)
                MouseEvent.MOUSE_MOVED -> for (l in mouseMotionListeners.toList()) l.mouseMoved(e)
            }
            is KeyEvent -> when (e.id) {
                KeyEvent.KEY_TYPED -> for (l in keyListeners.toList()) l.keyTyped(e)
                KeyEvent.KEY_PRESSED -> for (l in keyListeners.toList()) l.keyPressed(e)
                KeyEvent.KEY_RELEASED -> for (l in keyListeners.toList()) l.keyReleased(e)
            }
        }
    }

    /** Hook for painting; `paint` calls [paintComponent]-style hooks on
     * subclasses. The default implementation draws nothing. */
    public open fun paint(g: Graphics) = Unit
    public open fun update(g: Graphics) = paint(g)
    public open fun repaint() = Unit
    public open fun repaint(x: Int, y: Int, width: Int, height: Int) = Unit

    public open fun getGraphics(): Graphics? = null

    public open fun getPreferredSize(): Dimension = Dimension(width, height)
    public open fun getMinimumSize(): Dimension = getPreferredSize()
    public open fun getMaximumSize(): Dimension = Dimension(Int.MAX_VALUE, Int.MAX_VALUE)
    public val preferredSize: Dimension get() = getPreferredSize()
    public open val minimumSize: Dimension get() = getPreferredSize()
    public open val maximumSize: Dimension get() = Dimension(Int.MAX_VALUE, Int.MAX_VALUE)

    public open fun contains(x: Int, y: Int): Boolean =
        x >= 0 && y >= 0 && x < width && y < height

    public open fun contains(p: Point): Boolean = contains(p.x, p.y)

    public open fun requestFocus() = Unit
    public open fun hasFocus(): Boolean = false
    public open fun validate() = Unit
    public open fun invalidate() = Unit
    public open fun isDisplayable(): Boolean = false

    override fun toString(): String =
        "Component[component${hashCode() and 0xffff},$x,$y,${width}x$height]"
}

/** `java.awt.Container` — a component that holds children. */
public open class Container : Component() {
    private val children = mutableListOf<Component>()

    public open fun add(comp: Component): Component {
        children.add(comp)
        comp.parent = this
        return comp
    }

    public open fun add(comp: Component, index: Int): Component {
        children.add(index.coerceIn(0, children.size), comp)
        comp.parent = this
        return comp
    }

    public open fun add(comp: Component, constraints: Any?): Component = add(comp)

    public open fun remove(comp: Component) {
        children.remove(comp)
        comp.parent = null
    }

    public open fun remove(index: Int) {
        val comp = children.removeAt(index)
        comp.parent = null
    }

    public open fun removeAll() {
        for (c in children) c.parent = null
        children.clear()
    }

    public open fun getComponent(index: Int): Component = children[index]
    public val components: Array<Component> get() = children.toTypedArray()
    public val componentCount: Int get() = children.size

    public open fun getComponentAt(x: Int, y: Int): Component? =
        children.lastOrNull { it.contains(x - it.x, y - it.y) }

    public open fun getComponentAt(p: Point): Component? = getComponentAt(p.x, p.y)

    override fun toString(): String =
        "Container[container,$x,$y,${width}x$height]"
}

/** `java.awt.Window` — a top-level window. */
public open class Window : Container() {
    private var windowListeners = mutableListOf<WindowListener>()
    private var packed = false

    public constructor() {
        if (GraphicsEnvironment.isHeadless()) throw HeadlessException()
    }

    public constructor(owner: Window?) : this()

    public open fun addWindowListener(l: WindowListener) {
        windowListeners.add(l)
    }

    public open fun removeWindowListener(l: WindowListener) {
        windowListeners.remove(l)
    }

    public open fun getWindowListeners(): Array<WindowListener> = windowListeners.toTypedArray()

    protected open fun processWindowEvent(e: WindowEvent) {
        for (l in windowListeners.toList()) {
            when (e.id) {
                WindowEvent.WINDOW_OPENED -> l.windowOpened(e)
                WindowEvent.WINDOW_CLOSING -> l.windowClosing(e)
                WindowEvent.WINDOW_CLOSED -> l.windowClosed(e)
                WindowEvent.WINDOW_ICONIFIED -> l.windowIconified(e)
                WindowEvent.WINDOW_DEICONIFIED -> l.windowDeiconified(e)
                WindowEvent.WINDOW_ACTIVATED -> l.windowActivated(e)
                else -> Unit
            }
        }
    }

    protected override fun processEvent(e: AWTEvent) {
        if (e is WindowEvent) processWindowEvent(e) else super.processEvent(e)
    }

    public open fun pack() {
        packed = true
    }

    public open fun setLocationRelativeTo(c: Component?) = Unit

    public open fun toFront() = Unit
    public open fun toBack() = Unit
    public open fun dispose() {
        setVisible(false)
    }

    public open fun isActive(): Boolean = isVisible
    public open fun isFocused(): Boolean = false
}

/** `java.awt.Frame` — a top-level window with a title. */
public open class Frame : Window {
    public var title: String
    public var resizable = true
    public var state = 0

    public constructor() : super() {
        title = ""
    }

    public constructor(title: String?) : super() {
        this.title = title ?: ""
    }





    override fun toString(): String =
        "Frame[frame${hashCode() and 0xffff},$x,$y,${width}x$height,title=$title]"

    public companion object {
        public const val NORMAL: Int = 0
        public const val ICONIFIED: Int = 1
        public const val MAXIMIZED_HORIZ: Int = 2
        public const val MAXIMIZED_VERT: Int = 4
        public const val MAXIMIZED_BOTH: Int = 6
        public const val DEFAULT_CURSOR: Int = 0
        public const val CROSSHAIR_CURSOR: Int = 1
        public const val TEXT_CURSOR: Int = 2
        public const val WAIT_CURSOR: Int = 3
        public const val HAND_CURSOR: Int = 12
    }
}

@KsSymbolName("__kk_awt_is_headless")
private external fun awtIsHeadless(): Int

/** Packed (x,y) pointer location: x in the high 32 bits, y in the low 32. */
@KsSymbolName("__kk_awt_pointer_location")
private external fun awtPointerLocation(): Long
