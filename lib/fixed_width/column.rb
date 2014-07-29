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
      aligned = case alignment
      when :right then value.lstrip
      when :left then value.rstrip
      else value
      end
      return opt(:parser).call(aligned) if opt(:parser)
      aligned
    rescue
      raise FixedWidth::ParseError.new %{
        #{section.name}::#{name}:
        The value '#{value}' could not be parsed:
        #{$!}
      }.squish
    end

    def format(value)
      formatted = opt(:formatter).call(value)
      validate_size(pad(formatted))
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
      else
        value
      end
    end

    def assert_valid_options(options)
      opts = DEFAULT_OPTIONS.merge(options)
      unless [nil, :left, :right, :none].include?(opts[:align])
        raise ArgumentError.new("Option :align only accepts :right, :left, or :none")
      end
      [:parser, :formatter].each do |pkey|
        opts[pkey] = opts[pkey].to_proc if opts[pkey].respond_to?(:to_proc)
      end
      opts
    end

    def validate_size(result)
      if truncate && result.length > length
        result = case alignment
        when :right then result[-length,length]
        when :left  then result[0,length]
        else result
        end
      end
      raise FixedWidth::FormatError.new %{
        The formatted value '#{result}' in column '#{name}'
        with padding '#{alignment.inspect}' is too
        #{result.length > length ? 'long' : 'short'}:
        got #{result.length} chararacters, expected #{length}.
      }.squish if result.length != length
      result
    end

  end
end
