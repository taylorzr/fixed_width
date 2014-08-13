module FixedWidth
  class BaseError < StandardError; end
  class ConfigError < BaseError; end
  class SectionError < BaseError; end

  class SchemaError < BaseError; end
  class DuplicateNameError < SchemaError; end

  class ParseError < BaseError; end
  class RequiredSchemaNotFoundError < ParseError; end
  class UnusedInputError < ParseError; end
  class DuplicateDataError < ParseError; end

  class FormatError < BaseError; end
  class RequiredSchemaEmptyError < FormatError; end
end
