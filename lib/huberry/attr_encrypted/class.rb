module Huberry
  module AttrEncrypted
    module Class
      protected
        # Generates attr_accessors that encrypt and decrypt attributes transparently
        #
        # Options (any other options you specify are passed to the encryptor's encrypt and decrypt methods)
        #
        #   :attribute      => The name of the referenced encrypted attribute. For example 
        #                      <tt>attr_accessor :email, :attribute => :ee</tt> would generate an 
        #                      attribute named 'ee' to store the encrypted email. This is useful when defining
        #                      one attribute to encrypt at a time or when the :prefix and :suffix options
        #                      aren't enough. Defaults to nil.
        #
        #   :prefix         => A prefix used to generate the name of the referenced encrypted attributes.
        #                      For example <tt>attr_accessor :email, :password, :prefix => 'crypted_'</tt> would 
        #                      generate attributes named 'crypted_email' and 'crypted_password' to store the 
        #                      encrypted email and password. Defaults to 'encrypted_'.
        #
        #   :suffix         => A suffix used to generate the name of the referenced encrypted attributes.
        #                      For example <tt>attr_accessor :email, :password, :prefix => '', :suffix => '_encrypted'</tt>  
        #                      would generate attributes named 'email_encrypted' and 'password_encrypted' to store the 
        #                      encrypted email. Defaults to ''.
        #
        #   :key            => The encryption key. This option may not be required if you're using a custom encryptor. If you pass 
        #                      a symbol representing an instance method then the :key option will be replaced with the result of the 
        #                      method before being passed to the encryptor. Objects that respond to :call are evaluated as well (including procs). 
        #                      Any other key types will be passed directly to the encryptor.
        #
        #   :encode         => If set to true, attributes will be encoded as well as encrypted. This is useful if you're
        #                      planning on storing the encrypted attributes in a database. The default encoding is 'm*' (base64), 
        #                      however this can be overwritten by setting the :encode option to some other encoding string instead of
        #                      just 'true'. See http://www.ruby-doc.org/core/classes/Array.html#M002245 for more encoding directives. 
        #                      Defaults to false unless you're using it with ActiveRecord or DataMapper.
        #
        #   :marshal        => If set to true, attributes will be marshaled as well as encrypted. This is useful if you're planning
        #                      on encrypting something other than a string. Defaults to false unless you're using it with ActiveRecord 
        #                      or DataMapper.
        #
        #   :encryptor      => The object to use for encrypting. Defaults to Huberry::Encryptor.
        #
        #   :encrypt_method => The encrypt method name to call on the <tt>:encryptor</tt> object. Defaults to :encrypt.
        #
        #   :decrypt_method => The decrypt method name to call on the <tt>:encryptor</tt> object. Defaults to :decrypt.
        #
        #   :if             => Attributes are only encrypted if this option evaluates to true. If you pass a symbol representing an instance 
        #                      method then the result of the method will be evaluated. Any objects that respond to :call are evaluated as well. 
        #                      Defaults to true.
        #
        #   :unless         => Attributes are only encrypted if this option evaluates to false. If you pass a symbol representing an instance 
        #                      method then the result of the method will be evaluated. Any objects that respond to :call are evaluated as well. 
        #                      Defaults to false.
        #
        # You can specify your own default options
        #
        #   class User
        #     # now all attributes will be encoded and marshaled by default
        #     attr_encrypted_options.merge!(:encode => true, :marshal => true, :some_other_option => true)
        #     attr_encrypted :configuration
        #   end
        #
        #
        # Example
        #
        #   class User
        #     attr_encrypted :email, :credit_card, :key => 'some secret key'
        #     attr_encrypted :configuration, :key => 'some other secret key', :marshal => true
        #   end
        #
        #   @user = User.new
        #   @user.encrypted_email # returns nil
        #   @user.email = 'test@example.com'
        #   @user.encrypted_email # returns the encrypted version of 'test@example.com'
        #
        #   @user.configuration = { :time_zone => 'UTC' }
        #   @user.encrypted_configuration # returns the encrypted version of configuration
        #
        #   See README for more examples
        def attr_encrypted(*attrs)
          options = { 
            :prefix => 'encrypted_', 
            :suffix => '', 
            :encryptor => Huberry::Encryptor, 
            :encrypt_method => :encrypt,
            :decrypt_method => :decrypt,
            :encode => false, 
            :marshal => false, 
            :if => true, 
            :unless => false 
          }.merge(attr_encrypted_options).merge(attrs.last.is_a?(Hash) ? attrs.pop : {})
          options[:encode] = 'm*' if options[:encode] == true
          
          attrs.each do |attribute|
            encrypted_attribute_name = options[:attribute].nil? ? options[:prefix].to_s + attribute.to_s + options[:suffix].to_s : options[:attribute].to_s
            
            encrypted_attributes[attribute.to_s] = encrypted_attribute_name
            
            attr_reader encrypted_attribute_name.to_sym unless instance_methods.include?(encrypted_attribute_name)
            attr_writer encrypted_attribute_name.to_sym unless instance_methods.include?("#{encrypted_attribute_name}=")
            
            define_class_method "encrypt_#{attribute}" do |value|
              if options[:if] && !options[:unless]
                if value.nil?
                  encrypted_value = nil
                else
                  value = Marshal.dump(value) if options[:marshal]
                  encrypted_value = options[:encryptor].send options[:encrypt_method], options.merge(:value => value)
                  encrypted_value = [encrypted_value].pack(options[:encode]) if options[:encode]
                end
                encrypted_value
              else
                value
              end
            end
            
            define_class_method "decrypt_#{attribute}" do |encrypted_value|
              if options[:if] && !options[:unless]
                if encrypted_value.nil?
                  decrypted_value = nil
                else
                  encrypted_value = encrypted_value.unpack(options[:encode]).to_s if options[:encode]
                  decrypted_value = options[:encryptor].send(options[:decrypt_method], options.merge(:value => encrypted_value))
                  decrypted_value = Marshal.load(decrypted_value) if options[:marshal]
                end
                decrypted_value
              else
                encrypted_value
              end
            end
            
            define_method "#{attribute}" do
              value = instance_variable_get("@#{attribute}")
              encrypted_value = send(encrypted_attribute_name.to_sym)
              original_options = [:key, :if, :unless].inject({}) do |hash, option|
                hash[option] = options[option]
                options[option] = self.class.send :evaluate_attr_encrypted_option, options[option], self
                hash
              end
              value = instance_variable_set("@#{attribute}", self.class.send("decrypt_#{attribute}".to_sym, encrypted_value)) if value.nil? && !encrypted_value.nil?
              options.merge!(original_options)
              value
            end
            
            define_method "#{attribute}=" do |value|
              original_options = [:key, :if, :unless].inject({}) do |hash, option|
                hash[option] = options[option]
                options[option] = self.class.send :evaluate_attr_encrypted_option, options[option], self
                hash
              end
              send("#{encrypted_attribute_name}=".to_sym, self.class.send("encrypt_#{attribute}".to_sym, value))
              options.merge!(original_options)
              instance_variable_set("@#{attribute}", value)
            end
          end
        end
        
        # Evaluates an option specified as a symbol representing an instance method or a proc
        # If the option is not a symbol or proc then the original option is returned
        def evaluate_attr_encrypted_option(option, object)
          if option.is_a?(Symbol) && object.respond_to?(option)
            object.send(option)
          elsif option.respond_to?(:call)
            option.call(object)
          else
            option
          end
        end
    end
  end
end