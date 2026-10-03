// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import _BenchmarkSyntaxDiscoveryCore

@main
struct BenchmarkSyntaxDiscoveryTool {
  static func main() {
    BenchmarkSyntaxDiscoveryToolDriver.run(
      arguments: Array(CommandLine.arguments.dropFirst())
    )
  }
}
