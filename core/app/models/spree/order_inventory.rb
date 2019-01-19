# frozen_string_literal: true

module Spree
  class OrderInventory
    attr_accessor :order, :line_item, :variant

    def initialize(order, line_item)
      @order = order
      @line_item = line_item
      @variant = line_item.variant
    end

    # Only verify inventory for completed orders (as orders in frontend checkout
    # have inventory assigned via +order.create_proposed_shipment+) or when
    # shipment is explicitly passed
    #
    # In case shipment is passed the stock location should only unstock or
    # restock items if the order is completed. That is so because stock items
    # are always unstocked when the order is completed through +shipment.finalize+
    def verify(shipment = nil)
      if order.completed? || shipment.present?
        line_item.reload
        existing_quantity = inventory_units.sum(&:quantity)
        desired_quantity = line_item.quantity - existing_quantity
        if desired_quantity > 0
          shipment ||= determine_target_shipment
          add_to_shipment(shipment, desired_quantity)
        elsif desired_quantity < 0
          remove(-desired_quantity, shipment)
        end
      end
    end

    def inventory_units
      line_item.inventory_units
    end

    private

    def remove(quantity, shipment = nil)
      if shipment.present?
        remove_from_shipment(shipment, quantity)
      else
        remove_from_any_shipment(quantity)
      end
    end

    # Returns either one of the shipment:
    #
    # first unshipped that already includes this variant
    # first unshipped that's leaving from a stock_location that stocks this variant
    def determine_target_shipment
      potential_shipments = order.shipments.select(&:ready_or_pending?)

      potential_shipments.detect do |shipment|
        shipment.include?(variant)
      end || potential_shipments.detect do |shipment|
        variant.stock_location_ids.include?(shipment.stock_location_id)
      end
    end

    def add_to_shipment(shipment, quantity)
      pending_units = []
      if variant.should_track_inventory?
        on_hand, back_order = shipment.stock_location.fill_status(variant, quantity)
        pending_units << shipment.set_up_inventory('on_hand', variant, order, line_item, on_hand) unless on_hand.zero?
        pending_units << shipment.set_up_inventory('backordered', variant, order, line_item, back_order) unless back_order.zero?
      else
        pending_units << shipment.set_up_inventory('on_hand', variant, order, line_item, on_hand)
      end

      # adding to this shipment, and removing from stock_location
      if order.completed?
        Spree::Stock::InventoryUnitsFinalizer.new(pending_units).run!
      end

      quantity
    end

    def remove_from_any_shipment(quantity)
      order.shipments.each do |shipment|
        break if quantity == 0
        quantity -= remove_from_shipment(shipment, quantity)
      end
    end

    def remove_from_shipment(shipment, quantity)
      return 0 if quantity == 0 || shipment.shipped?

      shipment_units = shipment.inventory_units_for_item(line_item, variant).where.not(:state => 'shipped').sort_by(&:state)

      removed_quantity = 0

      shipment_units.each do |inventory_unit|
        break if removed_quantity == quantity
        if inventory_unit.quantity <= quantity
          inventory_unit_quantity = inventory_unit.quantity
          inventory_unit.destroy
          removed_quantity += inventory_unit_quantity
        else
          inventory_unit.update(:quantity => inventory_unit.quantity - quantity)
          removed_quantity += quantity
        end
      end

      if shipment.inventory_units.sum(&:quantity).zero?
        order.shipments.destroy(shipment)
      end

      # removing this from shipment, and adding to stock_location
      if order.completed?
        shipment.stock_location.restock variant, removed_quantity, shipment
      end

      removed_quantity
    end
  end
end
