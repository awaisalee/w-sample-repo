module Secured
  include Auth0JsonWebToken
  extend ActiveSupport::Concern

  SCOPES = {
    '/private' => nil,
    '/private-scoped' => ['read:messages']
  }

  included do
    before_action :auth0_authenticate_request!
  end

  def current_user
    @current_user
  end

  private

  def auth0_authenticate_request!
    @auth_payload, @auth_header = auth_token
    @current_user ||= User.find_or_simulate(@auth_payload) if @auth_payload.present?
    if @current_user.present?
      User.current_user = @current_user
    else
      raise Exception.new "Not Authenticated"
    end
    render json: { errors: ['Insufficient scope'] }, status: :unauthorized unless scope_included
  rescue JWT::VerificationError, JWT::DecodeError
    render json: { errors: ['Not Authenticated'] }, status: :unauthorized
  rescue => e
    Rails.logger.error(e.inspect)
    render json: { errors: ['Not Authenticated'] }, status: :unauthorized
  end

  def scope_included
    if SCOPES[request.env['PATH_INFO']] == nil
      true
    else
      # The intersection of the scopes included in the given JWT and the ones in the SCOPES hash needed to access
      # the PATH_INFO, should contain at least one element
      (String(@auth_payload['scope']).split(' ') & (SCOPES[request.env['PATH_INFO']])).any?
    end
  end

  def http_token
    if request.headers['Authorization'].present?
      request.headers['Authorization'].split(' ').last
    end
  end

  def auth_token
    Auth0JsonWebToken::verify(http_token)
  end
end
