package java.awt.event

import java.awt.AWTEvent
import java.awt.Component
import java.awt.Point
import java.util.EventListener
import java.util.EventObject

/** `java.awt.event.ComponentEvent`. */
public open class ComponentEvent(source: Component, id: Int) : AWTEvent(source, id) {
    public fun getComponent(): Component = source as Component

    public companion object {
        public const val COMPONENT_FIRST: Int = 100
        public const val COMPONENT_LAST: Int = 103
        public const val COMPONENT_MOVED: Int = 100
        public const val COMPONENT_RESIZED: Int = 101
        public const val COMPONENT_SHOWN: Int = 102
        public const val COMPONENT_HIDDEN: Int = 103
    }
}

/** `java.awt.event.FocusEvent`. */
public open class FocusEvent(source: Component, id: Int) : ComponentEvent(source, id) {
    public companion object {
        public const val FOCUS_FIRST: Int = 1004
        public const val FOCUS_LAST: Int = 1005
        public const val FOCUS_GAINED: Int = 1004
        public const val FOCUS_LOST: Int = 1005
    }
}

/** `java.awt.event.InputEvent` — base for mouse and key events. */
public open class InputEvent(
    source: Component,
    id: Int,
    public val `when`: Long,
    public val modifiers: Int
) : ComponentEvent(source, id) {
    public fun getModifiersEx(): Int = modifiers

    public fun isAltDown(): Boolean = modifiers and ALT_MASK != 0 || modifiers and ALT_DOWN_MASK != 0
    public fun isShiftDown(): Boolean = modifiers and SHIFT_MASK != 0 || modifiers and SHIFT_DOWN_MASK != 0
    public fun isControlDown(): Boolean = modifiers and CTRL_MASK != 0 || modifiers and CTRL_DOWN_MASK != 0
    public fun isMetaDown(): Boolean = modifiers and META_MASK != 0 || modifiers and META_DOWN_MASK != 0
    public fun consume() {
        consumed = true
    }

    private var consumed = false

    public companion object {
        public const val SHIFT_MASK: Int = 1
        public const val CTRL_MASK: Int = 2
        public const val META_MASK: Int = 4
        public const val ALT_MASK: Int = 8
        public const val BUTTON1_MASK: Int = 16
        public const val BUTTON2_MASK: Int = 8
        public const val BUTTON3_MASK: Int = 4
        public const val SHIFT_DOWN_MASK: Int = 1 shl 6
        public const val CTRL_DOWN_MASK: Int = 1 shl 7
        public const val META_DOWN_MASK: Int = 1 shl 8
        public const val ALT_DOWN_MASK: Int = 1 shl 9
        public const val BUTTON1_DOWN_MASK: Int = 1 shl 10
        public const val BUTTON2_DOWN_MASK: Int = 1 shl 11
        public const val BUTTON3_DOWN_MASK: Int = 1 shl 12
        public const val ALT_GRAPH_MASK: Int = 1 shl 5
        public const val ALT_GRAPH_DOWN_MASK: Int = 1 shl 13
    }
}

/** `java.awt.event.MouseEvent`. */
public open class MouseEvent(
    source: Component,
    id: Int,
    `when`: Long,
    modifiers: Int,
    public val x: Int,
    public val y: Int,
    public val xAbs: Int,
    public val yAbs: Int,
    public val clickCount: Int,
    public val isPopupTrigger: Boolean,
    public val button: Int
) : InputEvent(source, id, `when`, modifiers) {
    public constructor(source: Component, id: Int, `when`: Long, modifiers: Int, x: Int, y: Int, clickCount: Int, popupTrigger: Boolean, button: Int) :
        this(source, id, `when`, modifiers, x, y, x, y, clickCount, popupTrigger, button)

    public constructor(source: Component, id: Int, `when`: Long, modifiers: Int, x: Int, y: Int, clickCount: Int, popupTrigger: Boolean) :
        this(source, id, `when`, modifiers, x, y, clickCount, popupTrigger, NOBUTTON)

    public val point: Point get() = Point(x, y)
    public fun getLocationOnScreen(): Point = Point(xAbs, yAbs)

    public fun translatePoint(dx: Int, dy: Int) {
        // MouseEvent coordinates are immutable; the JVM mutates in place.
    }

    override fun toString(): String {
        val idName = when (id) {
            MOUSE_CLICKED -> "MOUSE_CLICKED"
            MOUSE_PRESSED -> "MOUSE_PRESSED"
            MOUSE_RELEASED -> "MOUSE_RELEASED"
            MOUSE_MOVED -> "MOUSE_MOVED"
            MOUSE_ENTERED -> "MOUSE_ENTERED"
            MOUSE_EXITED -> "MOUSE_EXITED"
            MOUSE_DRAGGED -> "MOUSE_DRAGGED"
            MOUSE_WHEEL -> "MOUSE_WHEEL"
            else -> "unknown type"
        }
        return "java.awt.event.MouseEvent[$idName,($x,$y),absolute($xAbs,$yAbs),button=$button,clickCount=$clickCount] on $source"
    }

    public companion object {
        public const val MOUSE_FIRST: Int = 500
        public const val MOUSE_LAST: Int = 507
        public const val MOUSE_CLICKED: Int = 500
        public const val MOUSE_PRESSED: Int = 501
        public const val MOUSE_RELEASED: Int = 502
        public const val MOUSE_MOVED: Int = 503
        public const val MOUSE_ENTERED: Int = 504
        public const val MOUSE_EXITED: Int = 505
        public const val MOUSE_DRAGGED: Int = 506
        public const val MOUSE_WHEEL: Int = 507
        public const val NOBUTTON: Int = 0
        public const val BUTTON1: Int = 1
        public const val BUTTON2: Int = 2
        public const val BUTTON3: Int = 3
    }
}

/** `java.awt.event.MouseWheelEvent`. */
public open class MouseWheelEvent(
    source: Component,
    id: Int,
    `when`: Long,
    modifiers: Int,
    x: Int,
    y: Int,
    clickCount: Int,
    popupTrigger: Boolean,
    public val scrollType: Int,
    public val scrollAmount: Int,
    public val wheelRotation: Int
) : MouseEvent(source, id, `when`, modifiers, x, y, clickCount, popupTrigger, MouseEvent.NOBUTTON) {

    public companion object {
        public const val WHEEL_UNIT_SCROLL: Int = 0
        public const val WHEEL_BLOCK_SCROLL: Int = 1
    }
}

/** `java.awt.event.KeyEvent`. */
public open class KeyEvent(
    source: Component,
    id: Int,
    `when`: Long,
    modifiers: Int,
    public val keyCode: Int,
    public val keyChar: Char
) : InputEvent(source, id, `when`, modifiers) {

    public companion object {
        public const val KEY_FIRST: Int = 400
        public const val KEY_LAST: Int = 402
        public const val KEY_TYPED: Int = 400
        public const val KEY_PRESSED: Int = 401
        public const val KEY_RELEASED: Int = 402
        public const val VK_ENTER: Int = 10
        public const val VK_BACK_SPACE: Int = 8
        public const val VK_TAB: Int = 9
        public const val VK_CANCEL: Int = 3
        public const val VK_ESCAPE: Int = 27
        public const val VK_SPACE: Int = 32
        public const val VK_DELETE: Int = 127
        public const val VK_LEFT: Int = 37
        public const val VK_UP: Int = 38
        public const val VK_RIGHT: Int = 39
        public const val VK_DOWN: Int = 40
        public const val VK_SHIFT: Int = 16
        public const val VK_CONTROL: Int = 17
        public const val VK_ALT: Int = 18
        public const val VK_A: Int = 65
        public const val VK_B: Int = 66
        public const val VK_C: Int = 67
        public const val VK_D: Int = 68
        public const val VK_E: Int = 69
        public const val VK_F: Int = 70
        public const val VK_G: Int = 71
        public const val VK_H: Int = 72
        public const val VK_I: Int = 73
        public const val VK_J: Int = 74
        public const val VK_K: Int = 75
        public const val VK_L: Int = 76
        public const val VK_M: Int = 77
        public const val VK_N: Int = 78
        public const val VK_O: Int = 79
        public const val VK_P: Int = 80
        public const val VK_Q: Int = 81
        public const val VK_R: Int = 82
        public const val VK_S: Int = 83
        public const val VK_T: Int = 84
        public const val VK_U: Int = 85
        public const val VK_V: Int = 86
        public const val VK_W: Int = 87
        public const val VK_X: Int = 88
        public const val VK_Y: Int = 89
        public const val VK_Z: Int = 90
        public const val VK_0: Int = 48
        public const val VK_1: Int = 49
        public const val VK_2: Int = 50
        public const val VK_3: Int = 51
        public const val VK_4: Int = 52
        public const val VK_5: Int = 53
        public const val VK_6: Int = 54
        public const val VK_7: Int = 55
        public const val VK_8: Int = 56
        public const val VK_9: Int = 57
        public const val CHAR_UNDEFINED: Char = '\uFFFF'
    }
}

/** `java.awt.event.ActionEvent`. */
public open class ActionEvent(
    source: Any,
    id: Int,
    public val actionCommand: String?
) : AWTEvent(source, id) {

    public companion object {
        public const val ACTION_FIRST: Int = 1001
        public const val ACTION_LAST: Int = 1001
        public const val ACTION_PERFORMED: Int = 1001
        public const val SHIFT_MASK: Int = 1
        public const val CTRL_MASK: Int = 2
        public const val META_MASK: Int = 4
        public const val ALT_MASK: Int = 8
    }
}

/** `java.awt.event.WindowEvent`. */
public open class WindowEvent(source: Component, id: Int) : ComponentEvent(source, id) {
    public fun getWindow(): java.awt.Window = source as java.awt.Window

    public companion object {
        public const val WINDOW_FIRST: Int = 200
        public const val WINDOW_LAST: Int = 205
        public const val WINDOW_OPENED: Int = 200
        public const val WINDOW_CLOSING: Int = 201
        public const val WINDOW_CLOSED: Int = 202
        public const val WINDOW_ICONIFIED: Int = 203
        public const val WINDOW_DEICONIFIED: Int = 204
        public const val WINDOW_ACTIVATED: Int = 205
    }
}

// ---- Listener interfaces --------------------------------------------------

/** `java.awt.event.MouseListener`. */
public interface MouseListener : EventListener {
    public fun mouseClicked(e: MouseEvent)
    public fun mousePressed(e: MouseEvent)
    public fun mouseReleased(e: MouseEvent)
    public fun mouseEntered(e: MouseEvent)
    public fun mouseExited(e: MouseEvent)
}

/** `java.awt.event.MouseMotionListener`. */
public interface MouseMotionListener : EventListener {
    public fun mouseDragged(e: MouseEvent)
    public fun mouseMoved(e: MouseEvent)
}

/** `java.awt.event.MouseWheelListener`. */
public interface MouseWheelListener : EventListener {
    public fun mouseWheelMoved(e: MouseWheelEvent)
}

/** `java.awt.event.KeyListener`. */
public interface KeyListener : EventListener {
    public fun keyTyped(e: KeyEvent)
    public fun keyPressed(e: KeyEvent)
    public fun keyReleased(e: KeyEvent)
}

/** `java.awt.event.FocusListener`. */
public interface FocusListener : EventListener {
    public fun focusGained(e: FocusEvent)
    public fun focusLost(e: FocusEvent)
}

/** `java.awt.event.ActionListener`. */
public interface ActionListener : EventListener {
    public fun actionPerformed(e: ActionEvent)
}

/** `java.awt.event.WindowListener`. */
public interface WindowListener : EventListener {
    public fun windowOpened(e: WindowEvent)
    public fun windowClosing(e: WindowEvent)
    public fun windowClosed(e: WindowEvent)
    public fun windowIconified(e: WindowEvent)
    public fun windowDeiconified(e: WindowEvent)
    public fun windowActivated(e: WindowEvent)
    public fun windowDeactivated(e: WindowEvent)
}

/** `java.awt.event.ComponentListener`. */
public interface ComponentListener : EventListener {
    public fun componentResized(e: ComponentEvent)
    public fun componentMoved(e: ComponentEvent)
    public fun componentShown(e: ComponentEvent)
    public fun componentHidden(e: ComponentEvent)
}

// ---- Adapter classes ------------------------------------------------------

/** `java.awt.event.MouseAdapter` — empty implementations of the three mouse
 * listener interfaces. */
public abstract class MouseAdapter : MouseListener, MouseMotionListener, MouseWheelListener {
    override fun mouseClicked(e: MouseEvent) = Unit
    override fun mousePressed(e: MouseEvent) = Unit
    override fun mouseReleased(e: MouseEvent) = Unit
    override fun mouseEntered(e: MouseEvent) = Unit
    override fun mouseExited(e: MouseEvent) = Unit
    override fun mouseDragged(e: MouseEvent) = Unit
    override fun mouseMoved(e: MouseEvent) = Unit
    override fun mouseWheelMoved(e: MouseWheelEvent) = Unit
}

/** `java.awt.event.MouseMotionAdapter` — empty mouse-motion implementation. */
public abstract class MouseMotionAdapter : MouseMotionListener {
    override fun mouseDragged(e: MouseEvent) = Unit
    override fun mouseMoved(e: MouseEvent) = Unit
}

/** `java.awt.event.KeyAdapter`. */
public abstract class KeyAdapter : KeyListener {
    override fun keyTyped(e: KeyEvent) = Unit
    override fun keyPressed(e: KeyEvent) = Unit
    override fun keyReleased(e: KeyEvent) = Unit
}

/** `java.awt.event.WindowAdapter`. */
public abstract class WindowAdapter : WindowListener {
    override fun windowOpened(e: WindowEvent) = Unit
    override fun windowClosing(e: WindowEvent) = Unit
    override fun windowClosed(e: WindowEvent) = Unit
    override fun windowIconified(e: WindowEvent) = Unit
    override fun windowDeiconified(e: WindowEvent) = Unit
    override fun windowActivated(e: WindowEvent) = Unit
    override fun windowDeactivated(e: WindowEvent) = Unit
}

/** `java.awt.event.FocusAdapter`. */
public abstract class FocusAdapter : FocusListener {
    override fun focusGained(e: FocusEvent) = Unit
    override fun focusLost(e: FocusEvent) = Unit
}

/** `java.awt.event.ComponentAdapter`. */
public abstract class ComponentAdapter : ComponentListener {
    override fun componentResized(e: ComponentEvent) = Unit
    override fun componentMoved(e: ComponentEvent) = Unit
    override fun componentShown(e: ComponentEvent) = Unit
    override fun componentHidden(e: ComponentEvent) = Unit
}
