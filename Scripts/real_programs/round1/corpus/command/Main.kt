import design_patterns.*
fun main() {
    val stereo = StereoSystem()
    val command = MacroCommand(TurnOnCommand(stereo), IncreaseVolumeCommand(stereo))
    command.execute()
    println(stereo.currentState)
    println(command.undo())
    println(stereo.currentState)
}
