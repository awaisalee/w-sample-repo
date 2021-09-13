class ContactController < ApplicationController
  include Emailer

  def index
    @contact = ContactMessage.new(new_contact_params)
  end

  def send_feedback
    @user = current_user || {email: contact_params[:email]}
    @contact = ContactMessage.create(contact_params)
    send_contact_feedback_email(@user[:email], @contact)

    redirect_to home_page, flash: { success: "Thank you for contacting us, We will get back to you soon." }
  end

  def thank_you
  end

  def contact_params
    params.require(:contact_message).permit(
      :user_id,
      :name,
      :email,
      :subject,
      :message
    )
  end

  def new_contact_params
    {
      name: current_user.try(:full_name) || '',
      email: current_user.try(:email) || '',
      user_id: current_user.try(:id)
    }
  end
end
