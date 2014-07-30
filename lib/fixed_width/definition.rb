module FixedWidth
  class Definition
    include Options

    options(
      parse: { default: :in_order, validate: FixedWidth::Parser::ParseTypes }
    )
    opt_settings( :reader => :parse )

    def initialize(opts={})
      initialize_options(opts)
    end

    [:section, :template].each do |type|
      define_method(type) do |name, opts={}, &block|
        add_part(type, name, opts, &block)
      end
      define_method("#{type}s".to_sym) do |*keys|
        return parts[type].values if keys.blank?
        keys.map{ |key| parts[type][key] }
      end
    end

    def method_missing(method, *args, &block)
      section(method, *args, &block)
    end

    private

    def add_part(type, name, opts, &block)
      raise FixedWidth::DuplicateNameError.new %{
        Definition has duplicate #{type} with name '#{name}'
      }.squish if parts[type][name]
      opts = opts.merge(name: name, definition: self)
      part = FixedWidth::Section.new(name, opts)
      yield(part)
      parts[type][name] = part
    end

    def parts
      @parts ||= { section: {}, template: {} }
    end

  end
end
