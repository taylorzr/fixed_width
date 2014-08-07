module FixedWidth
  class Section
    include Config::API

    options.define(
      name: { transform: :to_sym, validate: :blank },
      optional: { default: false, validate: [true, false] },
      singular: { default: false, validate: [true, false] },
      parent: { validate: Config::API },
      trap: { transform: :nil_or_proc }
    )
    options.configure(
      required: [:name, :parent],
      reader: [:name, :parent, :optional, :singular],
      writer: [:optional, :singular]
    )

    RESERVED_NAMES = [:spacer, :template, :section].freeze


    def template(name)
      template = definition.templates(name).first
      raise FixedWidth::ConfigError.new %{
        Template '#{name}' not found as a known template.
      }.squish unless template
      template.columns.each do |col|
        col.options.merge!(self.options, prefer: :self, missing: :undefined)
        unless RESERVED_NAMES.include?(col.name)
          gn = check_duplicates(col.group, col.name)
          group(gn) << col.name
        end
        columns << col
      end
      template
    end

    def format(data)
      columns.map do |c|
        hash = c.group ? data[c.group] : data
        c.format(hash[c.name])
      end.join
    end

    def parse(line)
      data = groups.reduce({}) { |acc, (name,cols)|
        acc[name] = {} if name
        acc
      }
      cursor = 0
      columns.each do |c|
        unless c.name == :spacer
          store = c.group ? data[c.group] : data
          capture = line.mb_chars[cursor..cursor+c.length-1] || ''
          store[c.name] = c.parse(capture, self)
        end
        cursor += c.length
      end
      data
    end

    def match(raw_line)
      raw_line.nil? ? false :
        raw_line.length == self.length &&
          (!trap || trap.call(raw_line))
    end

    # protected
    def groups
      @groups ||= {}
    end

    def group(name = nil)
      groups[name] ||= Set.new
    end

    #private
    def check_duplicates(gn, name)
      gns = gn ? "'#{gn}'" : "default"
      raise FixedWidth::DuplicateNameError.new %{
        You have already defined a column named
        '#{name}' in the #{gns} group.
      }.squish if group(gn).include?(name)
      raise FixedWidth::DuplicateNameError.new %{
        You have already defined a column named #{gns};
        you cannot have a group and column of the same name.
      }.squish if group(nil).include?(gn)
      raise FixedWidth::DuplicateNameError.new %{
        You have already defined a group named '#{name}';
        you cannot have a group and column of the same name.
      }.squish if groups.key?(name)
      gn
    end


#######################################################


    def initialize(opts)
      initialize_options(opts)
      initialize_options(parent.options)
      @in_setup = false
    end

    # DSL methods

    def schema(*args, &block)
      opts = validate_schema_func_args(args, block_given?)
      if block_given? # new sub-schema
        child = Schema.new(opts.merge(parent: self))
        child.setup(&block)
        fields << child
      else # existing schema
        fields << opts # do the lookup lazily
      end
    end

    def column(name, length, opts={})
      # Construct column
      col = make_column(opts.merge(name: name, length: length))
      # Check name
      raise ConfigError.new %{
        Invalid Name: '#{col.name}' is a reserved keyword!
      }.squish if RESERVED_NAMES.include?(col.name)
      # Check for duplicates
      gn = check_duplicates(col.group, col.name)
      # Add the new column
      fields << col
      group(gn) << col.name
      col
    end

    def spacer(length, pad=nil)
      opts = { name: :spacer, length: length }
      opts[:padding] = pad if pad
      col = make_column(opts)
      fields << col
      col
    end

    def trap(&block)
      set_opt(:trap, block) if block_given?
      opt(:trap)
    end

    def setup(&block)
      raise SchemaError, "already in #setup; recursion forbidden" if @in_setup
      raise SchemaError, "#setup requires a block!" unless block_given?
      @in_setup = true
      instance_eval(&block)
    ensure
      @in_setup = false
    end

    def respond_to_missing?(method, *)
      @in_setup || super
    end

    def method_missing(method, *args, &block)
      return super unless @in_setup
      return schema(method, *args, &block) if block_given?
      column(method, *args)
    end

    # Data methods

    def length
      @length = nil if @fields_hash != fields.hash
      @length ||= begin
        @fields_hash = fields.hash
        fields.map(&:length).reduce(0,:+)
      end
    end

    def export
      fields.enum_for(:grep, Schema)
    end

    # Parsing methods

    protected

    def fields
      @fields ||= []
    end

    private

    def make_column(*args)
      col = Column.new(*args)
      col.options.merge!(self.options, prefer: :self, missing: :undefined)
      col
    end

    def validate_schema_func_args(args, has_block)
      case args.count
      when 1
        arg = args.first
        return {name: arg.to_sym} if arg.respond_to?(:to_sym)
        if arg.is_a?(Hash)
          return arg if arg.key?(:name) || arg.key?(:schema_name)
          if !has_block && arg.count == 1
            list = [arg.keys.first, {schema_name: arg.values.first}]
            return validate_schema_func_args(list, has_block)
          end
        end
      when 2
        name, opts = args
        if name.respond_to?(:to_sym)
          if opts.is_a?(Hash)
            if !opts.key?(:name) || !opts.key?(:schema_name)
              names = {name: name.to_sym}
              names[:schema_name] = opts[:name] if opts.key?(:name)
              return opts.merge(names)
            end
          end
        end
      end
      expected = "[name, options = {}]"
      expected += " OR [{name: schema_name}]" unless has_block
      raise SchemaError.new %{
        Unexpected arguments for #schema. Expected #{expected}.
        Got #{args.inspect}#{" and a block" if has_block}
      }.squish
    end

  end
end
