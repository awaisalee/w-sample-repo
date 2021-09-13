require 'auth0'
require 'uri'
require 'net/http'
require 'openssl'

class Auth0Service
  attr_accessor :response

  def initialize(user=nil)
    @user ||= user
    @connection = "Username-Password-Authentication"
    @access_token = get_access_token
    @client = Auth0Client.new(
      token: @access_token,
      domain: ENV['AUTH0_DOMAIN'],
      api_version: 2,
      timeout: 15
    )
  end

  def admin_create_user
    @response = @client.create_user(@user.full_name, user_params)
    if @response.present?
      @user.update_columns(
        auth0_uid: @response["user_id"],
        status: :invited
      )
      send_password_reset_email
    end
    @response
  rescue
    nil
  end

  def admin_destroy_user
    @client.delete_user(@user.auth0_uid) if @user.auth0_uid.present?
  rescue
    nil
  end

  def send_password_reset_email
    url = URI("https://#{ENV['AUTH0_DOMAIN']}/dbconnections/change_password")
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    request = Net::HTTP::Post.new(url)
    request["content-type"] = 'application/json'
    request.body = password_change_params.to_json

    response = http.request(request)
    response
  end

  def admin_update_user
    @response = @client.patch_user(@user.auth0_uid, patch_user_params) if @user.auth0_uid.present?
    @response
  rescue
    nil
  end

  private

  def user_params
    {
      email: @user.email,
      name: @user.full_name,
      connection: @connection,
      password: generate_random_password,
      verify_email: false,
      email_verified: false,
      user_metadata: {
        role: @user.role.try(:name)
      }
    }
  end

  def password_change_params
    {
      client_id: ENV['AUTH0_CLIENT_ID'],
      email: @user.email,
      connection: @connection
    }
  end

  def patch_user_params
    {
      connection: @connection,
      name: @user.full_name,
      user_metadata: { role: @user.role.try(:name) },
      blocked: false
    }
  end

  def get_access_token
    url = URI("https://#{ENV['AUTH0_DOMAIN']}/oauth/token")

    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    request = Net::HTTP::Post.new(url)
    request["content-type"] = 'application/x-www-form-urlencoded'
    request.body = "grant_type=client_credentials&client_id=#{ENV['AUTH0_API_ID']}&client_secret=#{ENV['AUTH0_API_SECRET']}&audience=#{ENV['AUTH0_AUDIENCE']}"

    response = http.request(request)
    body = JSON.parse(response.body)
    body["access_token"]
  rescue
    nil
  end

  def generate_random_password
    SecureRandom.base64(8)
  end
end
