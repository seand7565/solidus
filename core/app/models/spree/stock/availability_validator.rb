# frozen_string_literal: true

module Spree
  module Stock
    class AvailabilityValidator < ActiveModel::Validator
      def validate(line_item)
        if is_valid?(line_item)
          true
        else
          variant = line_item.variant
          display_name = variant.name.to_s
          display_name += %{ (#{variant.options_text})} unless variant.options_text.blank?

          line_item.errors[:quantity] << I18n.t(
            'spree.selected_quantity_not_available',
            item: display_name.inspect
          )
          false
        end
      end

      private

      def is_valid?(line_item)
        if line_item.inventory_units.empty?
          Stock::Quantifier.new(line_item.variant).can_supply?(line_item.quantity)
        else
          quantity_by_stock_location_id = line_item.inventory_units.pending.group_by{|iu|iu.shipment.stock_location_id}
          quantity_by_stock_location_id.all? do |stock_location_id, inventory_unit|
            Stock::Quantifier.new(line_item.variant, stock_location_id).can_supply?(inventory_unit.sum(&:quantity))
          end
        end
      end
    end
  end
end
