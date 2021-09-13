# frozen_string_literal: true

module AuthResource
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_user
  end

  private

  def authenticate_user
    unless user_signed_in?
      redirect_to home_page
      return
    end
  end
end
