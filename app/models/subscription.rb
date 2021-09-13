class Subscription < ApplicationRecord

  attr_accessor :skip_callbacks

  belongs_to :user
  belongs_to :plan, optional: true

  after_save :subscribe_plan, on: :commit, unless: :skip_callbacks
  after_save :subscribe_quantity, on: :commit, unless: :skip_callbacks

  def subscribe_plan
    if paid_previously_changed? || active_previously_changed? || subscription_id_previously_changed?
      if paid == "paid" && active == true
        subscribe = StripeService.new.get_subscription(self.subscription_id)
        sub_price = subscribe["items"]["data"][0]["price"]["id"] rescue nil
        sub_quantity = subscribe["items"]["data"][0]["quantity"] rescue 1
        customer = subscribe["customer"]
        subscription_item = subscribe["items"]["data"][0]["id"]
        plan = Plan.find_by(stripe_price_id: sub_price) if sub_price
        sub_trial_end = Time.at(subscribe["trial_end"].to_i).to_datetime
        sub_trial_start = Time.at(subscribe["trial_start"].to_i).to_datetime
        if plan.present?
          update_columns(plan_id: plan.id, cancel_at: nil, quantity: sub_quantity, trial_start: sub_trial_start, trial_end: sub_trial_end, customer_id: customer, subscription_item_id: subscription_item)
          user.update_column('account_type', :business) if sub_quantity > 1 || plan.whistle_pro?
        end
      else
        update_column('plan_id', nil)
      end
    end
  end

  def subscribe_quantity
    if quantity_previously_changed?
      StripeService.new.update_subscription_quantity(subscription_id, self)
    end
  end

  def cancelled?
    cancel_at.present?
  end
end
