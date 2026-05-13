public struct SpanAttributes: Sendable, Equatable, ExpressibleByDictionaryLiteral {
  public typealias Key = String
  public typealias Value = SpanAttributeValue

  public static let empty = SpanAttributes()

  public var values: [Key: Value]

  public init() {
    self.values = [:]
  }

  public init(_ values: [Key: Value]) {
    self.values = values
  }

  public init(dictionaryLiteral elements: (Key, Value)...) {
    self.values = Dictionary(uniqueKeysWithValues: elements)
  }
}

public enum SpanAttributeValue: Sendable, Equatable, ExpressibleByStringLiteral,
  ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral
{
  case string(String)
  case int(Int)
  case double(Double)
  case bool(Bool)

  public init(stringLiteral value: String) {
    self = .string(value)
  }

  public init(integerLiteral value: Int) {
    self = .int(value)
  }

  public init(floatLiteral value: Double) {
    self = .double(value)
  }

  public init(booleanLiteral value: Bool) {
    self = .bool(value)
  }
}
