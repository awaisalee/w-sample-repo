class PricingController < ApplicationController
  before_action :check_pricing_enabled

  def index
  end

  def upgrade
  end

  private
  def check_pricing_enabled
    redirect_to home_page unless enable_pricing?
  end
end
