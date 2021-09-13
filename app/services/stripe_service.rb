require 'stripe'

class StripeService
  Stripe.api_key = ENV['STRIPE_PRIVATE_KEY']

  def product_list
    products = Stripe::Product.list()
    products["data"]
  end

  def price_list(product_id)
    prices = Stripe::Price.list({product: product_id})
    prices["data"]
  end

  def create_product(params)
    Stripe::Product.create(product_params(params))
  end

  def create_price(params)
    Stripe::Price.create(price_params(params))
  end

  def update_price(params)
    Stripe::Price.update(params[:stripe_price_id], update_price_params(params))
  end

  def get_subscription(sub_id)
    Stripe::Subscription.retrieve(sub_id)
  end

  def update_subscription_quantity(sub_id, subscription)
    Stripe::Subscription.update(sub_id,
      {
        items: [
        {
          id: subscription.subscription_item_id,
          quantity: subscription.quantity,
          price: subscription.plan.stripe_price_id
        }]
      }
    )
  end

  private
  def product_params(params)
    {
      name: params[:name],
      metadata: {
        display_name: params[:display_name]
      }
    }
  end

  def price_params(params)
    {
      nickname: params[:name] || params[:plan_name],
      product: params[:product_id] || params[:stripe_product_id],
      unit_amount: params[:unit_amount],
      currency: 'usd',
      recurring: {
        interval: params[:interval],
      },
      metadata: {
        display_name: params[:display_name] || params[:plan_name]
      }
    }
  end

  def update_price_params(params)
    _params = {}
    _params[:nickname] = params[:plan_name] if params[:plan_name].present?
    _params
  end
end
