# frozen_string_literal: true

# BigBlueButton open source conferencing system - http://www.bigbluebutton.org/.
#
# Copyright (c) 2018 BigBlueButton Inc. and by respective authors (see below).
#
# This program is free software; you can redistribute it and/or modify it under the
# terms of the GNU Lesser General Public License as published by the Free Software
# Foundation; either version 3.0 of the License, or (at your option) any later
# version.
#
# BigBlueButton is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License along
# with BigBlueButton; if not, see <http://www.gnu.org/licenses/>.

require 'i18n/language/mapping'

module UsersHelper
  include I18n::Language::Mapping

  def recaptcha_enabled?
    Rails.configuration.recaptcha_enabled
  end

  def disabled_roles(user)
    current_user_role = current_user.role

    # Admins are able to remove the admin role from other admins
    # For all other roles they can only add/remove roles with a higher priority
    disallowed_roles = if current_user_role.name == "admin"
                          Role.editable_roles(@user_domain).where("priority < #{current_user_role.priority}")
                              .pluck(:id)
                        else
                          Role.editable_roles(@user_domain).where("priority <= #{current_user_role.priority}")
                              .pluck(:id)
                       end

    [user.role.id] + disallowed_roles
  end

  # Returns language selection options for user edit
  def language_options
    locales = I18n.available_locales
    language_opts = [['<<<< ' + t("language_default") + ' >>>>', "default"]]
    locales.each do |locale|
      language_mapping = I18n::Language::Mapping.language_mapping_list[locale.to_s.gsub("_", "-")]
      language_opts.push([language_mapping["nativeName"], locale.to_s])
    end
    language_opts.sort
  end

  # Returns a list of roles that the user can have
  def role_options
    Role.editable_roles(@user_domain).where("priority >= ?", current_user.role.priority).by_priority
  end

  # Parses markdown for rendering.
  def markdown(text)
    markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML,
      no_intra_emphasis: true,
      fenced_code_blocks: true,
      disable_indented_code_blocks: true,
      autolink: true,
      tables: true,
      underline: true,
      highlight: true)

    markdown.render(text).html_safe
  end

  def subscription_plans
    plans = [['Whistle Community', nil]]
    Plan.all.each do |plan|
      plans << ["#{plan.plan_type.titleize} @ $#{plan.unit_amount.to_f} per host / #{plan.interval}", plan.id.to_s, {'data-package' => plan.plan_type}]
    end
    plans
  end

  def plan_pricing_detail
    if current_user&.plan_subscription and current_user.plan_subscription.quantity > 1
      return "$ #{current_user.subscribe_plan.unit_amount * current_user.plan_subscription.quantity} for #{current_user.plan_subscription.quantity} hosts per #{current_user.subscribe_plan.interval}"
    elsif current_user&.subscribe_plan
      return "$ #{current_user.subscribe_plan.unit_amount} per #{current_user.subscribe_plan.interval}"
    end
    "Free"
  end

  def get_brand_color type
    colors = JSON.parse(current_user.theme_colors)
    return colors[type]
  end
end
