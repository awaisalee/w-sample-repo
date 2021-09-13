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

require 'bigbluebutton_api'

module BbbServer
  extend ActiveSupport::Concern
  include BbbApi

  META_LISTED = "gl-listed"

  # Checks if a room is running on the BigBlueButton server.
  def room_running?(bbb_id)
    bbb_server.is_meeting_running?(bbb_id)
  end

  # Returns a list of all running meetings
  def all_running_meetings
    bbb_server.get_meetings
  end

  def get_recordings(meeting_id)
    bbb_server.get_recordings(meetingID: meeting_id)
  end

  def get_multiple_recordings(meeting_ids)
    bbb_server.get_recordings(meetingID: meeting_ids)
  end

  # Returns a URL to join a user into a meeting.
  def join_path(room, name, options = {}, uid = nil)

    # Destroy otp current_session
    current_user.destroy_otp if current_user&.room_otp.present?
    session.delete(:otp_name)

    # Create the meeting, even if it's running
    start_session(room, options)

    # Determine the password to use when joining.
    password = options[:user_is_moderator] ? room.moderator_pw : room.attendee_pw

    # Generate the join URL.
    join_opts = {}
    join_opts[:userID] = uid if uid
    join_opts[:join_via_html5] = true

    bbb_server.join_meeting_url(room.bbb_id, name, password, join_opts)
  end

  # Creates a meeting on the BigBlueButton server.
  def start_session(room, options = {})
    create_options = {
      record: options[:record].to_s,
      logoutURL: options[:meeting_logout_url] || '',
      moderatorPW: room.moderator_pw,
      attendeePW: room.attendee_pw,
      moderatorOnlyMessage: options[:moderator_message],
      muteOnStart: options[:mute_on_start].to_s || "false",
      breakoutRoomsEnabled: options[:breakoutRoomsEnabled],
      "logo": options[:customLogoUrl] || '',
      "meta_#{META_LISTED}": options[:recording_default_visibility].to_s || "false",
      "meta_whistle-origin-version": "1.0",
      "meta_whistle-origin": "WhistleRoom",
      "meta_whistle-origin-server-name": options[:host],
      "meta_roomPassword": room.attendee_pw,
      "meta_inviteMsgPassword": "#{options[:moderator_message]}",
      "meta_meetingUrl": options[:meeting_url],
      "meta_auth-mandatory": options[:auth_mandatory].to_s || "false",
      "meta_auth-multi-factor": options[:auth_multi_factor].to_s || "false",
      "meta_auth-room-key": room.access_code.present?,
      "meta_room-key": room.access_code.to_s,
      "meta_auth-lobby": options[:auth_lobby].to_s || "false",
      "meta_auth-onetime": options[:auth_one_time_invite_link].to_s || "false",
      "meta_encrypt-transit": "true",
      "meta_encrypt-recording": "true",
      "meta_encrypt-content": "true",
      "meta_privacy-record-consent": "true",
      "meta_privacy-data-deletion": "true",
      "meta_owner": options[:owner].to_s || "false",
      "meta_email": options[:owner_email].to_s || "",
      "meta_webinar": options[:listen_only].to_s || "false",
      "meta_google-calendar-url": options[:google_calendar_url] || '',
      "meta_banner-message": options[:banner_message] || ''
    }

    create_options[:guestPolicy] = "ASK_MODERATOR" if options[:require_moderator_approval]
    create_options[:maxParticipants] = options[:maxParticipants] if options[:maxParticipants]
    create_options[:lockSettingsDisableMic] = options[:listen_only]
    create_options[:listenOnlyMode] = options[:listen_only]
    create_options[:forceListenOnly] = options[:listen_only]
    create_options[:enableListenOnly] = options[:listen_only]
    create_options[:lockSettingsLockOnJoin] = true
    create_options[:record] = options[:record]

    # Send the create request.
    begin
      meeting = if room.presentation.attached?
        modules = BigBlueButton::BigBlueButtonModules.new
        url = rails_blob_url(room.presentation).gsub("&", "%26")
        logger.info("Support: Room #{room.uid} starting using presentation: #{url}")
        modules.add_presentation(:url, url)
        bbb_server.create_meeting(room.name, room.bbb_id, create_options, modules)
      else
        bbb_server.create_meeting(room.name, room.bbb_id, create_options)
      end

      unless meeting[:messageKey] == 'duplicateWarning'
        room.update_attributes(sessions: room.sessions + 1, last_session: DateTime.now)
      end
    rescue BigBlueButton::BigBlueButtonException => e
      puts "BigBlueButton failed on create: #{e.key}: #{e.message}"
      raise e
    end
  end

  # Gets the number of recordings for this room
  def recording_count(bbb_id)
    bbb_server.get_recordings(meetingID: bbb_id)[:recordings].length
  end

  # Update a recording from a room
  def update_recording(record_id, meta)
    meta[:recordID] = record_id
    bbb_server.send_api_request("updateRecordings", meta)
  end

  # Deletes a recording from a room.
  def delete_recording(record_id)
    bbb_server.delete_recordings(record_id)
  end

  # Deletes all recordings associated with the room.
  def delete_all_recordings(bbb_id)
    record_ids = bbb_server.get_recordings(meetingID: bbb_id)[:recordings].pluck(:recordID)
    bbb_server.delete_recordings(record_ids) unless record_ids.empty?
  end
end
