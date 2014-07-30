module FixedWidth
  class Section
    include Options

    options(
      name: { transform: :to_sym, validate: blank },
      optional: { default: false, validate: [true, false] },
      singular: { default: false, validate: [true, false] },
      definition: { validate: FixedWidth::Definition },
      trap: { transform: nil_or_proc }
    )
    opt_settings(
      required: [:name, :definition],
      reader: [:name, :definition, :optional, :singular],
      writer: [:optional, :singular]
    )

    RESERVED_NAMES = [:spacer, :template, :section].freeze

    def initialize(opts)
      initialize_options(opts)
    end

    def column(name, length, opts={})
      # Construct column
      col = Column.new opts.merge(name: name, length: length)
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
      col = Column.new(opts)
      columns << col
      col
    end

    def trap(&block)
      set_opt(:trap, block) if block_given?
      opt(:trap)
    end

    def template(name)
      template = definition.templates(name).first
      raise FixedWidth::ConfigError.new %{
        Template '#{name}' not found as a known template.
      }.squish unless template
      template.columns.each do |col|
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

    def method_missing(method, *args)
      column(method, *args)
    end

    def length
      @length = nil if @columns_hash != columns.hash
      @length ||= begin
        @columns_hash = columns.hash
        columns.map(&:length).reduce(0,:+)
      end
    end

    protected

    def columns
      @columns ||= []
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

  end
end
