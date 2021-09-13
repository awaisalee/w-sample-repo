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

module Joiner
  extend ActiveSupport::Concern

  # Displays the join room page to the user
  def show_user_join
    # Get users name
    @name ||= if current_user
      current_user.full_name
    elsif cookies.encrypted[:guest_user_name]
      cookies.encrypted[:guest_user_name]
    else
      "Guest"
    end

    @search, @order_column, @order_direction, pub_recs =
      public_recordings(@room.bbb_id, params.permit(:search, :column, :direction), true)

    @pagy, @public_recordings = pagy_array(pub_recs)

    @is_guest_user = (@join_name.present? || @name.present?) && !room_authentication_required && (@room.access_code.blank? || (@room.access_code == session[:access_code])) && params[:guest_id].present?
    @is_reloading = request.query_parameters[:reload] == "true"

    render :join
  end

  # create or update cookie to track the three most recent rooms a user joined
  def save_recent_rooms
    if current_user.present?
      recent_room = current_user.recent_rooms.find_or_create_by(room_id: @room.id)
      recent_room.update_column(:last_joined_at, DateTime.now)
    end
  end

  def get_saved_room
    @room_saved ||= current_user.recent_rooms.find_by(room_id: @room.id, saved: true)
  end

  def join_room(opts)
    @room_settings = JSON.parse(@room[:room_settings])

    if room_running?(@room.bbb_id) || @room.owned_by?(current_user)

      # Determine if the user needs to join as a moderator.
      opts[:user_is_moderator] = @room.owned_by?(current_user) || room_setting_with_config("joinModerator") || @shared_room
      opts[:record] = record_meeting
      opts[:require_moderator_approval] = room_setting_with_config("requireModeratorApproval")
      opts[:mute_on_start] = room_setting_with_config("muteOnStart")
      opts[:auth_mandatory] = @room_settings['authMandatory']
      opts[:auth_multi_factor] = @room_settings['authMultiFactor']
      opts[:auth_lobby] = @room_settings['authLobby']
      opts[:auth_one_time_invite_link] = @room_settings['authOneTimeInviteLink']
      opts[:webinar_mode] = @room_settings['webinarMode']
      opts[:banner_message] = @room_settings['bannerMessage'] if @room.uid == ENV['MARKETING_ROOM_URL']

      if current_user
        join_name = params[:room][:join_name] || current_user.full_name rescue current_user.full_name
        redirect_to join_path(@room, join_name, opts, current_user.uid)
      else
        invite_name = params[@room.invite_path].present? ? params[@room.invite_path][:join_name] : nil
        join_name = invite_name || session[:otp_name] || cookies.encrypted[:guest_user_name] || params[:room][:join_name] rescue "Guest"
        redirect_to join_path(@room, join_name, opts, fetch_guest_id)
      end

    elsif !room_running?(@room.bbb_id)
      # We dont need public recording and saved rooms here
      # TODO: Clean up required here later
      # search_params = params[@room.invite_path] || params
      # @search, @order_column, @order_direction, pub_recs =
      #   public_recordings(@room.bbb_id, search_params.permit(:search, :column, :direction), true)
      #
      # @pagy, @public_recordings = pagy_array(pub_recs)
      get_saved_room if current_user

      # They need to wait until the meeting begins.
      render :wait
    else
      return
    end
  end

  def incorrect_user_domain
    Rails.configuration.loadbalanced_configuration && @room.owner.provider != @user_domain
  end

  # Default, unconfigured meeting options.
  def default_meeting_options
    invite_msg = I18n.t("invite_message")
    is_owner = @room.owned_by?(current_user) rescue false
    webinar_mode = JSON.parse(@room.room_settings)['webinarMode'] rescue false
    room_invite_path = @room.access_code.present? ? room_path(@room, pwd: BCrypt::Password.create(@room.access_code)) : room_path(@room)
    {
      user_is_moderator: false,
      meeting_logout_url: request.base_url + logout_room_path(@room),
      meeting_recorded: true,
      moderator_message: "#{request.base_url + room_invite_path}",
      host: request.host,
      recording_default_visibility: @settings.get_value("Default Recording Visibility") == "public",
      meeting_url: (request.base_url + room_path(@room)).to_s,
      custom_logo_url: @room.owner.brand_image.to_s || '',
      owner: is_owner,
      listen_only: webinar_mode,
      force_listen_only: webinar_mode,
      google_calendar_url: google_calendar_url
    }
  end

  private

  def fetch_guest_id
    return cookies[:guest_id] if cookies[:guest_id].present?

    guest_id = "gl-guest-#{SecureRandom.hex(12)}"

    cookies[:guest_id] = {
      value: guest_id,
      expires: 1.day.from_now
    }

    guest_id
  end

  def google_calendar_url
    "http://calendar.google.com/calendar/r/eventedit?text=#{@room.name}&location=#{room_url(@room)}&details=You have been invited to the session.#{@room.access_code.blank? ? '' : ("%0ATo join the session use key: " + @room.access_code)}"
  end
end
