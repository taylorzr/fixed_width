module FixedWidth
  class Section
    include Config::API

    options.define(
      name: { transform: :to_sym, validate: :blank },
      optional: { default: false, validate: [true, false] },
      singular: { default: false, validate: [true, false] },
      definition: { validate: FixedWidth::Definition },
      trap: { transform: :nil_or_proc }
    )
    options.configure(
      required: [:name, :definition],
      reader: [:name, :definition, :optional, :singular],
      writer: [:optional, :singular]
    )

    RESERVED_NAMES = [:spacer, :template, :section].freeze

    def initialize(opts)
      initialize_options(opts)
      initialize_options(definition.options)
      @in_setup = false
    end

    def column(name, length, opts={})
      # Construct column
      col = make_column(opts.merge(name: name, length: length))
      # Check name
      raise FixedWidth::ConfigError.new %{
        Invalid Name: '#{col.name}' is a reserved keyword!
      }.squish if RESERVED_NAMES.include?(col.name)
      # Check for duplicates
      gn = check_duplicates(col.group, col.name)
      # Add the new column
      columns << col
      group(gn) << col.name
      col
    end

    def spacer(length, pad=nil)
      opts = { name: :spacer, length: length }
      opts[:padding] = pad if pad
      col = make_column(opts)
      columns << col
      col
    end

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



    # DSL methods

    def schema(*args, &bock)
      #
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
      fields.to_enum
    end

    # Parsing methods

    protected

    def fields
      @fields ||= []
    end

    def groups
      @groups ||= {}
    end

    def group(name = nil)
      groups[name] ||= Set.new
    end

    private

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

    def make_column(*args)
      col = Column.new(*args)
      col.options.merge!(self.options, prefer: :self, missing: :undefined)
      col
    end

  end
end
