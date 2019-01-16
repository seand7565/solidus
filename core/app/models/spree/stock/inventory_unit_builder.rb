# frozen_string_literal: true

module Spree
  module Stock
    class InventoryUnitBuilder
      def initialize(order)
        @order = order
      end

      def units
        @order.line_items.flat_map do |line_item|
          Spree::InventoryUnit.new(
            pending: true,
            variant: line_item.variant,
            line_item: line_item,
            quantity: line_item.quantity
          )
        end
      end
    end
  end
end
