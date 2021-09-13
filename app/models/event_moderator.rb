class EventModerator < ApplicationRecord
  belongs_to :event
  belongs_to :moderator, class_name: "User", foreign_key: "moderator_id", optional: true

  before_save { email.try(:downcase!) }
  validates :email, length: { maximum: 256 }, allow_blank: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP }

  def m_email
    moderator.try(:email) || email
  end

  def m_name
    moderator.try(:full_name) || name
  end
end
