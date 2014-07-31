module FixedWidth
  module Options

    def self.included(base)
      base.extend(ClassMethods)
      base.extend(FixedWidth::Helpers)
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
              when Array then err_func( ->(val) { arg.include?(val) },
                ->(val) { ":#{key} must be one of #{arg.inspect}, got '#{val.inspect}'" } )
              when Proc then err_func( arg,
                ->(val) { "'#{val.inspect}' is an invalid value for :#{key}" } )
              when Class then err_func( ->(val) { arg === val },
                ->(val) { ":#{key} must be a #{arg}, got '#{val.inspect}'" } )
              else err_func( ->(val) { arg == val },
                ->(val) { ":#{key} must equal #{arg}, got '#{val.inspect}'" } )
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

      def opt_settings(hash)
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
      end

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
      [:value,:default].each { |x|
        return options[key][x] if options[key].key?(x)
      }
      nil
    end

    def set_opt(name, value, undefined = nil)
      want_bool = undefined.is_a?(Hash)
      if key = opt_defined(name, !want_bool)
        prep = options[key][:prepare].call(value)
        options[key][:value] = prep
      else
        set = ( undefined[name.to_sym] ||= { undefined: true } )
        set[:value] = value
      end
    end

    protected

    def each_opt(undefined = false)
      return enum_for(:each_opt) unless block_given?
      over = (undefined && undefined_options) || {}
      over.merge(options).each do |key, conf|
        yield conf.merge(key: key)
      end
    end

    def merge_options(other, mopts)
      other.each_opt(true) { |conf|
        key = conf[:key]
        if opt_defined(key, false)
          pref = mopts[:prefer]
          mopt_error(:prefer, pref) unless [:self, :other].include?(pref)
          if using_default?(options[key]) # self is default
            if using_default?(conf) # other is default
              if pref == :other
                prep = options[key][:prepare].call(value)
                options[key][:default] = prep
              end
            else # other is value
              set_opt(key, conf[:value])
            end
          else # self is value
            if !using_default?(conf) # other is value
              set_opt(key, conf[:value]) if pref == :other
            end
          end
        else
          mi = mopts[:missing]
          mi_valid = [:import, :raise, :skip, :undefined].include?(mi)
          mopt_error(:missing, mi) unless mi_valid
          case mi
          when :undefined
            undefined_options[key] ||= { undefined: true }
            [:value, :default].each do |vt|
              undefined_options[key][vt] = conf[vt] if conf.key?(vt)
            end
          when :import
            options[key] = conf.reject{ |k,v| k == :key } if conf[:prepare]
          when :raise
            raise FixedWidth::ConfigError.new "Cannot merge option :#{key}"
          end
        end
      }
    end

    def undefined_options
      @undefined_options ||= {}
    end

    private

    def using_default?(hash)
      hash.key?(:default) && !hash.key?(:value)
    end

    def mopt_error(key, got)
      raise FixedWidth::ConfigError.new %{
        Merge does not understand '#{got}' for :#{key}
      }.squish
    end

    def initialize_options(input)
      if input.is_a?(FixedWidth::Options)
        mopts = { prefer: :self, missing: :undefined }
        merge_options(input, mopts)
      elsif input.is_a?(Hash)
        input.each do |k,v|
          set_opt(k,v, undefined_options)
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
          acc[var][:default] = conf[:default] if conf.key?(:default)
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
          missing << key if !conf.key?(:value) && !conf.key?(:default)
        end
      end
      raise FixedWidth::ConfigError.new %{
        The following required fields are missing: #{missing.inspect}
      }.squish unless missing.empty?
    end

  end
end
