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

module RecordingsHelper
  # Helper for converting BigBlueButton dates into the desired format.
  def recording_date(date)
    I18n.l date, format: "%B %d, %Y"
  end

  # Helper for converting BigBlueButton dates into a nice length string.
  def recording_length(playbacks)
    # Looping through playbacks array and returning first non-zero length value
    playbacks.each do |playback|
      length = playback[:length]
      return recording_length_string(length) unless length.zero?
    end
    # Return '< 1 min' if length values are zero
    "< 1 min"
  end

  def get_recording_download_url(recording_id)
    object_key_name = "#{recording_id}.zip"
    bucket_name = ENV['AWS_BUCKET']
    aws_access_key = ENV['AWS_ACCESS_KEY_ID']
    aws_secret_key = ENV['AWS_SECRET_ACCESS_KEY']
    region = ENV['AWS_REGION']
    aws_resource = Aws::S3::Resource::new(
        access_key_id: aws_access_key,
        secret_access_key: aws_secret_key,
        region: region
    )
    recording_url = aws_resource.bucket(bucket_name).object(object_key_name).presigned_url(:get, expires_in: 86400,
                                                                                      response_content_disposition: 'attachment')
    return recording_url
  end


  def show_download_button(end_date_time)
    depricated_date = Date.new(2021,3,4)
    end_date_time > depricated_date ? true : false
  end

  # Prevents single images from erroring when not passed as an array.
  def safe_recording_images(images)
    Array.wrap(images)
  end

  def room_uid_from_bbb(bbb_id)
    Room.find_by(bbb_id: bbb_id)[:uid]
  end

  # returns whether recording thumbnails are enabled on the server
  def recording_thumbnails?
    Rails.configuration.recording_thumbnails
  end

  private

  # Returns length of the recording as a string
  def recording_length_string(len)
    if len > 60
      "#{(len / 60).to_i} h #{len % 60} min"
    else
      "#{len} min"
    end
  end
end
