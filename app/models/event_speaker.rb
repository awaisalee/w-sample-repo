class EventSpeaker < ApplicationRecord
  belongs_to :event, touch: true
  belongs_to :speaker, class_name: "User", foreign_key: "speaker_id", optional: true

  before_save { email.try(:downcase!) }
  validates :email, length: { maximum: 256 }, allow_blank: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP }

  def s_email
    speaker.try(:email) || email
  end

  def s_name
    speaker.try(:full_name) || name
  end
end
