require 'rack/protection'
require 'rack/utils'
require 'tempfile'

begin
  require 'escape_utils'
rescue LoadError
end

module Rack
  module Protection
    ##
    # Prevented attack::   XSS
    # Supported browsers:: all
    # More infos::         http://en.wikipedia.org/wiki/Cross-site_scripting
    #
    # Automatically escapes Rack::Request#params so they can be embedded in HTML
    # or JavaScript without any further issues. Calls +html_safe+ on the escaped
    # strings if defined, to avoid double-escaping in Rails.
    #
    # Options:
    # escape:: What escaping modes to use, should be Symbol or Array of Symbols.
    #          Available: :html (default), :javascript, :url
    class EscapedParams < Base
      extend Rack::Utils

      class << self
        alias escape_url escape
        public :escape_html
      end

      default_options :escape => :html,
        :escaper => defined?(EscapeUtils) ? EscapeUtils : self

      def initialize(*)
        super

        modes       = Array options[:escape]
        @escaper    = options[:escaper]
        @html       = modes.include? :html
        @javascript = modes.include? :javascript
        @url        = modes.include? :url

        if @javascript and not @escaper.respond_to? :escape_javascript
          fail("Use EscapeUtils for JavaScript escaping.")
        end
      end

      def call(env)
        request  = Request.new(env)
        get_was  = handle(request.GET, env)
        post_was = handle(request.POST, env) rescue nil
        app.call env
      ensure
        request.GET.replace  get_was  if get_was
        request.POST.replace post_was if post_was
      end

      def handle(hash, env)
        was = hash.dup
        hash.replace escape(hash, env)
        was
      end

      def escape(object, env)
        case object
        when Hash   then escape_hash(object, env)
        when Array  then object.map { |o| escape(o) }
        when String then escape_string(object)
        when Tempfile then object
        when nil then nil
        else
          warn(env, "Unable to escape unhandled #{object.inspect} - dropping from params")
          nil
        end
      end

      def escape_hash(hash, env)
        hash = hash.dup
        hash.each { |k,v| hash[k] = escape(v, env) }
        hash
      end

      def escape_string(str)
        str = @escaper.escape_url(str)        if @url
        str = @escaper.escape_html(str)       if @html
        str = @escaper.escape_javascript(str) if @javascript
        str
      end
    end
  end
end
