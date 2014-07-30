module FixedWidth
  class Definition
    attr_reader :options

    def initialize(options={})
      @parts = { section: {}, template: {} }
      @options = {
        align: :right,
        parse: :in_order
      }.merge(options)
    end

    [:section, :template].each do |type|
      define_method(type) do |name, options={}, &block|
        add_part(type, name, options, &block)
      end
      define_method("#{type}s".to_sym) do |*keys|
        return @parts[type].values if keys.blank?
        keys.map{ |key| @parts[type][key] }
      end
    end

    def method_missing(method, *args, &block)
      section(method, *args, &block)
    end

    private

    def add_part(type, name, options, &block)
      raise FixedWidth::DuplicateNameError.new %{
        Definition has duplicate #{type} with name '#{name}'
      }.squish if @parts[type][name]
      part = FixedWidth::Section.new(name, @options.merge(options))
      part.definition = self
      yield(part)
      @parts[type][name] = part
    end

  end
end
