import design_patterns.*
fun main() {
    val printer: MyPrinter = ExclamationPrinter(WorldPrinter(SpacePrinter(CommaPrinter(HelloPrinter()))))
    println(printer.printedText())
}
