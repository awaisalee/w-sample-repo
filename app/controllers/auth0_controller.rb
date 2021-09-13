class Auth0Controller < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :check_api_key

  def signup
    @user = User.where(email: user_params[:email]).first_or_create!(user_params)
    @user.try(:activate) if @user.present?
    render json: { success: true }, status: 200
  rescue => e
    render json: { }, status: 500
  end

  def activate
    @user = User.find_by(email: user_params[:email])
    @user.try(:activate)
    head :no_content
  end

  private

  def check_api_key
    return render json: { error: 'invalid api key' } unless ENV['WHISTLE_LIVE_API_KEY'] == params[:apiKey]
  end

  def random_password
    @random_password ||= SecureRandom.base64(8)
  end

  def user_params
    {
      email: params['user']['email'],
      first_name: params['user']['email'],
      last_name: params['user']['email'],
      auth0_uid: params['user']['id'],
      provider: 'auth0',
      password: random_password,
      password_confirmation: random_password
    }
  end
end
