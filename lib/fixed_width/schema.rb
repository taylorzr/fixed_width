module FixedWidth
  class Schema
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

#######################################################

    RESERVED_NAMES = [:spacer].freeze

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
        field = check_duplicates(child)
      else # existing schema
        field = check_duplicates(opts)
      end
      (fields << field)[-1]
    end

    def column(name, length, opts={})
      # Construct column
      col = Column.new(opts.merge(name: name, length: length, parent: self))
      # Check name
      raise ConfigError.new %{
        Invalid Name: '#{col.name}' is a reserved keyword!
      }.squish if RESERVED_NAMES.include?(col.name)
      # Add the new column
      (fields << check_duplicates(col))[-1]
    end

    def spacer(length, pad=nil)
      opts = { name: :spacer, length: length, parent: self }
      opts[:padding] = pad if pad
      col = Column.new(opts)
      (fields << col)[-1]
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
    rescue => e
      raise unless e.is_a?(ArgumentError)
      b = [block_given?, block.try(:source_location)]
      raise SchemaError, [method, args, b, e.inspect].inspect
    end

    # Data methods

    def length
      @length = nil if @fields_hash != fields.hash
      @length ||= begin
        @fields_hash = fields.hash
        fields.map { |f|
          f, _ = lookup_hash(f,raiser) if f.is_a?(Hash)
          f.length
        }.reduce(0,:+)
      end
    end

    def schemas
      fields.enum_for(:grep, Schema)
    end

    def columns
      fields.enum_for(:grep, Column)
    end

    def imported_schemas
      return enum_for(:imported_schemas) unless block_given?
      fields.each do |field|
        if field.is_a?(Hash) && names = hash_to_name_list(field)
          yield names
        end
      end
    end

    def valid?
      errors.empty?
    end

    # Parsing methods

    def match(raw_line)
      raw_line.nil? ? false :
        raw_line.length == self.length &&
          (!trap || trap.call(raw_line))
    end

    def parse(line, start_pos = 0)
      # need to update to use groups
      data = {}
      cursor = start_pos
      fields.each do |f|
        case f
        when Column
          unless f.name == :spacer
            capture = line.mb_chars[cursor..cursor+f.length-1] || ''
            data[f.name] = f.parse(capture, self)
          end
          cursor += f.length
        when Schema
          data[f.name] = f.parse(line, cursor)
          cursor += f.length
        when Hash
          schema, store_name = lookup_hash(f,raiser)
          data[store_name] = schema.parse(line, cursor)
          cursor += schema.length
        else
          raise SchemaError, field_type_error(f)
        end
      end
      data
    end

    def format(data)
      # need to update to use groups
      fields.map do |f|
        if f.is_a?(Hash)
          s, sn = lookup_hash(f,raiser)
          s.format(data[sn])
        else
          f.format(data[f.name])
        end
      end.join
    end

    protected

    def fields
      @fields ||= []
    end

    def errors
      fields.reduce([]) { |errs, field|
        errs + case field
        when Hash
          lookup_hash(field, hash_err = [])
          hash_err
        when Column then []
        when Schema then field.errors
        else [field_type_error(field)]
        end
      }
    end

    def lookup(schema_name, sval = nil)
      @lookup ||= {}
      @lookup[schema_name] ||= case
        when sval.is_a?(Schema) then sval
        when parent.is_a?(Schema)
          pass_options(parent.lookup(schema_name))
        when parent.respond_to?(:schemas)
          pass_options(parent.schemas(schema_name).first)
        else nil
      end
    end

    private

    def lookup_hash(h, err = nil)
      store_name, schema_name = hash_to_name_list(h)
      unless schema_name
        err << "Missing schema name: #{h.inspect}" if err
        return nil
      end
      unless schema = lookup(schema_name)
        err << "Cannot find schema named `#{schema_name.inspect}`" if err
        return nil
      end
      return schema, store_name
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
            names = case
            when !opts.key?(:name)
              {name: name.to_sym}
            when !opts.key?(:schema_name)
              {schema_name: name.to_sym}
            else nil
            end
            return opts.merge(names) if names
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

    def pass_options(schema)
      if schema
        merge_ops = {prefer: :self, missing: :undefined}
        schema.columns.each do |col|
          col.options.merge!(self.options, merge_ops)
        end
      end
      schema
    end

    def check_duplicates(field)
      field_name = field.is_a?(Hash) ?
        hash_to_name_list(field).try(:first) : field.name
      raise SchemaError.new %{
        Field has no name: #{field.inspect}
      }.squish unless field_name
      field_types = [
        [schemas, :name, "a schema"],
        [columns, :name, "a column"],
        [imported_schemas, :first, "an imported schema"]
      ]
      field_types.each do |(list,nm,type)|
        raise DuplicateNameError.new %{
          You already have #{type} named '#{field_name}'
        }.squish if list.find{ |x| field_name == x.send(nm) }
      end
      if field.is_a?(Schema)
        from_lookup = lookup(field.name, field)
        raise DuplicateNameError.new %{
          An imported schema of type #{from_lookup.name}
          conflicts with the new schema: old =
          #{from_lookup.inspect}, new = #{field.inspect}
        }.squish if from_lookup != field
      end
      field
    end

    def field_type_error(f)
      "Unknown field type: #{f.inspect}"
    end

    def hash_to_name_list(field)
      schema_name = field[:schema_name] || field[:name]
      store_name = field[:name] || schema_name
      return nil unless store_name && schema_name
      [store_name, schema_name]
    end

    def raiser
      @raiser ||= Class.new do
        def <<(msg)
          raise SchemaError, msg
        end
      end.new
    end

  end
end
