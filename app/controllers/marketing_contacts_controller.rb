class MarketingContactsController < ApplicationController

  def create
    MarketingContact.create(email: params[:marketing_contact][:email])
    if is_production?
      user = User.find_by(role_id: Role.find_by(name: 'marketing').id)
      Analytics.identify(
        user_id: user.id,
        traits: {
          email: params[:marketing_contact][:email],
          marketing_contact_type: true
      })
    end

    respond_to do |format|
      format.js
    end
  end

  def update_banner_message
    room = current_user.main_room
    settings = JSON.parse(room.room_settings)
    settings["bannerMessage"] = params[:bannerMessage]
    if room.update(room_settings: JSON.generate(settings))
      redirect_to update_banner_path(user_uid: current_user.uid), flash: { success: I18n.t("info_update_success") }
    end
  end
  
end
