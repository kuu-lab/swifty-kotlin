package javax.swing

import java.awt.Color
import java.awt.Component
import java.awt.Container
import java.awt.Dimension
import java.awt.Font
import java.awt.Frame
import java.awt.Graphics
import java.awt.Point
import java.awt.event.ActionListener
import java.awt.image.BufferedImage

/** `javax.swing.SwingConstants` — shared alignment/direction constants. */
public interface SwingConstants {
    public companion object {
        public const val CENTER: Int = 0
        public const val TOP: Int = 1
        public const val LEFT: Int = 2
        public const val BOTTOM: Int = 3
        public const val RIGHT: Int = 4
        public const val NORTH: Int = 1
        public const val NORTH_EAST: Int = 2
        public const val EAST: Int = 3
        public const val SOUTH_EAST: Int = 4
        public const val SOUTH: Int = 5
        public const val SOUTH_WEST: Int = 6
        public const val WEST: Int = 7
        public const val NORTH_WEST: Int = 8
        public const val HORIZONTAL: Int = 0
        public const val VERTICAL: Int = 1
        public const val LEADING: Int = 10
        public const val TRAILING: Int = 11
        public const val NEXT: Int = 12
        public const val PREVIOUS: Int = 13
    }
}

/** `javax.swing.WindowConstants`. */
public interface WindowConstants {
    public companion object {
        public const val DO_NOTHING_ON_CLOSE: Int = 0
        public const val HIDE_ON_CLOSE: Int = 1
        public const val DISPOSE_ON_CLOSE: Int = 2
        public const val EXIT_ON_CLOSE: Int = 3
    }
}

/** `javax.swing.JComponent` — base for Swing widgets. */
public abstract class JComponent : Container() {
    public var toolTipText: String? = null
    public var border: Any? = null
    public var opaque: Boolean = true

    public open fun paintComponent(g: Graphics) = Unit
    public open fun paintBorder(g: Graphics) = Unit
    public open fun paintChildren(g: Graphics) {
        for (child in components) {
            if (child is JComponent) child.paintComponent(g)
        }
    }

    override fun paint(g: Graphics) {
        paintComponent(g)
        paintBorder(g)
        paintChildren(g)
    }
}

/** `javax.swing.JPanel`. */
public open class JPanel : JComponent() {
    public constructor()
    public constructor(isDoubleBuffered: Boolean) : this()

    override fun toString(): String =
        "javax.swing.JPanel[panel,${getX()},${getY()},${getWidth()}x${getHeight()}]"
}

/** `javax.swing.JLabel`. */
public open class JLabel : JComponent(), SwingConstants {
    public var text: String
    public var icon: Any? = null
    public var horizontalAlignment: Int = SwingConstants.LEADING
    public var verticalAlignment: Int = SwingConstants.CENTER
    public var horizontalTextPosition: Int = SwingConstants.TRAILING
    public var verticalTextPosition: Int = SwingConstants.CENTER

    public constructor() {
        text = ""
    }

    public constructor(text: String?) {
        this.text = text ?: ""
    }

    public constructor(text: String?, horizontalAlignment: Int) {
        this.text = text ?: ""
        this.horizontalAlignment = horizontalAlignment
    }



    override fun toString(): String = "javax.swing.JLabel[label,$text]"
}

/** `javax.swing.JComponent`-derived button with an action listener set. */
public open class AbstractButton : JComponent() {
    public var text: String = ""
    private val actionListeners = mutableListOf<ActionListener>()

    public open fun addActionListener(l: ActionListener) {
        actionListeners.add(l)
    }

    public open fun removeActionListener(l: ActionListener) {
        actionListeners.remove(l)
    }

    public open fun doClick() {
        val event = java.awt.event.ActionEvent(this, java.awt.event.ActionEvent.ACTION_PERFORMED, null)
        for (l in actionListeners.toList()) l.actionPerformed(event)
    }
}

/** `javax.swing.JButton`. */
public open class JButton : AbstractButton {
    public constructor()
    public constructor(text: String?) {
        this.text = text ?: ""
    }

}

/** `javax.swing.JFrame` — top-level Swing window. */
public open class JFrame : Frame, WindowConstants {
    public var defaultCloseOperation: Int = WindowConstants.HIDE_ON_CLOSE
        set(value) {
            if (value < 0 || value > 3) throw IllegalArgumentException("defaultCloseOperation must be one of: DO_NOTHING_ON_CLOSE, HIDE_ON_CLOSE, DISPOSE_ON_CLOSE, or EXIT_ON_CLOSE")
            field = value
        }
    public var contentPane: Container = JPanel()

    public constructor() : super()

    public constructor(title: String?) : super(title)



    public open fun setContentPane(pane: Container) {
        contentPane = pane
    }

    override fun add(comp: Component): Component = contentPane.add(comp)

    public fun setJMenuBar(menuBar: Any?) = Unit

    public fun getLayeredPane(): Container = contentPane
    public fun getGlassPane(): Component = contentPane
    public fun getRootPane(): Component = contentPane

    override fun setVisible(visible: Boolean) {
        if (!visible && defaultCloseOperation == WindowConstants.EXIT_ON_CLOSE && isVisible) {
            super.setVisible(false)
            kotlin.system.exitProcess(0)
        }
        super.setVisible(visible)
    }

    override fun toString(): String =
        "javax.swing.JFrame[frame${hashCode() and 0xffff},${getX()},${getY()},${getWidth()}x${getHeight()},title=$title]"
}

/** `javax.swing.SwingUtilities`. */
public object SwingUtilities {
    /** Runs the runnable immediately — there is no separate event-dispatch
     * thread in the compatibility implementation, so `invokeLater` executes
     * inline and `invokeAndWait` is identical. */
    public fun invokeLater(runnable: Runnable) = runnable.run()

    public fun invokeAndWait(runnable: Runnable) = runnable.run()

    public fun isEventDispatchThread(): Boolean = false

    public fun getWindowAncestor(c: Component?): java.awt.Window? {
        var current = c
        while (current != null) {
            if (current is java.awt.Window) return current
            current = current.parentComponent
        }
        return null
    }

    public fun convertPointToScreen(p: Point, c: Component?) {
        p.translate(c?.getX() ?: 0, c?.getY() ?: 0)
    }

    public fun convertPointFromScreen(p: Point, c: Component?) {
        p.translate(-(c?.getX() ?: 0), -(c?.getY() ?: 0))
    }

    public fun updateComponentTreeUI(c: Component?) = Unit
}

/** `javax.swing.ImageIcon` — wraps an image for labels/buttons. */
public open class ImageIcon {
    public var image: java.awt.Image? = null
    public val iconWidth: Int get() = image?.width ?: -1
    public val iconHeight: Int get() = image?.height ?: -1

    public constructor()
    public constructor(image: java.awt.Image?) {
        this.image = image
    }


}

/** `javax.swing.Timer` — fires an action listener after a delay. The
 * compatibility implementation supports `start`/`stop`/`isRunning` and
 * immediate (non-scheduled) repeats via [doClick]-style invocation. */
public open class Timer(private val delay: Int, private val listener: ActionListener) {
    private var running = false
    private var repeats = true

    public val isRunning: Boolean get() = running
    public val isRepeats: Boolean get() = repeats

    public fun start() {
        running = true
    }

    public fun stop() {
        running = false
    }

    public fun restart() {
        running = true
    }

    public fun setRepeats(repeats: Boolean) {
        this.repeats = repeats
    }


    public fun fireActionPerformed() {
        listener.actionPerformed(java.awt.event.ActionEvent(this, java.awt.event.ActionEvent.ACTION_PERFORMED, null))
    }
}
