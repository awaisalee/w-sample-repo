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
#
require 'google/api_client/client_secrets.rb'
require 'google/apis/calendar_v3'

class RoomsController < ApplicationController
  include RoomsHelper
  include Pagy::Backend
  include Recorder
  include Joiner
  include Populator
  include Emailer

  before_action :validate_accepted_terms, unless: -> { !Rails.configuration.terms }
  before_action :validate_verified_email, except: [:show, :join, :join_session],
                unless: -> { !Rails.configuration.enable_email_verification }
  before_action :find_room, except: [:create, :join_specific_room, :cant_create_rooms, :join_session]
  before_action :checked_for_auth_user, only: [:show, :join]
  before_action :verify_room_ownership_or_admin_or_shared, only: [:start, :shared_access]
  before_action :verify_room_ownership_or_admin, only: [:update_settings, :destroy, :preupload_presentation, :remove_presentation]
  before_action :verify_room_ownership_or_shared, only: [:remove_shared_access]
  # before_action :verify_room_owner_verified, only: [:show, :join], unless: -> { !Rails.configuration.enable_email_verification }
  before_action :verify_room_owner_valid, only: [:show, :join]
  before_action :verify_user_not_admin, only: [:show, :join_session]
  skip_before_action :verify_authenticity_token, only: [:join]

  # POST /
  def create
    # Return to root if user is not signed in
    return redirect_to root_path unless current_user

    # Check if the user has not exceeded the room limit
    return redirect_to current_user.main_room, flash: { alert: I18n.t("room.room_limit") } if room_limit_exceeded

    # Create room
    @room = Room.new(name: room_params[:name], access_code: room_params[:access_code])
    @room.owner = current_user
    @room.room_settings = create_room_settings_string(room_params)

    # Save the room and redirect if it fails
    return redirect_to current_user.main_room, flash: { alert: I18n.t("room.create_room_error") } unless @room.save

    logger.info "Support: #{current_user.email} has created a new room #{@room.uid}."

    # Redirect to room is auto join was not turned on
    return redirect_to @room,
      flash: { success: I18n.t("room.create_room_success") } unless room_params[:auto_join] == "1"

    # Start the room if auto join was turned on
    start
  end

  # GET /:room_uid
  def show
    @room_settings = JSON.parse(@room[:room_settings])
    @anyone_can_start = room_setting_with_config("anyoneCanStart")
    @room_running = room_running?(@room.bbb_id)
    @shared_room = room_shared_with_user
    @show_host_button = @current_user.present? ? @current_user.has_monthly_sessions? : false

    # If its the current user's room
    if current_user && (@room.owned_by?(current_user) || @shared_room)
      get_recent_rooms
      # If the user is trying to access their own room but is not allowed to
      if @room.owned_by?(current_user) && !current_user.role.get_permission("can_create_rooms")
        return redirect_to cant_create_rooms_path
      end

      # User is allowed to have rooms
      @search, @order_column, @order_direction, recs =
        recordings(@room.bbb_id, params.permit(:search, :column, :direction), true)

      @user_list = shared_user_list if shared_access_allowed

      @pagy, @recordings = pagy_array(recs)
      get_appointments
      @google_events_list = current_user.provider == "google" && current_user.integrated_google_calendar ? get_calendar_events : []
      @next_appointment = @appointments.where("start_date >= ?", DateTime.now).reorder('start_date ASC').limit(1)&.first

    else

      if params[:pwd].present? && @room.access_code.present?
        begin
          if BCrypt::Password.new(params[:pwd]) == @room.access_code
            session[:access_code] = @room.access_code
            show_user_join
            return
          else
            flash.now[:alert] = I18n.t("room.invalid_pwd")
          end
        rescue
          return redirect_to cant_create_rooms_path, alert: I18n.t("room.no_room.invalid_room_uid")
        end
      end

      return redirect_to root_path, flash: { alert: I18n.t("room.invalid_provider") } if incorrect_user_domain
      if current_user.present?
        send_room_otp_key_email if @room_settings['authMultiFactor'] && current_user.room_otp.blank?
        get_saved_room
      end
      show_user_join
    end
  end

  # GET /rooms
  def cant_create_rooms
    return redirect_to root_path unless current_user
    shared_rooms = current_user.shared_rooms

    if current_user.shared_rooms.empty?
      # Render view for users that cant create rooms
      get_recent_rooms
      render :cant_create_rooms
    else
      redirect_to shared_rooms[0]
    end
  end

  # POST /:room_uid
  def join
    session[:access_code] = params[@room.invite_path][:access_code] if params[@room.invite_path] && params[@room.invite_path][:access_code].present?
    safely_join_room
  end

  def save_room
    if current_user.present?
      @saved_room = current_user.recent_rooms.find_or_create_by(room_id: @room.id)
      @saved_room.update_columns(saved: !@saved_room.saved, last_joined_at: DateTime.now)
    end
  end

  # DELETE /:room_uid
  def destroy
    begin
      # Don't delete the users home room.
      raise I18n.t("room.delete.home_room") if @room == @room.owner.main_room
      @room.destroy!
    rescue => e
      flash[:alert] = I18n.t("room.delete.fail", error: e)
    else
      flash[:success] = I18n.t("room.delete.success")
    end

    # Redirect to home room if the redirect_back location is the deleted room
    return redirect_to @current_user.main_room if request.referer == room_url(@room)

    # Redirect to the location that the user deleted the room from
    redirect_back fallback_location: current_user.main_room
  end

  # POST /room/join
  def join_specific_room
    room_uid = params[:join_room][:url].split('/').last

    @room = Room.find_by(uid: room_uid)
    return redirect_to cant_create_rooms_path, alert: I18n.t("room.no_room.invalid_room_uid") unless @room

    redirect_to room_path(@room)
  end

  # POST /:room_uid/start
  def start
    # redirect to account activation path if not yet activated
    return redirect_to(account_activation_path(digest: @room.owner.activation_digest)) unless @room.owner.activated?

    logger.info "Support: #{current_user.email} is starting room #{@room.uid}"

    # Join the user in and start the meeting.
    opts = default_meeting_options
    opts[:user_is_moderator] = true
    opts[:owner_email] = @room.owner.email

    # Include the user's choices for the room settings
    @room_settings = JSON.parse(@room[:room_settings])
    opts[:mute_on_start] = room_setting_with_config("muteOnStart")
    opts[:require_moderator_approval] = room_setting_with_config("requireModeratorApproval") || @room_settings['authLobby']
    opts[:record] = record_meeting
    opts[:customLogoUrl] = @room.owner.brand_image_url.to_s || ''

    # Check for the subscription and change meeting participants limit
    # Participants limit must be

    # Set  Max participants limit is 20 by default
    opts[:maxParticipants] = ENV['MAX_PARTICIPANTS_COMMUNITY']

    if current_user && current_user.subscribed?
      if current_user.subscribe_plan.whistle_plus?
        opts[:maxParticipants] = ENV['MAX_PARTICIPANTS_WHISTLER']
        opts[:record] = true
        opts[:customLogoUrl] = ""
        opts[:breakoutRoomsEnabled] = true
      elsif current_user.subscribe_plan.whistle_pro?
        opts[:maxParticipants] = ENV['MAX_PARTICIPANTS_WHISTLER_PLUS']
        opts[:record] = true
        opts[:customLogoUrl] = @room.owner.brand_image_url.to_s || ""
        opts[:breakoutRoomsEnabled] = true
      end
    else
      opts[:maxParticipants] = ENV['MAX_PARTICIPANTS_COMMUNITY']
      opts[:record] = false
      opts[:customLogoUrl] = ""
      opts[:breakoutRoomsEnabled] = false

      # Decrease count of available sessions for this month
      current_user.decrease_monthly_sessions if current_user.id == @room.owner.id
      if current_user && is_production?
        Analytics.identify(
          user_id: current_user.id,
          traits: {
              email: current_user.email,
              available_sessions: current_user.remaining_monthly_sessions
          }
        )
      end

    end

    opts[:auth_mandatory] = @room_settings['authMandatory']
    opts[:auth_multi_factor] = @room_settings['authMultiFactor']
    opts[:auth_lobby] = @room_settings['authLobby']
    opts[:auth_one_time_invite_link] = @room_settings['authOneTimeInviteLink']
    opts[:webinar_mode] = @room_settings['webinarMode']
    opts[:banner_message] = @room_settings['bannerMessage'] if @room.uid == ENV['MARKETING_ROOM_URL']

    begin
      redirect_to join_path(@room, current_user.full_name, opts, current_user.uid)
    rescue BigBlueButton::BigBlueButtonException => e
      logger.error("Support: #{@room.uid} start failed: #{e}")

      redirect_to room_path, alert: I18n.t(e.key.to_s.underscore, default: I18n.t("bigbluebutton_exception"))
    end

    # Notify users that the room has started.
    # Delay 5 seconds to allow for server start, although the request will retry until it succeeds.
    NotifyUserWaitingJob.set(wait: 5.seconds).perform_later(@room)
  end

  # POST /:room_uid/update_settings
  def update_settings
    begin
      options = params[:room].nil? ? params : params[:room]
      raise "Room name can't be blank" if options[:name].present? && options[:name].blank?

      # Update the rooms values
      room_settings_string = options[:name].present? ? @room.room_settings : create_room_settings_string(options)
      room_name = options[:name].present? ? options[:name] : @room.name

      @room.update_attributes(
        name: room_name,
        room_settings: room_settings_string,
        access_code: options[:access_code]
      )

      flash[:success] = I18n.t("room.update_settings_success")
    rescue => e
      logger.error "Support: Error in updating room settings: #{e}"
      flash[:alert] = I18n.t("room.update_settings_error")
    end

    respond_to do |format|
      format.js
      format.html { redirect_back fallback_location: room_path(@room) }
    end
  end

  # GET /:room_uid/current_presentation
  def current_presentation
    attached = @room.presentation.attached?

    # Respond with JSON object of presentation name
    respond_to do |format|
      format.json { render body: { attached: attached, name: attached ? @room.presentation.filename.to_s : "" }.to_json }
    end
  end

  # POST /:room_uid/preupload_presenstation
  def preupload_presentation
    begin
      raise "Invalid file type" unless valid_file_type
      @room.presentation.attach(room_params[:presentation])

      flash[:success] = I18n.t("room.preupload_success")
    rescue => e
      logger.error "Support: Error in updating room presentation: #{e}"
      flash[:alert] = I18n.t("room.preupload_error")
    end

    redirect_back fallback_location: room_path(@room)
  end

  # POST /:room_uid/remove_presenstation
  def remove_presentation
    begin
      @room.presentation.purge

      flash[:success] = I18n.t("room.preupload_remove_success")
    rescue => e
      logger.error "Support: Error in removing room presentation: #{e}"
      flash[:alert] = I18n.t("room.preupload_remove_error")
    end

    redirect_back fallback_location: room_path(@room)
  end

  # POST /:room_uid/update_shared_access
  def shared_access
    begin
      current_list = @room.shared_users.pluck(:id)
      new_list = User.where(uid: params[:add]).pluck(:id)

      # Get the list of users that used to be in the list but were removed
      users_to_remove = current_list - new_list
      # Get the list of users that are in the new list but not in the current list
      users_to_add = new_list - current_list

      # Remove users that are removed
      SharedAccess.where(room_id: @room.id, user_id: users_to_remove).delete_all unless users_to_remove.empty?

      # Add users that are added
      users_to_add.each do |id|
        SharedAccess.create(room_id: @room.id, user_id: id)
      end

      flash[:success] = I18n.t("room.shared_access_success")
    rescue => e
      logger.error "Support: Error in updating room shared access: #{e}"
      flash[:alert] = I18n.t("room.shared_access_error")
    end

    redirect_back fallback_location: room_path
  end

  # POST /:room_uid/remove_shared_access
  def remove_shared_access
    begin
      SharedAccess.find_by!(room_id: @room.id, user_id: current_user).destroy
      flash[:success] = I18n.t("room.remove_shared_access_success")
    rescue => e
      logger.error "Support: Error in removing room shared access: #{e}"
      flash[:alert] = I18n.t("room.remove_shared_access_error")
    end

    redirect_to current_user.main_room
  end

  # GET /:room_uid/shared_users
  def shared_users
    # Respond with JSON object of users that have access to the room
    respond_to do |format|
      format.json { render body: @room.shared_users.to_json }
    end
  end

  # GET /:room_uid/room_settings
  def room_settings
    # Respond with JSON object of the room_settings
    respond_to do |format|
      format.json { render body: @room.room_settings }
    end
  end

  # GET /:room_uid/security_settings
  def security_settings
    redirect_to home_page unless @room.owned_by?(current_user)
  end

  # GET /:room_uid/logout
  def logout
    logger.info "Support: #{current_user.present? ? current_user.email : 'Guest'} has left room #{@room.uid}"

    # Redirect the correct page.
    redirect_to @room
  end

  # POST /:room_uid/login
  def login
    @join_name = params[:room][:join_name]
    session[:otp_name] = @join_name
    cookies.encrypted[:guest_user_name] = @join_name

    @guest_id = fetch_guest_id if @join_name.present? && !room_authentication_required && (@room.access_code.blank? || (@room.access_code == session[:access_code]))

    join and return if @room.uid == ENV['MARKETING_ROOM_URL']
    redirect_to room_path(@room.uid, session_event: @session_event.try(:id), guest_id: @guest_id)
  end

  # POST /:room_uid/login_with_otp
  def login_with_otp
    session[:auth_multi_factor_otp] = room_params[:auth_multi_factor_otp]
    flash[:alert] = 'Room OTP required!' if session[:auth_multi_factor_otp] != current_user&.room_otp

    redirect_to room_path(@room.uid, session_event: @session_event.try(:id))
  end

  def send_room_otp_key
    send_room_otp_key_email
    # Respond with JS
    respond_to do |format|
      format.js
    end
  end

  def join_session
    redirect_to home_page and return unless current_user
    get_appointments
  end

  def google_calendar
    respond_to do |format|
      format.js
    end
  end

  private

  def safely_join_room
    @shared_room = room_shared_with_user
    settings = JSON.parse(@room.room_settings)

    unless @room.owned_by?(current_user) || @shared_room
      # Don't allow users to join unless they have a valid access code or the room doesn't have an access code
      if @room.access_code && !@room.access_code.empty? && @room.access_code != session[:access_code]
        return redirect_to room_path(@room, session_event: @session_event.try(:id)), flash: { alert: I18n.t("room.access_code_required") }
      end

      # Don't allow users to join unless they have a valid otp key
      if settings['authMultiFactor'] && current_user.room_otp != session[:auth_multi_factor_otp]
        return redirect_to room_path(@room, session_event: @session_event.try(:id)), flash: { alert: 'Room OTP required!' }
      end

    end

    # create or update cookie with join name
    cookies.encrypted[:guest_user_name] = @join_name unless cookies.encrypted[:guest_user_name] == @join_name

    save_recent_rooms

    logger.info "Support: #{current_user.present? ? current_user.email : @join_name} is joining room #{@room.uid}"
    join_room(default_meeting_options)
  end

  def create_room_settings_string(options)
    room_settings = {
      "muteOnStart": options[:mute_on_join] == "1",
      "requireModeratorApproval": options[:require_moderator_approval] == "1",
      "anyoneCanStart": options[:anyone_can_start] == "1",
      "joinModerator": options[:all_join_moderator] == "1",
      "recording": options[:recording] == "1",
      "authMandatory": options[:auth_mandatory] == "1",
      "authMultiFactor": options[:auth_multi_factor] == "1",
      "authLobby": options[:auth_lobby] == "1",
      "authOneTimeInviteLink": options[:auth_one_time_invite_link] == "1",
      "webinarMode": options[:webinar_mode] == "1"
    }

    room_settings.to_json
  end

  def room_params
    params.require(:room).permit(
      :name,
      :auto_join,
      :mute_on_join,
      :access_code,
      :require_moderator_approval,
      :anyone_can_start,
      :all_join_moderator,
      :recording,
      :presentation,
      :auth_mandatory,
      :auth_multi_factor,
      :auth_lobby,
      :auth_one_time_invite_link,
      :auth_multi_factor_otp,
      :webinar_mode
    )
  end

  # Find the room from the uid.
  def find_room
    @room = Room.includes(:owner).find_by(uid: params[:room_uid])

    unless @room.present?
      backup_room = RoomUrlBackup.find_by!(uid: params[:room_uid])
      raise "Room not found" if backup_room.room.deleted?
      return redirect_to room_path(backup_room.room.uid, request.query_parameters)
    end

    @session_event = Appointment.find_by(id: request.query_parameters[:session_event]) if request.query_parameters[:session_event].present?
  end

  def get_recent_rooms
    @recent_rooms = current_user.recent_rooms
  end

  def get_appointments
    @appointments = Appointment.get_appointments(current_user).where("start_date <= ?", DateTime.now.end_of_day)
  end

  def get_calendar_events
    #Google calander events
    #
    token = current_user.google_calendar_token
    # Initialize Google Calendar API
    service = Google::Apis::CalendarV3::CalendarService.new
    # Use google keys to authorize
    service.authorization = token.google_secret.to_authorization
    # Request for a new access token just incase it expired
    if token.expired?
      new_access_token = service.authorization.refresh!
      token.access_token = new_access_token['access_token']
      token.expires_at =
          Time.now.to_i + new_access_token['expires_in'].to_i
      token.save
    end
    # Get a list of calendars
    calendar_list = service.list_calendar_lists.items[0]
    @events_list = service.list_events(calendar_list.id, time_min: Date.today.beginning_of_day.in_time_zone(current_user.timezone).to_datetime.rfc3339, time_max: Date.today.end_of_day.in_time_zone(current_user.timezone).to_datetime.rfc3339).items
  end

  # Ensure the user either owns the room or is an admin of the room owner or the room is shared with him
  def verify_room_ownership_or_admin_or_shared
    return redirect_to root_path unless @room.owned_by?(current_user) ||
                                        room_shared_with_user ||
                                        current_user&.admin_of?(@room.owner, "can_manage_rooms_recordings")
  end

  # Ensure the user either owns the room or is an admin of the room owner
  def verify_room_ownership_or_admin
    return redirect_to root_path if !@room.owned_by?(current_user) &&
                                    !current_user&.admin_of?(@room.owner, "can_manage_rooms_recordings")
  end

  def send_room_otp_key_email
    current_user.generate_otp
    send_user_room_otp(current_user, @room)
  end

  # Ensure the user owns the room or is allowed to start it
  def verify_room_ownership_or_shared
   return redirect_to root_path unless @room.owned_by?(current_user) || room_shared_with_user
  end

  def validate_accepted_terms
    redirect_to terms_path if current_user && !current_user&.accepted_terms
  end

  def validate_verified_email
    redirect_to account_activation_path(digest: current_user.activation_digest) if current_user && !current_user&.activated?
  end

  def verify_room_owner_verified
    redirect_to root_path, alert: t("room.unavailable") unless @room.owner.activated?
  end

  # Check to make sure the room owner is not pending or banned
  def verify_room_owner_valid
    redirect_to root_path, alert: t("room.owner_banned") if @room.owner.has_role?(:pending) || @room.owner.has_role?(:denied)
  end

  def verify_user_not_admin
    redirect_to admins_path if current_user&.has_role?(:super_admin)
  end

  # Checks if the room is shared with the user and room sharing is enabled
  def room_shared_with_user
    shared_access_allowed ? @room.shared_with?(current_user) : false
  end

  def room_limit_exceeded
    limit = @settings.get_value("Room Limit").to_i

    # Does not apply to admin or users that aren't signed in
    # 15+ option is used as unlimited
    return false if current_user&.has_role?(:admin) || limit == 15

    current_user.rooms.length >= limit
  end
  helper_method :room_limit_exceeded

  def record_meeting
    # If the require consent setting is checked, then check the room setting, else, set to true
    if recording_consent_required?
      room_setting_with_config("recording")
    else
      true
    end
  end

  # Checks if the file extension is allowed
  def valid_file_type
    Rails.configuration.allowed_file_types.split(",")
         .include?(File.extname(room_params[:presentation].original_filename.downcase))
  end

  def checked_for_auth_user
    if room_authentication_required
      flash[:alert] = I18n.t("administrator.site_settings.authentication.user-info")
      cookies[:return_to] = request.url
      render :join and return
    end
  end

  # Gets the room setting based on the option set in the room configuration
  def room_setting_with_config(name)
    config = case name
    when "muteOnStart"
      "Room Configuration Mute On Join"
    when "requireModeratorApproval"
      "Room Configuration Require Moderator"
    when "joinModerator"
      "Room Configuration All Join Moderator"
    when "anyoneCanStart"
      "Room Configuration Allow Any Start"
    when "recording"
      "Room Configuration Recording"
    end

    case @settings.get_value(config)
    when "enabled"
      true
    when "optional"
      @room_settings[name]
    when "disabled"
      false
    end
  end
  helper_method :room_setting_with_config
end
