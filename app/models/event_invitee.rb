class EventInvitee < ApplicationRecord
  belongs_to :event, touch: true
  belongs_to :invitee, class_name: "User", foreign_key: "invitee_id", optional: true

  before_save { email.try(:downcase!) }
  validates :email, length: { maximum: 256 }, allow_blank: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP }

  def i_email
    invitee.try(:email) || email
  end

  def i_name
    invitee.try(:full_name) || name
  end
end
