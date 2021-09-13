module PricingHelper
  def default_pricing_account
    if current_user
      return current_user.account_type if current_user.manager?
      return "#{current_user.manager.account_type}_immutable"
    end
    "business"
  end

  def whistle_plus_month
    @whistle_plus_month ||= Plan.whistle_plus.month.first
  end

  def whistle_plus_year
    @whistle_plus_year ||= Plan.whistle_plus.year.first
  end

  def whistle_pro_month
    @whistle_pro_month ||= Plan.whistle_pro.month.first
  end

  def whistle_pro_year
    @whistle_pro_year ||= Plan.whistle_pro.year.first
  end
end
