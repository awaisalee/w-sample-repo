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

module RoomsHelper
  # Helper to generate the path to a Google Calendar event creation
  # It will have its title set as the room name, and the location as the URL to the room
  def formatted_google_calendar_path
    "http://calendar.google.com/calendar/r/eventedit?text=#{@room.name}&location=#{room_url(@room)}&details=#{calendar_invite_msg}"
  end

  def calendar_invite_msg
    access_code = @room.access_code != "" ? "%0ATo join the session use key: #{@room.access_code}" : ""
    details = "You have been invited to the session." + access_code
    details
  end

  def room_authentication_required
    settings = JSON.parse(@room.room_settings)
    settings["authMandatory"] == true && current_user.nil?
  end

  def current_room_exceeds_limit(room)
    # Get how many rooms need to be deleted to reach allowed room number
    limit = @settings.get_value("Room Limit").to_i

    return false if current_user&.has_role?(:admin) || limit == 15

    @diff = current_user.rooms.count - limit
    @diff.positive? && current_user.rooms.pluck(:id).index(room.id) + 1 > limit
  end

  def room_configuration(name)
    @settings.get_value(name)
  end

  def preupload_allowed?
    @settings.get_value("Preupload Presentation") == "true"
  end

  def display_joiner_consent
    # If the require consent setting is checked, then check the room setting, else, set to false
    if recording_consent_required?
      room_setting_with_config("recording")
    else
      false
    end
  end

  # Array of recording formats not to show for public recordings
  def hidden_format_public
    ENV.fetch("HIDDEN_FORMATS_PUBLIC", "").split(",")
  end

  def time_diff(start_time, end_time)
    seconds_diff = (start_time - end_time).to_i.abs

    days = seconds_diff / 86400
    seconds_diff -= days * 86400

    hours = seconds_diff / 3600
    seconds_diff -= hours * 3600

    minutes = seconds_diff / 60
    seconds_diff -= minutes * 60

    seconds = seconds_diff

    duration = ""
    duration = duration + "#{days} days " if days > 0
    duration = duration + "#{hours} hrs " if hours > 0
    duration = duration + "#{minutes} min " if minutes > 0
    duration = "now" if duration.blank?
    duration
   end

  def room_multi_factor_required
    settings = JSON.parse(@room.room_settings)
    settings["authMultiFactor"]
  rescue
    false
  end

  def parse_session_date(appointment, fixed_date=false)
    s_time = fixed_date ? appointment.start_date.strftime("%I:%M %p") : appointment.start_date.strftime("%a, %b %e, %I:%M %p")
    e_time = appointment.end_date.strftime("%I:%M %p")
    "#{s_time} - #{e_time}"
  end

  def parse_google_cal_date(appointment, fixed_date=false)
    s_time = fixed_date ? appointment.start.date_time.strftime("%I:%M %p") : appointment.start.date_time.strftime("%a, %b %e, %I:%M %p")
    e_time = appointment.end.date_time.strftime("%I:%M %p")
    "#{s_time} - #{e_time}"
  end

  def show_recurrence_event(appointment, query_date, fixed_date=false)
    s_time = fixed_date ? appointment.start.date_time.strftime("%I:%M %p") : "#{query_date.strftime("%a, %b %e,")} #{appointment.start.date_time.strftime(" %I:%M %p")}"
    e_time = appointment.end.date_time.strftime("%I:%M %p")
    "#{s_time} - #{e_time}"
  end

  def onetime_room_link
    pwd = @room.access_code.present? ? "?pwd=" + BCrypt::Password.create(@room.access_code) : ''
    request.base_url + @room.invite_path + pwd
  end
  
end
