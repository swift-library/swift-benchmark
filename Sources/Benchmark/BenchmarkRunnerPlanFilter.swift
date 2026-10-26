// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation

extension BenchmarkRunner.Plan {
  public struct Filter: Sendable, Equatable {
    public var suiteName: String?
    public var caseName: String?
    public var suitePattern: String?
    public var casePattern: String?
    public var tags: [String]

    public init(
      suiteName: String? = nil,
      caseName: String? = nil,
      suitePattern: String? = nil,
      casePattern: String? = nil,
      tags: [String] = []
    ) {
      self.suiteName = suiteName
      self.caseName = caseName
      self.suitePattern = suitePattern
      self.casePattern = casePattern
      self.tags = tags
    }

    public static var all: Filter {
      Filter()
    }

    public func matchesSuite(_ name: String) -> Bool {
      matches(name: name, exact: suiteName, pattern: suitePattern)
    }

    public func matchesCase(_ name: String) -> Bool {
      matches(name: name, exact: caseName, pattern: casePattern)
    }

    public func matchesTags(_ candidateTags: [String]) -> Bool {
      tags.allSatisfy { candidateTags.contains($0) }
    }

    private func matches(name: String, exact: String?, pattern: String?) -> Bool {
      if let exact, exact != name {
        return false
      }
      if let pattern, !Self.matchesPattern(pattern, name: name) {
        return false
      }
      return true
    }

    private static func matchesPattern(_ pattern: String, name: String) -> Bool {
      guard pattern.contains("*") else {
        return name.contains(pattern)
      }
      let parts = pattern.split(separator: "*", omittingEmptySubsequences: false).map(String.init)
      var remainder = name[...]
      for (index, part) in parts.enumerated() where !part.isEmpty {
        guard let range = remainder.range(of: part) else {
          return false
        }
        if index == 0, !pattern.hasPrefix("*"), range.lowerBound != remainder.startIndex {
          return false
        }
        remainder = remainder[range.upperBound...]
      }
      if let last = parts.last, !last.isEmpty, !pattern.hasSuffix("*") {
        return name.hasSuffix(last)
      }
      return true
    }
  }
}
