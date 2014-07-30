module FixedWidth
  class Column
    include Options

    options(
      name: { transform: :to_sym, validate: blank },
      length: { transform: to_int },
      parser: { transform: nil_or_proc },
      formatter: { default: :to_s, transform: nil_or_proc },
      padding: { default: ' ', validate: String },
      truncate: { default: false, validate: [true, false] },
      nil_blank: { default: false, validate: [true, false] },
      align: { default: :right, validate: [nil, :left, :right, :none] }
      group: {}
    )
    opt_settings(
      required: [:name, :length],
      reader: [:name, :length, :align, :padding, :truncate, :group]
    )

    def initialize(opts)
      initialize_options(opts)
    end

    def parse(value, section)
      return nil if opt(:nil_blank) && value.blank?
      aligned = case align
      when :right then value.lstrip
      when :left then value.rstrip
      else value
      end
      return opt(:parser).call(aligned) if opt(:parser)
      aligned
    rescue
      raise FixedWidth::ParseError.new %{
        #{section.name}::#{name}:
        The value '#{value}' could not be parsed: #{$!}
      }.squish
    end

    def format(value)
      formatted = opt(:formatter).call(value)
      validate_size(pad(formatted))
    end

    private

    def pad(value)
      case align
      when :left
        value.ljust(length, padding)
      when :right
        value.rjust(length, padding)
      else
        value
      end
    end

    def validate_size(result)
      if truncate && result.length > length
        result = case align
        when :right then result[-length,length]
        when :left  then result[0,length]
        else result
        end
      end
      raise FixedWidth::FormatError.new %{
        The formatted value '#{result}' in column '#{name}'
        with padding '#{align.inspect}' is too
        #{result.length > length ? 'long' : 'short'}:
        got #{result.length} chararacters, expected #{length}.
      }.squish if result.length != length
      result
    end

  end
end
