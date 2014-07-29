module FixedWidth
  class Column

    DEFAULT_OPTIONS = {
      alignment: :right,
      padding: ' ',
      truncate: false,
      formatter: :to_s,
      nil_blank: false,
      parser: nil,
      group: nil
    }.freeze

    attr_reader :name, :length

    [:alignment, :padding, :truncate, :group].each do |m|
      define_method(m) { opt(m) }
    end

    def initialize(name, length, options={})
      @options = assert_valid_options(options)
      @name    = name
      @length  = length
    end

    def parse(value, section)
      return nil if opt(:nil_blank) && value.blank?
      return opt(:parser).call(value) if opt(:parser)
      case alignment
      when :right
        value.lstrip
      when :left
        value.rstrip
      end
    rescue
      raise FixedWidth::ParseError.new %{
        #{section.name}::#{name}:
        The value '#{value}' could not be parsed:
        #{$!}
      }.squish
    end

    def format(value)
      pad(
        validate_size(
          opt(:formatter).call(value)
        )
      )
    end

    def opt(key)
      @options[key]
    end

    private

    def pad(value)
      case alignment
      when :left
        value.ljust(length, padding)
      when :right
        value.rjust(length, padding)
      end
    end

    def assert_valid_options(options)
      opts = DEFAULT_OPTIONS.merge(options)
      unless [nil, :left, :right].include?(opts[:align])
        raise ArgumentError.new("Option :align only accepts :right (default) or :left")
      end
      [:parser, :formatter].each do |pkey|
        opts[pkey] = opts[pkey].to_proc if opts[pkey].respond_to?(:to_proc)
      end
      opts
    end

    def validate_size(result)
      return result if result.length <= length
      raise FixedWidth::FormattedStringExceedsLengthError.new %{
        The formatted value '#{result}' in column '#{name}'
        exceeds the allowed length of #{length} chararacters.
      }.squish unless truncate
      case alignment
      when :right then result[-length,length]
      when :left  then result[0,length]
      end
    end

  end
end
