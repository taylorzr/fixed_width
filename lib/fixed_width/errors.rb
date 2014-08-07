module FixedWidth
  class BaseError < StandardError; end
  class SchemaError < BaseError; end
  class ParseError < BaseError; end
  class DuplicateNameError < BaseError; end
  class ConfigError < BaseError; end
  class RequiredSectionNotFoundError < BaseError; end
  class RequiredSectionEmptyError < BaseError; end
  class FormatError < BaseError; end
  class SectionsNotSameLengthError < StandardError; end
  class UnusedLineError < BaseError; end
end
