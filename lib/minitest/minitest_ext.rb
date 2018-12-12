module Minitest
  class Test #< Runnable
    class << self
      def metadata
        @metadata ||= {}
      end

      def params
        @params ||= []
      end

      def example(desc=nil, &block)
        it desc do
          self.class.metadata[:example_name] = desc
          self.instance_eval(&block)
        end
      end

      def meta(key, value)
        metadata[key] = value
      end

      def param(name, description, options={})
        params << {name: name, description: description}.merge(options)
      end
    end
  end
end

# module Kernel
#   # `document` is an alias for `describe` but it also declares the tests
#   # order-dependent. This is because we would like to have the documentation
#   # always in the same order.
#   def document(desc, additional_desc=nil, &block)
#     describe desc, additional_desc do
#       i_suck_and_my_tests_are_order_dependent!
#       self.instance_eval(&block)
#     end
#   end
# end
module Kernel
  # `document` is an alias for `describe` but it also declares the tests
  # order-dependent. This is because we would like to have the documentation
  # always in the same order.
  def document(desc, additional_desc=nil, &block)

    # puts "documenting..."

    if desc.include?("::")
      module_split_name = desc.split("::")

      first_module = nil

      module_split_name.each do |name|

        if module_split_name.last != name

          if first_module
            begin
              klass = first_module.const_get(name)
            rescue NameError
              klass = first_module.const_set(name, Module.new)
            end
          else
            begin
              klass = Module.const_get(name)
            rescue NameError
              klass = Object.const_set(name, Module.new)
            end
          end

          first_module = klass
        else

          spec_name = name + "Spec"

          begin
            last_klass = first_module.const_get(spec_name)
          rescue NameError
            last_klass = first_module.const_set(spec_name,  Class.new(ApiSpec) {
              include Minitest::Apidoc::CaptureMethods
              i_suck_and_my_tests_are_order_dependent!

              # This allows for methods defined in the spec to be included
              self.class_eval(&block)
            })
          end
          first_module = last_klass
        end
      end

    else
      Object.const_set(desc,  Class.new(ApiSpec) {
        include Minitest::Apidoc::CaptureMethods
        i_suck_and_my_tests_are_order_dependent!
        self.instance_eval(&block)
      })
    end
  end
end


module Minitest
  module Apidoc
    class Endpoint
      attr_accessor :metadata, :params, :examples

      def initialize(test_class)
        @params = test_class.params
        @metadata = test_class.metadata
        @examples = []
      end

      # If request method is specified explicitly in the metadata by the user,
      # prefer that. If not, grab the request method that was actually used by
      # rack-test (stored in the example).
      def request_method

        found_verb = @metadata[:request_method].to_s || @examples[0].request_method
        found_verb = found_verb.downcase

        allowed_verbs = %w[head get post put patch delete options]
        if !allowed_verbs.include?(found_verb)
          raise "Verb '#{found_verb}' is not in the list of allowed verbs: [#{allowed_verbs.join(', ')}]"
        end

        found_verb.upcase
      end

    end
  end
end

# require "rack/test"

module Minitest
  module Apidoc
    module CaptureMethods
      include Rack::Test::Methods

      VERBS = %w[head get post put patch delete options]

      # Takes over rack-test's `get`, `post`, etc. methods (first aliasing the
      # originals so that they can still be used). This way we can call the
      # methods normally in our tests but they perform all the documentation
      # goodness.
      VERBS.each do |verb|
        alias_method "rack_test_#{verb}", verb
        # new_method_name = "capture_#{verb}"
        new_method_name = verb
        define_method(new_method_name) do |uri, params={}, env={}, &block|
          _request(verb, uri, params, env, &block)
        end
      end

      # Performs a rack-test request while also saving the metadata necessary
      # for documentation. Detects if the response is JSON (naively by just
      # trying to parse it as JSON). If it is, formats the response nicely and
      # also yields the data as parsed JSON object instead of raw text.
      def _request(verb, uri, params={}, env={})
        send("rack_test_#{verb}", uri, params, env)
        self.class.metadata[:session] = current_session

        response_data = begin
          JSON.load(last_response.body)
        rescue JSON::ParserError
          last_response.body
        end

        yield response_data if block_given?
      end
    end
  end
end