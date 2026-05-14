import _BenchmarkSyntaxDiscoveryCore

@main
struct BenchmarkSyntaxDiscoveryTool {
  static func main() {
    BenchmarkSyntaxDiscoveryToolDriver.run(
      arguments: Array(CommandLine.arguments.dropFirst())
    )
  }
}
