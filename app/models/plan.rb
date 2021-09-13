class Plan < ApplicationRecord
  has_many :subscriptions

  enum interval: { month: 0, year: 1 }
  enum plan_type: { whistle_plus: 0, whistle_pro: 1 }

  after_update :update_on_stripe, on: :commit

  def update_on_stripe
    if unit_amount_previously_changed?
      params = self.dup
      params[:unit_amount] = params[:unit_amount] * 100
      price_id = StripeService.new.create_price(params)
      update_attribute(:stripe_price_id, price_id["id"])
    end
  end
end
