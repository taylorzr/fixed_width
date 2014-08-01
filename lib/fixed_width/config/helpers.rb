module FixedWidth
  module Config
    module Helpers
      Functions = {
        blank: ->(v){ !v.blank? },
        to_int: ->(v){ Integer(v) },
        nil_or_proc: ->(v){ v.try(:to_proc) }
      }
    end
  end
end
