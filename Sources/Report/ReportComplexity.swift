// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation

extension Report {
  /// The growth model that best fits a Dimension curve: how the metric grows
  /// with the size.
  ///
  /// Each model is fitted by least squares as `value ≈ coefficient × f(size)`,
  /// and the model with the smallest ``normalizedRMS`` wins. A fit needs at
  /// least three sizes; sizes chosen across orders of magnitude separate the
  /// models best.
  public struct Complexity: Sendable, Equatable, Codable {
    /// A growth model.
    public enum Model: String, Sendable, Codable, CaseIterable {
      /// O(1).
      case constant
      /// O(log n).
      case logarithmic
      /// O(n).
      case linear
      /// O(n log n).
      case linearithmic
      /// O(n²).
      case quadratic
      /// O(n³).
      case cubic

      /// The model in big-O notation, such as `O(n log n)`.
      public var notation: String {
        switch self {
        case .constant: "O(1)"
        case .logarithmic: "O(log n)"
        case .linear: "O(n)"
        case .linearithmic: "O(n log n)"
        case .quadratic: "O(n²)"
        case .cubic: "O(n³)"
        }
      }

      /// The model's growth function at `size`.
      func callAsFunction(_ size: Double) -> Double {
        switch self {
        case .constant: 1
        case .logarithmic: log2(size)
        case .linear: size
        case .linearithmic: size * log2(size)
        case .quadratic: size * size
        case .cubic: size * size * size
        }
      }
    }

    /// The best-fitting model.
    public var model: Model
    /// The fitted factor of the model's growth function, in the metric's unit.
    public var coefficient: Double
    /// The fit's root-mean-square error divided by the mean value: 0 for a
    /// perfect fit, and larger the worse the model fits.
    public var normalizedRMS: Double

    /// Creates a fit.
    public init(model: Model, coefficient: Double, normalizedRMS: Double) {
      self.model = model
      self.coefficient = coefficient
      self.normalizedRMS = normalizedRMS
    }

    /// The best fit for `points`, or `nil` with fewer than three distinct
    /// sizes or no positive mean value.
    static func fit(_ points: [(size: Double, value: Double)]) -> Complexity? {
      guard Set(points.map(\.size)).count >= 3 else {
        return nil
      }
      let mean = points.map(\.value).reduce(0, +) / Double(points.count)
      guard mean > 0 else {
        return nil
      }
      let fits = Model.allCases.compactMap { model -> Complexity? in
        let growth = points.map { model($0.size) }
        let squaredGrowth = growth.reduce(0) { $0 + $1 * $1 }
        guard squaredGrowth > 0 else {
          return nil
        }
        let coefficient =
          zip(points, growth).reduce(0) { $0 + $1.0.value * $1.1 } / squaredGrowth
        let squaredError = zip(points, growth).reduce(0) { partial, pair in
          let error = pair.0.value - coefficient * pair.1
          return partial + error * error
        }
        let rms = (squaredError / Double(points.count)).squareRoot()
        return Complexity(model: model, coefficient: coefficient, normalizedRMS: rms / mean)
      }
      return fits.min { $0.normalizedRMS < $1.normalizedRMS }
    }
  }
}
