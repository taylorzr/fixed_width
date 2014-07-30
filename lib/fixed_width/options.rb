module FixedWidth
  module Options

    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def options(hash)
        hash.each do |name, conf|
          begin
            # Add option definition
            key = name.to_sym
            raise FixedWidth::ConfigError.new %{
              Option :'#{key}' is already defined!
            }.squish if option_config.key?(key)
            option_config[key] = {}
            # Setup transformation function
            if transform = conf[:transform]
              transform = transform.to_proc unless transform.is_a?(Proc)
            end
            # Setup validation function
            validate = !conf.key?(:validate) ? nil :
              case (arg = conf[:validate])
              when Array
                err_func(
                  ->(val) { arg.include?(val) },
                  ->(val) { ":#{key} must be one of #{arg.inspect}," +
                            "got '#{val.inspect}'"
                          }
                )
              when Proc
                err_func(arg, ->(val) {
                  "'#{val.inspect}' is an invalid value for :#{key}"
                })
              when Class
                err_func(
                  ->(val) { arg === val },
                  ->(val) { ":#{key} must be a #{arg}, got '#{val.inspect}'" }
                )
              else
                err_func(
                  ->(val) { arg == val },
                  ->(val) { ":#{key} must equal #{arg}, got '#{val.inspect}'" }
                )
              end
            # Put it together
            option_config[key][:prepare] = lambda { |value|
              value = transform.call(value) if transform
              validate.call(value) if validate
              value
            }
            # Default Value
            if default = conf[:default]
              prep = option_config[key][:prepare].call(default)
              option_config[key][:default] = prep
            end
          rescue => e
            raise if e.is_a?(FixedWidth::BaseError)
            raise FixedWidth::ConfigError.new %{
              Could not add option #{name} due to an error: #{e.inspect}
            }.squish
          end
        end
      end

      def opt_settings(hash) {
        hash.each do |key,val|
          case key
          when :required
            Array(val).map(&:to_sym).each do |field|
              opt_exists_error(field)
              option_config[field][:required] = true
            end
          when :reader
            Array(val).map(&:to_sym).each do |field|
              opt_exists_error(field)
              define_method(field) { opt(field) }
            end
          when :writer
            Array(val).map(&:to_sym).each do |field|
              opt_exists_error(field)
              define_method("#{field}=".to_sym) { |value|
                set_opt(field, value)
              }
            end
          else
            raise FixedWidth::ConfigError.new(
              "Unknown opt_setting '#{key.inspect}'")
          end
        end
      }

      private

      def option_config
        @option_config ||= {}
      end

      def err_func(func, err)
        ->(x) { raise FixedWidth::ConfigError.new(err.(x)) unless func.(x) }
      end

      def opt_exists_error(key)
        raise FixedWidth::ConfigError.new %{
          Option '#{key}' is not defined;
          cannot create a reader function
        }.squish unless option_config.key?(key)
      end
    end

    def opt(name)
      key = opt_defined(name)
      options[key][:value]
    end

    def set_opt(name, value)
      key = opt_defined(name)
      prep = options[key][:prepare].call(value)
      options[key][:value] = prep
    end

    protected

    def each_opt(&blk)
      options.each(&blk)
    end

    def merge_options(other, mopts)
      other.each_opt { |key, conf|
        if opt_defined(key, false)
          case mopts[:prefer]
          when :self
            set_opt(key, conf[key][:value]) unless options[key].key?(:value)
          when :other
            set_opt(key, conf[key][:value])
          else mopt_error(:prefer, mopts[:prefer])
          end
        else
          case mopts[:missing]
          when :import
            options[key] = conf[key].dup
          when :raise
            raise FixedWidth::ConfigError.new "Cannot merge option :#{key}"
          when :skip
          else mopt_error(:missing, mopts[:missing])
          end
        end
      }
    end

    def blank
      ->(v){ !v.blank? }
    end

    def to_int
      ->(v){ Integer(v) }
    end

    def nil_or_proc
      ->(v){ v.try(:to_proc) }
    end

    private

    def mopt_error(key, got)
      raise FixedWidth::ConfigError.new %{
        Merge does not understand '#{got}' for :#{key}
      }.squish
    end

    def initialize_options(input)
      if input.is_a?(FixedWidth::Options)
        mopts = { prefer: :self, missing: :skip }
        merge_options(input, mopts)
      elsif input.is_a?(Hash)
        input.each do |k,v|
          set_opt(k,v)
        end
      else
        raise FixedWidth::ConfigError.new %{
          Not sure how to initialize options from '#{input.inspect}'
        }.squish
      end
      check_required_opts!
    end

    def options
      @options ||= begin
        config = self.class.send(:option_config)
        config.reduce({}) { |acc, (var,conf)|
          acc[var] = {
            prepare: conf[:prepare],
            required: !!conf[:required]
          }
          acc[var][:value] = conf[:default] if conf.key?(:default)
          acc
        }
      end
    end

    def opt_defined(name, raise_undef = true)
      key = name.to_sym
      exists = options.key?(key)
      return exists unless raise_undef
      raise unless exists
      key
    rescue
      raise FixedWidth::ConfigError.new %{
        Option '#{name}' is not defined!
      }.squish
    end

    def check_required_opts!
      missing = []
      options.each do |key, conf|
        if conf[:required]
          missing << key unless conf.key(:value)
        end
      end
      raise FixedWidth::ConfigError.new %{
        The following required fields are missing: #{missing.inspect}
      }.squish unless missing.empty?
    end

  end
end
