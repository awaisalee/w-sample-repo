class Api::V1::PasswordsController < Api::ApiController
  include Emailer
  before_action :find_user, only: [:reset_password, :validate_token]
  skip_before_action :auth0_authenticate_request!, only: [:forgot_password, :reset_password]

  def forgot_password
    # Check if user exists and throw an error if he doesn't
    begin
      @user = User.find_by!(email: params[:password_reset][:email].downcase, provider: 'greenlight')
      send_password_reset_email(@user, @user.create_reset_digest, 'api')
      render json: { success: I18n.t("email_sent", email_type: t("forgot_password.subtitle")) }, status: 200
    rescue
      # User doesn't exist
      render json: { error: I18n.t("no_user_email_exists") }, status: 404
    end
  end

  def validate_token
    render json: {success: 'Valid Token'} , status: 200 if @user
  end

  def reset_password
    # Check if password is valid
    if params[:user][:password].empty?
      return render json: { error: I18n.t("password_empty_notice") }, status: 422
    elsif params[:user][:password] != params[:user][:password_confirmation]
      # Password does not match password confirmation
      render json: { error: I18n.t("password_different_notice") }, status: 422
    elsif @user.update_attributes(user_params)
      # Clear the user's social uid if they are switching from a social to a local account
      @user.update_attribute(:social_uid, nil) if @user.social_uid.present?
      # destroy one_time_link
      @user.destroy_reset_digest
      # Successfully reset password
      return render json: { success: I18n.t("password_reset_success") }, status: 200
    end
    render json: {}, status: 422
  end

  private

  def find_user
    @user = User.find_by(reset_digest: User.hash_token(params[:token]), provider: 'greenlight')
    return render json: { error: I18n.t("reset_password.invalid_token") }, status: 404 unless @user
  end

  def user_params
    params.require(:user).permit(:password, :password_confirmation)
  end
end
