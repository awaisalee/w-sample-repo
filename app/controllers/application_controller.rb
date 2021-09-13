# frozen_string_literal: true

# BigBlueButton open source conferencing system - http://www.bigbluebutton.org/.
#
# Copyright (c) 2018 BigBlueButton Inc. and by respective authors (see below).
#
# This program is free software; you can redistribute it and/or modify it under the
# terms of the GNU Lesser General Public License as published by the Free Software
# Foundation; either version 3.0 of the License, or (at your option) any later
# version.
#
# BigBlueButton is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License along
# with BigBlueButton; if not, see <http://www.gnu.org/licenses/>.

require 'google/api_client/client_secrets.rb'
require 'google/apis/people_v1'
require 'google/apis/calendar_v3'

class ApplicationController < ActionController::Base
  attr_reader :current_user
  include BbbServer
  include Errors
  include Authenticator

  before_action :block_unknown_hosts, :redirect_to_https, :set_user_domain, :set_user_settings, :maintenance_mode?, :migration_error?, :user_locale, :check_admin_password, :check_user_role

  before_action :check_profile_complete, if: :current_user
  before_action :update_segment_hubspot, if: :current_user
  before_action :check_google_api_access, if: :current_user
  before_action :handle_whistle_plus_trial, if: :current_user

  # Disabled Browser detection
  # , :detect_browser?
  around_action :set_time_zone, if: :current_user

  protect_from_forgery with: :exceptions

  # Retrieves the current user.
  def current_user
    session[:user_id] ||= cookies[:auth_token]
    @current_user ||= User.includes(:role, :main_room).find_by(id: session[:user_id])

    if Rails.configuration.loadbalanced_configuration
      unless @current_user.nil?
        if !@current_user.has_role?(:super_admin) &&
           @current_user.provider != @user_domain
           @current_user = nil
           session.clear
        end
      end
    end
    # Check and create monthly sessions
    @current_user.has_monthly_sessions? unless @current_user.nil?

    @current_user
  end

  helper_method :current_user

  def user_signed_in?
    !!current_user
  end
  helper_method :user_signed_in?

  def bbb_server
    @bbb_server ||= Rails.configuration.loadbalanced_configuration ? bbb(@user_domain) : bbb("greenlight")
  end

  # Block unknown hosts to mitigate host header injection attacks
  def block_unknown_hosts
    return if Rails.configuration.hosts.blank?
    raise UnsafeHostError, "#{request.host} is not a safe host" unless Rails.configuration.hosts.include?(request.host)
  end

  # Force SSL
  def redirect_to_https
    if Rails.configuration.loadbalanced_configuration && request.headers["X-Forwarded-Proto"] == "http"
      redirect_to protocol: "https://"
    end
  end

  # Sets the user domain variable
  def set_user_domain
    if Rails.env.test? || !Rails.configuration.loadbalanced_configuration
      @user_domain = "greenlight"
    else
      @user_domain = parse_user_domain(request.host)

      check_provider_exists
    end
  end

  # Sets the settinfs variable
  def set_user_settings
    @settings = Setting.includes(:features).find_or_create_by(provider: @user_domain)
  end

  # Redirects the user to a Maintenance page if turned on
  def maintenance_mode?
    if ENV["MAINTENANCE_MODE"] == "true"
      render "errors/greenlight_error", status: 503, formats: :html,
        locals: {
          status_code: 503,
          message: I18n.t("errors.maintenance.message"),
          help: I18n.t("errors.maintenance.help"),
        }
    end

    maintenance_string = @settings.get_value("Maintenance Banner").presence || Rails.configuration.maintenance_window
    if maintenance_string.present?
      flash.now[:maintenance] = maintenance_string unless cookies[:maintenance_window] == maintenance_string
    end
  end


  def is_production?
    if ENV["DEPLOYED_ENV"].present? && ENV["DEPLOYED_ENV"] == "production"
      return true
    end
    return false
  end

  def is_development?
    if ENV["DEPLOYED_ENV"].present? && ENV["DEPLOYED_ENV"] == "development"
      return true
    end
    return false
  end

  def is_testing?
    if ENV["DEPLOYED_ENV"].present? && ENV["DEPLOYED_ENV"] == "testing"
      return true
    end
    return false
  end


  def detect_browser?
    if Rails.env.production?
      # redirect to home page if browser is not supported
      render "main/_landing" unless modern_browser?
    end
  end

  # Show an information page when migration fails and there is a version error.
  def migration_error?
    render :migration_error, status: 500 unless ENV["DB_MIGRATE_FAILED"].blank?
  end

  # Sets the appropriate locale.
  def user_locale(user = current_user)
    locale = if user && user.language != 'default'
      user.language
    else
      http_accept_language.language_region_compatible_from(I18n.available_locales)
    end

    begin
      I18n.locale = locale.tr('-', '_') unless locale.nil?
    rescue
      # Default to English if there are any issues in language
      logger.error("Support: User locale is not supported (#{locale}")
      I18n.locale = "en"
    end
  end

  # Checks to make sure that the admin has changed his password from the default
  def check_admin_password
    if current_user&.has_role?(:admin) && current_user.email == "admin@example.com" &&
       current_user&.greenlight_account? && current_user&.authenticate(Rails.configuration.admin_password_default)

      flash.now[:alert] = I18n.t("default_admin",
        edit_link: change_password_path(user_uid: current_user.uid)).html_safe
    end
  end

  # Checks if the user is banned and logs him out if he is
  def check_user_role
    if current_user&.has_role? :denied
      session.delete(:user_id)
      redirect_to root_path, flash: { alert: I18n.t("registration.banned.fail") }
    elsif current_user&.has_role? :pending
      session.delete(:user_id)
      redirect_to root_path, flash: { alert: I18n.t("registration.approval.fail") }
    end
  end

  # Relative root helper (when deploying to subdirectory).
  def relative_root
    Rails.configuration.relative_url_root || ""
  end
  helper_method :relative_root

  # Determines if the BigBlueButton endpoint is configured (or set to default).
  def bigbluebutton_endpoint_default?
    return false if Rails.configuration.loadbalanced_configuration
    Rails.configuration.bigbluebutton_endpoint_default == Rails.configuration.bigbluebutton_endpoint
  end
  helper_method :bigbluebutton_endpoint_default?

  def allow_greenlight_accounts?
    return Rails.configuration.allow_user_signup unless Rails.configuration.loadbalanced_configuration
    return false unless @user_domain && !@user_domain.empty? && Rails.configuration.allow_user_signup
    return false if @user_domain == "greenlight"
    # Proceed with retrieving the provider info
    begin
      provider_info = retrieve_provider_info(@user_domain, 'api2', 'getUserGreenlightCredentials')
      provider_info['provider'] == 'greenlight'
    rescue => e
      logger.error "Error in checking if greenlight accounts are allowed: #{e}"
      false
    end
  end
  helper_method :allow_greenlight_accounts?

  # Determine if Greenlight is configured to allow user signups.
  def allow_user_signup?
    Rails.configuration.allow_user_signup
  end
  helper_method :allow_user_signup?

  # Gets all configured omniauth providers.
  def configured_providers
    Rails.configuration.providers.select do |provider|
      Rails.configuration.send("omniauth_#{provider}")
    end
  end
  helper_method :configured_providers

  # Indicates whether users are allowed to share rooms
  def shared_access_allowed
    @settings.get_value("Shared Access") == "true"
  end
  helper_method :shared_access_allowed

  # Indicates whether users are allowed to share rooms
  def recording_consent_required?
    @settings.get_value("Require Recording Consent") == "true"
  end
  helper_method :recording_consent_required?

  # Returns a list of allowed file types
  def allowed_file_types
    Rails.configuration.allowed_file_types
  end
  helper_method :allowed_file_types

  # Returns the page that the logo redirects to when clicked on
  def home_page
    return root_path unless current_user
    return admins_path if current_user.has_role? :super_admin
    return room_path(current_user.main_room) if current_user.role&.get_permission("can_create_rooms") && current_user.main_room.present?
    cant_create_rooms_path
  end
  helper_method :home_page

  # Parses the url for the user domain
  def parse_user_domain(hostname)
    return hostname.split('.').first if Rails.configuration.url_host.empty?
    Rails.configuration.url_host.split(',').each do |url_host|
      return hostname.chomp(url_host).chomp('.') if hostname.include?(url_host)
    end
    ''
  end

  # Include user domain in lograge logs
  def append_info_to_payload(payload)
    super
    payload[:host] = @user_domain
  end

  # Manually handle BigBlueButton errors
  rescue_from BigBlueButton::BigBlueButtonException do |ex|
    logger.error "BigBlueButtonException: #{ex}"
    render "errors/bigbluebutton_error"
  end

  # Manually deal with 401 errors
  rescue_from CanCan::AccessDenied do |_exception|
    if current_user
      render "errors/greenlight_error"
    else
      # Store the current url as a cookie to redirect to after sigining in
      cookies[:return_to] = request.url

      # Get the correct signin path
      path = if allow_greenlight_accounts?
        signin_path
      elsif Rails.configuration.loadbalanced_configuration
        "#{Rails.configuration.relative_url_root}/auth/bn_launcher"
      else
        signin_path
      end

      redirect_to path
    end
  end

  # Segment Marketing Info Sending
  def segment_upgrade_date(email)
    user = User.find_by_email(email)
    Analytics.identify(
      user_id: user.id,
      traits: {
        first_name: user.first_name,
          last_name: user.first_name,
          email: user.email,
          available_sessions: user.remaining_monthly_sessions,
          host: user.manager? ? "Co Host" : "Host",
          plan: user.plan_name.humanize,
          plan_duration: user.subscribe_plan&.interval.nil? ? 0 : user.subscribe_plan&.interval,
          account_type: user.account_type,
          upgrade_date: DateTime.now.iso8601,
          org_role: user.business_role || '',
          number_of_licenses: user.no_of_licenses || ''
      })
  end

  def update_segment_hubspot
    # Push data to Segment-Hubspot
    # TODO : Defaults to Whistle Community User
    if current_user.id && is_production?
      identify_action = Analytics.identify(
        user_id: current_user.id,
        traits: {
          first_name: current_user.first_name,
            last_name: current_user.first_name,
            email: current_user.email,
            available_sessions: current_user.remaining_monthly_sessions,
            host: current_user.manager? ? "Co Host" : "Host",
            plan: current_user.plan_name.humanize,
            plan_duration: current_user.subscribe_plan&.interval.nil? ? 0 : current_user.subscribe_plan&.interval,
            account_type: current_user.account_type,
            org_role: current_user.business_role || '',
            number_of_licenses: current_user.no_of_licenses || '',
            account_creation_date: current_user.main_room.nil? ? current_user.created_at.iso8601 : current_user.main_room.created_at.iso8601,
            account_creation_type: current_user.provider,
        })
      puts identify_action
    end
  end

  def enable_pricing?
    Rails.configuration.enable_pricing.to_s == "true"
  end
  helper_method :enable_pricing?

  def user_timezone_offset
    Time.now.in_time_zone(current_user.try(:timezone))&.formatted_offset
  end
  helper_method :user_timezone_offset

  def modern_browser?
    browser = Browser.new(request.env["HTTP_USER_AGENT"])
    [
      browser.chrome?(">= 72"),
      browser.firefox?(">= 63"),
      browser.edge?(">= 79"),
      browser.ie?(">= 11") && !browser.compatibility_view?,
      browser.safari?(">= 10"),
      browser.opera?(">= 50"),
      browser.electron?(">= 50"),
      browser.yandex?(">= 19"),
      browser.samsung_browser?(">= 10"),
      browser.safari_webapp_mode?
    ].any?
  end
  helper_method :modern_browser?

  private

  def check_provider_exists
    # Checks to see if the user exists
    begin
      # Check if the session has already checked that the user exists
      # and return true if they did for this domain
      return if session[:provider_exists] == @user_domain

      retrieve_provider_info(@user_domain, 'api2', 'getUserGreenlightCredentials')

      # Add a session variable if the provider exists
      session[:provider_exists] = @user_domain
    rescue => e
      logger.error "Error in retrieve provider info: #{e}"
      # Use the default site settings
      @user_domain = "greenlight"
      @settings = Setting.find_or_create_by(provider: @user_domain)

      if e.message.eql? "No user with that id exists"
        render "errors/greenlight_error", locals: { message: I18n.t("errors.not_found.user_not_found.message"),
          help: I18n.t("errors.not_found.user_not_found.help") }
      elsif e.message.eql? "Provider not included."
        render "errors/greenlight_error", locals: { message: I18n.t("errors.not_found.user_missing.message"),
          help: I18n.t("errors.not_found.user_missing.help") }
      elsif e.message.eql? "That user has no configured provider."
        render "errors/greenlight_error", locals: { status_code: 501,
          message: I18n.t("errors.no_provider.message"),
          help: I18n.t("errors.no_provider.help") }
      else
        render "errors/greenlight_error", locals: { status_code: 500, message: I18n.t("errors.internal.message"),
          help: I18n.t("errors.internal.help"), display_back: true }
      end
    end
  end

  def set_time_zone(&block)
    Time.use_zone(current_user.timezone, &block)
  end

  def check_profile_complete
    return if (%w[users sessions].include?(controller_path) and %w[edit update destroy].include?(action_name)) || current_user.full_name.present?
    redirect_to edit_user_path(current_user)
  end

  def check_google_api_access
    if current_user.provider == 'google'
      begin
        contact_service = google_api_access('contact') if current_user.integrated_google_contact
        google_api_access('calendar') if current_user.integrated_google_calendar

        if !current_user.google_contacts.any? || current_user.google_contact_sync_time + 2.minutes <= Time.now
          sync_google_contact(contact_service) if current_user.integrated_google_contact
        end
      rescue => e
        logout
        redirect_to root_path, alert: "Session expired, login with Google."
      end
    end
  end

  def google_api_access(type)
     begin
      gettoken = current_user.google_token
      if type == 'contact'
        gettoken = current_user.google_contact_token
        service = Google::Apis::PeopleV1::PeopleServiceService.new
      elsif type == 'calendar'
        gettoken = current_user.google_calendar_token
        service = Google::Apis::CalendarV3::CalendarService.new
      end
      service.authorization = gettoken.google_secret.to_authorization
      # Request for a new access token just incase it expired

      if gettoken.expired?
        new_access_token = service.authorization.refresh!
        gettoken.access_token = new_access_token['access_token']
        gettoken.expires_at =
            Time.now.to_i + new_access_token['expires_in'].to_i
            gettoken.save
        # Authorise service with new access_token
        service.authorization = gettoken.google_secret.to_authorization
      end

      service.authorization = gettoken.google_secret.to_authorization
      service
    rescue => exception
      if type == 'contact'
        current_user.update(integrated_google_contact: false)
      elsif type == 'calendar'
        current_user.update(integrated_google_calendar: false)
      end
    end
  end

  def sync_google_contact(service)
    fields = "emailAddresses,names,phoneNumbers"
    person_contacts = service.list_person_connections( "people/me", person_fields: fields).connections
    other_contacts = service.list_other_contacts(read_mask: fields).other_contacts

    begin
      directory_source = ["DIRECTORY_SOURCE_TYPE_DOMAIN_CONTACT", "DIRECTORY_SOURCE_TYPE_DOMAIN_PROFILE"]
      directory_contacts = service.list_person_directory_people(read_mask: fields, sources: directory_source).people
    rescue
      directory_contacts = []
    end

    contact_list = [other_contacts, directory_contacts, person_contacts]
    contact_list.compact!
    contact_list.flatten!

    #store google contact in database
    contact_list.each do |con|
      if(con.email_addresses&.first&.value.present?)
        contact = current_user.google_contacts.find_by(email_address: con.email_addresses&.first&.value)
        if contact
          contact.update(name: con.names&.first&.display_name, phone_number: con.phone_numbers&.first&.canonical_form)
        else
          GoogleContact.create(name: con.names&.first&.display_name, phone_number: con.phone_numbers&.first&.canonical_form, user_id: current_user.id, email_address: con.email_addresses&.first&.value)
        end
      end
    end

    current_user.update(google_contact_sync_time: Time.now)
  end

  def handle_whistle_plus_trial
    if current_user&.plan_subscription && current_user.subscribe_plan.whistle_plus? && !current_user.whistle_plus_trial_ended
      if current_user.plan_subscription.trial_end.present? && current_user.plan_subscription.trial_end < DateTime.now && !current_user.plan_subscription.cancel_at.present?
        current_user.update(whistle_plus_trial_ended: true)
        current_user.subscription.destroy
      end
    end
  end
end
