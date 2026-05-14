import _BenchmarkDiscoveryCore
import Foundation

@main
struct BenchmarkDiscoveryTool {
  static func main() {
    BenchmarkDiscoveryToolDriver.run(
      arguments: Array(CommandLine.arguments.dropFirst())
    )
  }
}
