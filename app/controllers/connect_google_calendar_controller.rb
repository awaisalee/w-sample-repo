require 'google/apis/calendar_v3'

class ConnectGoogleCalendarController < ApplicationController
  def redirect
    client = Signet::OAuth2::Client.new(client_options)
    redirect_to client.authorization_uri.to_s
  end

  def callback
    unless params[:error].present?
      client = Signet::OAuth2::Client.new(client_options)
      client.code = params[:code]
      response = client.fetch_access_token!
      save_token(response)
    end
    redirect_to root_path
  end

  private

  def save_token(response)
    token = current_user.tokens.find_or_initialize_by(provider: 'google_calendar')
    token.access_token = response['access_token']
    token.expires_at = Time.now.to_i + response['expires_in'].to_i
    token.refresh_token = response['refresh_token'] if response['refresh_token'].present?
    current_user.update(integrated_google_calendar: true) if token.save
  end

  def client_options
    {
      client_id: ENV['GOOGLE_OAUTH2_ID'],
      client_secret: ENV['GOOGLE_OAUTH2_SECRET'],
      authorization_uri: 'https://accounts.google.com/o/oauth2/auth',
      token_credential_uri: 'https://accounts.google.com/o/oauth2/token',
      scope: 'https://www.googleapis.com/auth/calendar.readonly',
      redirect_uri: calendar_callback_url
    }
  end
end
