# encoding: utf-8
module DoubleEntry
  class Account

    class << self
      attr_writer :accounts

      # @api private
      def accounts
        @accounts ||= Account::Set.new
      end

      # @api private
      def account(identifier, options = {})
        account = accounts.find(identifier, options[:scope].present?)
        DoubleEntry::Account::Instance.new(:account => account, :scope => options[:scope])
      end

      # @api private
      def currency(identifier)
        accounts.detect { |a| a.identifier == identifier }.try(:currency)
      end
    end

    # @api private
    class Set < Array
      def define(attributes)
        self << Account.new(attributes)
      end

      def find(identifier, scoped)
        account = detect do |account|
          account.identifier == identifier && account.scoped? == scoped
        end
        raise UnknownAccount.new("account: #{identifier} scoped?: #{scoped}") unless account
        return account
      end

      def <<(account)
        if any? { |a| a.identifier == account.identifier }
          raise DuplicateAccount.new
        else
          super(account)
        end
      end

      def active_record_scope_identifier(active_record_class)
        ActiveRecordScopeFactory.new(active_record_class).scope_identifier
      end
    end

    class ActiveRecordScopeFactory
      def initialize(active_record_class)
        @active_record_class = active_record_class
      end

      def scope_identifier
        lambda do |value|
          case value
          when @active_record_class
            value.id
          when String, Fixnum
            value
          else
            raise AccountScopeMismatchError.new("Expected instance of `#{@active_record_class}`, received instance of `#{value.class}`")
          end
        end
      end
    end

    class Instance
      attr_reader :account, :scope
      delegate :identifier, :scope_identifier, :scoped?, :positive_only, :currency, :to => :account

      def initialize(args)
        @account = args[:account]
        @scope = args[:scope]
        ensure_scope_is_valid
      end

      def scope_identity
        scope_identifier.call(scope).to_s if scoped?
      end

      # Get the current or historic balance of this account.
      #
      # @option options :from [Time]
      # @option options :to [Time]
      # @option options :at [Time]
      # @option options :code [Symbol]
      # @option options :codes [Array<Symbol>]
      # @return [Money]
      #
      def balance(options = {})
        BalanceCalculator.calculate(self, options)
      end

      include Comparable

      def ==(other)
        other.is_a?(self.class) && identifier == other.identifier && scope_identity == other.scope_identity
      end

      def eql?(other)
        self == other
      end

      def <=>(account)
        [scope_identity.to_s, identifier.to_s] <=> [account.scope_identity.to_s, account.identifier.to_s]
      end

      def hash
        if scoped?
          "#{scope_identity}:#{identifier}".hash
        else
          identifier.hash
        end
      end

      def to_s
        "\#{Account account: #{identifier} scope: #{scope} currency: #{currency}}"
      end

      def inspect
        to_s
      end

      private

      def ensure_scope_is_valid
        scope_identity
      end
    end

    attr_reader :identifier, :scope_identifier, :positive_only, :currency

    def initialize(args)
      @identifier = args[:identifier]
      @scope_identifier = args[:scope_identifier]
      @positive_only = args[:positive_only]
      @currency = args[:currency] || Money.default_currency
    end

    def scoped?
      !!scope_identifier
    end
  end
end
