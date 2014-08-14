module FixedWidth
  class Section
    include Config::API

    options.define(
      ordered: { validate: [true, false] },
      repeat: { validate: [true, false] },
      optional: { default: false, validate: [true, false] },
      singular: { default: true, validate: [true, false] }
    )
    options.configure(
      required: [:ordered, :repeat],
      reader: [:ordered, :repeat, :optional, :singular],
      writer: [:ordered, :repeat, :optional, :singular]
    )

    def initialize(opts)
      initialize_options(opts)
      @in_setup = false
    end

    def add_schema(schema, opts = {})
      raise SectionError.new %{
        Cannot add `#{schema.inspect}` to section!
      }.squish unless schema.respond_to?(:to_sym)
      raise SectionError.new %{
        Invalid options hash: #{opts.inspect}
      }.squish unless opts.is_a?(Hash)
      list << [schema.to_sym, opts]
      self
    end

    def repeat(opts = {}, &blk)
      dsl_subsection('repeat', opts.merge(repeat: true), &blk)
    end

    def section(opts = {}, &blk)
      dsl_subsection('section', {repeat: false}.merge(opts), &blk)
    end

    def setup(&block)
      raiser << "already in #setup; recursion forbidden" if @in_setup
      raiser << "#setup requires a block!" unless block_given?
      @in_setup = true
      instance_eval(&block)
    ensure
      @in_setup = false
    end

    def respond_to_missing?(method, *)
      @in_setup || super
    end

    def method_missing(method, *args)
      return super unless @in_setup
      raiser << %{unexpected block while dispatching '#{method}'
                  in #method_missing}.squish if block_given?
      add_schema(method, *args)
    end

    def valid?(definition)
      schema_enum(definition).all? { |x| x.first.is_a?(Schema) }
    end

    def validate!(definition)
      bad = schema_enum(definition).map(&:first).reject { |x| x.is_a?(Schema) }
      raise SectionError.new %{
        Can not find the following schemas: #{bad.inspect}
      }.squish unless bad.empty?
    end

    def enum(definition)
      return enum_for(:enum, definition) unless block_given?
      list.each do |item|
        if item.is_a?(Section)
          yield item
        elsif item.is_a?(Array)
          schema = definition.schemas(item.first).first
          yield [schema || item.first] + item[1..-1]
        else
          raise SectionError, "Unknown section type: #{item.inspect}"
        end
      end
    end

    def schema_names
      list.map{ |x| x.is_a?(Section) ? x.schema_names : x.first }
    end

    def repeat?
      opt(:repeat)
    end

    protected

    def schema_enum(definition, &blk)
      return enum_for(:schema_enum, definition) unless block_given?
      enum(definition).each do |item|
        if item.is_a?(Section)
          item.schema_enum(definition, &blk)
        else
          yield item
        end
      end
    end

    private

    def list
      @list ||= []
    end

    def raiser
      @raiser ||= Class.new do
        def <<(msg)
          raise SectionError, msg
        end
      end.new
    end

    def dsl_subsection(mn, more_opts, &blk)
      raiser << "cannot call ##{mn} outside of #setup" unless @in_setup
      raiser << "##{mn} requires a block!" unless block_given?
      to_init = options.to_hash.merge(more_opts)
      new_section = self.class.new(to_init)
      new_section.setup(&blk)
      list << new_section
      self
    end

  end
end
