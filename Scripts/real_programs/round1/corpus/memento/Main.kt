import design_patterns.*
fun main() {
    val view = TextView()
    view.setText("hello")
    val saved = view.onSaveInstanceState()
    view.setText("changed")
    view.onRestoreInstanceState(saved)
    view.draw()
}
