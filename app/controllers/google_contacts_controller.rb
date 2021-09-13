class GoogleContactsController < ApplicationController

  def search
    @get_contact = current_user.google_contacts.where("email_address LIKE ? OR name LIKE ?", "%#{params[:search]}%", "%#{params[:search]}%").where.not(email_address:nil)
    respond_to do |format|
      format.json  { render :json => @get_contact } 
    end
  end
end
