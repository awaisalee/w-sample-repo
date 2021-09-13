class Participant < ApplicationRecord
  belongs_to :appointment, touch: true
  before_save { email.try(:downcase!) }
  validates :email, length: { maximum: 256 }, allow_blank: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP }

  after_destroy :send_dropped_email

  def send_dropped_email
    appointment.send_meeting_dropped_email_to(self)
  end
end
